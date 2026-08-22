"use strict";

const crypto = require("node:crypto");
const logger = require("firebase-functions/logger");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {
  TEMPLATE_CATALOG,
  WIZARD_SCHEMA_VERSION,
  editableEventForm,
  generateOccurrences,
  normalizeDraftForm,
  occurrenceLimitForTier,
  seriesOccurrenceStart,
  sanitizedDuplicateForm,
  sanitizedTemplateForm,
  timestampDate,
  validatePublishable,
} = require("./wizard-core");

const REGION = "us-central1";
const CALL_OPTIONS = {
  region: REGION,
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
  maxInstances: 30,
};

function requireOrganizer(request) {
  const uid = request.auth?.uid;
  const provider = request.auth?.token?.firebase?.sign_in_provider;
  if (!uid || provider === "anonymous") {
    throw new HttpsError("unauthenticated", "A signed-in organizer account is required.");
  }
  if (!request.app && process.env.FUNCTIONS_EMULATOR !== "true") {
    throw new HttpsError("failed-precondition", "App Check verification is required.");
  }
  return uid;
}

function requireIdentifier(value, label) {
  const normalized = typeof value === "string" ? value.trim() : "";
  if (!/^[A-Za-z0-9_-]{1,160}$/.test(normalized)) {
    throw new HttpsError("invalid-argument", `A valid ${label} is required.`);
  }
  return normalized;
}

function requireRevision(value, fallback = 0) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) return fallback;
  return parsed;
}

async function groupAccess(db, uid, organizationId) {
  if (!organizationId) return {allowed: true, isAdmin: false, organization: null};
  const [organizationSnapshot, memberSnapshot] = await Promise.all([
    db.collection("Organizations").doc(organizationId).get(),
    db.collection("Organizations").doc(organizationId).collection("Members").doc(uid).get(),
  ]);
  if (!organizationSnapshot.exists) return {allowed: false, isAdmin: false, organization: null};
  const organization = organizationSnapshot.data() || {};
  if (organization.createdBy === uid) return {allowed: true, isAdmin: true, organization};
  const member = memberSnapshot.data() || {};
  const approved = String(member.status || "approved").toLowerCase() === "approved";
  const role = String(member.role || "").toLowerCase();
  const isAdmin = ["owner", "admin"].includes(role);
  return {allowed: approved && (organization.allowMemberEventCreation !== false || isAdmin),
    isAdmin, organization};
}

async function tierForUser(db, uid) {
  const subscription = await db.collection("subscriptions").doc(uid).get();
  const data = subscription.data() || {};
  if (data.isActive === true || String(data.status || "").toLowerCase() === "active") {
    const tier = String(data.tier || data.subscriptionTier || "").toLowerCase();
    if (tier === "premium" || tier === "basic") return tier;
  }
  return "free";
}

async function paidCheckoutEnabled(db) {
  const snapshot = await db.collection("AppConfig").doc("publicWeb").get();
  return snapshot.get("paidTicketCheckoutEnabled") === true;
}

function signInMethods(profile) {
  if (profile === "self_check_in") return ["qr_code", "manual_code"];
  if (profile === "staff_entry") return ["personal_pass", "staff_roster"];
  return ["qr_code", "manual_code", "personal_pass", "staff_roster"];
}

function legacySecurityTier(profile) {
  return profile === "hybrid" ? "all" : "regular";
}

function draftStoragePath(imageUrl, uid, draftId) {
  const value = String(imageUrl || "");
  const encoded = value.match(/\/o\/([^?]+)/)?.[1];
  if (!encoded) return null;
  const path = decodeURIComponent(encoded);
  return path.startsWith(`event-drafts/${uid}/${draftId}/`) ? path : null;
}

async function promoteDraftMedia(admin, {uid, draftId, imageUrl, eventIds}) {
  const sourcePath = draftStoragePath(imageUrl, uid, draftId);
  if (!sourcePath || eventIds.length === 0) return null;
  const bucket = admin.storage().bucket();
  const token = crypto.randomUUID();
  const destinationPath = `events_images/wizard-${eventIds[0]}-cover.jpg`;
  await bucket.file(sourcePath).copy(bucket.file(destinationPath));
  await bucket.file(destinationPath).setMetadata({metadata: {firebaseStorageDownloadTokens: token},
    cacheControl: "public,max-age=31536000,immutable"});
  const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
    `${encodeURIComponent(destinationPath)}?alt=media&token=${token}`;
  const batch = admin.firestore().batch();
  for (const eventId of eventIds) {
    batch.update(admin.firestore().collection("Events").doc(eventId), {imageUrl: publicUrl});
  }
  await batch.commit();
  await bucket.deleteFiles({prefix: `event-drafts/${uid}/${draftId}/`});
  return publicUrl;
}

async function canManageEvent(db, uid, event) {
  if (event.customerUid === uid || (Array.isArray(event.coHosts) && event.coHosts.includes(uid))) {
    return true;
  }
  if (!event.organizationId) return false;
  return (await groupAccess(db, uid, event.organizationId)).isAdmin;
}

function eventDocument(admin, form, context) {
  const start = timestampDate(context.startAt || form.startAt);
  const end = timestampDate(context.endAt || form.endAt);
  const durationMinutes = Math.max(1, Math.round((end - start) / 60000));
  const registration = form.registration;
  const policy = form.experience.checkInPolicy;
  const ticketed = registration.mode !== "rsvp";
  return {
    id: context.eventId,
    groupName: context.preserved?.groupName || context.groupName,
    title: form.title,
    description: form.description,
    imageUrl: form.imageUrl,
    customerUid: context.preserved?.customerUid || context.uid,
    organizationId: form.organizationId,
    authorId: context.preserved?.authorId || context.uid,
    authorName: context.preserved?.authorName || context.authorName,
    authorRole: context.preserved?.authorRole || context.authorRole,
    selectedDateTime: admin.firestore.Timestamp.fromDate(start),
    eventGenerateTime: context.preserved?.eventGenerateTime || context.createdAt,
    createdAt: context.preserved?.createdAt || context.createdAt,
    status: context.status,
    private: form.private,
    locationType: form.locationType,
    location: form.location,
    locationName: form.locationName || null,
    placeId: form.placeId || null,
    city: form.locationType === "online" ? "" : form.city,
    regionCode: form.locationType === "online" ? "" : form.regionCode,
    countryCode: form.locationType === "online" ? "" : form.countryCode,
    streetAddress: form.locationType === "online" ? "" : form.streetAddress,
    postalCode: form.locationType === "online" ? "" : form.postalCode,
    eventTimeZone: form.eventTimeZone,
    latitude: form.locationType === "online" ? 0 : form.latitude,
    longitude: form.locationType === "online" ? 0 : form.longitude,
    radius: form.locationType === "online" ? 0 : form.radius,
    radiusUnit: "meters",
    getLocation: form.locationType === "in_person",
    eventDuration: Math.max(1, Math.ceil(durationMinutes / 60)),
    eventDurationMinutes: durationMinutes,
    categories: [],
    primaryDiscoveryCategoryId: form.primaryDiscoveryCategoryId,
    discoveryCategoryIds: form.discoveryCategoryIds,
    discoveryCategorySource: "organizer",
    discoveryCategoryVersion: 1,
    registrationPolicy: registration,
    ticketsEnabled: ticketed,
    maxTickets: registration.capacity || 0,
    ticketPrice: registration.mode === "paid_ticket" ? registration.priceUsd : 0,
    issuedTickets: context.preserved?.issuedTickets || 0,
    reservedTickets: context.preserved?.reservedTickets || 0,
    paidTicketCount: context.preserved?.paidTicketCount || 0,
    grossRevenue: context.preserved?.grossRevenue || 0,
    netRevenue: context.preserved?.netRevenue || 0,
    saveCount: context.preserved?.saveCount || 0,
    attendanceCount: context.preserved?.attendanceCount || 0,
    commentCount: context.preserved?.commentCount || 0,
    isFeatured: context.preserved?.isFeatured || false,
    featureEndDate: context.preserved?.featureEndDate || null,
    accessList: context.preserved?.accessList || [],
    likes: context.preserved?.likes || [],
    coHosts: form.experience.coHosts,
    checkInStaff: form.experience.checkInStaff,
    checkInPolicy: policy,
    signInMethods: signInMethods(policy.profile),
    signInSecurityTier: legacySecurityTier(policy.profile),
    experience: {
      agenda: form.experience.agenda,
      accessibilityOptions: form.experience.accessibilityOptions,
      accessibilityDetails: form.experience.accessibilityDetails,
      thingsToBring: form.experience.thingsToBring,
      publicContact: form.experience.publicContact,
    },
    reminderPolicy: {preset: form.reminderPreset,
      offsetsMinutes: form.reminderPreset === "24h_1h" ? [1440, 60] :
        form.reminderPreset === "24h" ? [1440] : form.reminderPreset === "1h" ? [60] : []},
    seriesId: context.seriesId || null,
    occurrenceIndex: context.occurrenceIndex ?? null,
    seriesVersion: context.seriesId ? 1 : null,
    occurrenceStart: context.seriesId ? admin.firestore.Timestamp.fromDate(start) : null,
    eventRevision: context.eventRevision,
    wizardSchemaVersion: WIZARD_SCHEMA_VERSION,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function customerIdentity(db, uid) {
  const snapshot = await db.collection("Customers").doc(uid).get();
  const data = snapshot.data() || {};
  return {name: String(data.name || data.username || "Organizer").slice(0, 160), snapshot, data};
}

function createSaveEventDraft(admin) {
  const db = admin.firestore();
  return onCall(CALL_OPTIONS, async (request) => {
    const uid = requireOrganizer(request);
    const incomingId = request.data?.draftId;
    const draftRef = incomingId ? db.collection("EventDrafts")
        .doc(requireIdentifier(incomingId, "draft ID")) : db.collection("EventDrafts").doc();
    const expectedRevision = requireRevision(request.data?.expectedRevision);
    const form = normalizeDraftForm(request.data?.formData);
    const access = await groupAccess(db, uid, form.organizationId);
    if (!access.allowed) throw new HttpsError("permission-denied", "You cannot create events for this group.");
    const mode = ["create", "edit", "duplicate"].includes(request.data?.mode) ? request.data.mode : "create";
    const currentStage = Math.min(3, Math.max(0, requireRevision(request.data?.currentStage)));
    let revision;
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(draftRef);
      if (snapshot.exists) {
        const current = snapshot.data();
        if (current.ownerUid !== uid) throw new HttpsError("permission-denied", "Draft access denied.");
        if (Number(current.revision || 0) !== expectedRevision) {
          throw new HttpsError("aborted", "This draft changed elsewhere. Your local copy was preserved.",
              {serverRevision: Number(current.revision || 0)});
        }
        revision = expectedRevision + 1;
      } else {
        if (incomingId && expectedRevision !== 0) throw new HttpsError("not-found", "Draft not found.");
        revision = 1;
      }
      transaction.set(draftRef, {
        id: draftRef.id, ownerUid: uid, organizationId: form.organizationId, mode,
        sourceEventId: request.data?.sourceEventId || null,
        sourceSeriesId: request.data?.sourceSeriesId || null,
        sourceEventRevision: snapshot.exists ? snapshot.get("sourceEventRevision") :
          (request.data?.sourceEventRevision ?? null),
        currentStage, completedStages: Array.isArray(request.data?.completedStages) ?
          request.data.completedStages.filter(Number.isInteger).filter((value) => value >= 0 && value <= 3) : [],
        formData: form, revision, schemaVersion: WIZARD_SCHEMA_VERSION,
        archived: false, createdAt: snapshot.exists ? snapshot.get("createdAt") :
          admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastClientMutationId: String(request.data?.clientMutationId || "").slice(0, 160),
      }, {merge: true});
    });
    return {draftId: draftRef.id, revision, savedAt: new Date().toISOString()};
  });
}

function createListEventDrafts(admin) {
  const db = admin.firestore();
  return onCall(CALL_OPTIONS, async (request) => {
    const uid = requireOrganizer(request);
    const snapshot = await db.collection("EventDrafts").where("ownerUid", "==", uid)
        .where("archived", "==", false).orderBy("updatedAt", "desc").limit(50).get();
    return {drafts: snapshot.docs.map((doc) => ({id: doc.id, ...doc.data()}))};
  });
}

function createArchiveEventDraft(admin) {
  const db = admin.firestore();
  return onCall(CALL_OPTIONS, async (request) => {
    const uid = requireOrganizer(request);
    const draftId = requireIdentifier(request.data?.draftId, "draft ID");
    const ref = db.collection("EventDrafts").doc(draftId);
    const snapshot = await ref.get();
    if (!snapshot.exists || snapshot.get("ownerUid") !== uid) {
      throw new HttpsError("not-found", "Draft not found.");
    }
    await ref.update({archived: true, archivedAt: admin.firestore.FieldValue.serverTimestamp()});
    return {archived: true};
  });
}

function createDeleteEventDraft(admin) {
  const db = admin.firestore();
  return onCall(CALL_OPTIONS, async (request) => {
    const uid = requireOrganizer(request);
    const draftId = requireIdentifier(request.data?.draftId, "draft ID");
    const ref = db.collection("EventDrafts").doc(draftId);
    const snapshot = await ref.get();
    if (!snapshot.exists || snapshot.get("ownerUid") !== uid) {
      throw new HttpsError("not-found", "Draft not found.");
    }
    await admin.storage().bucket().deleteFiles({prefix: `event-drafts/${uid}/${draftId}/`});
    await ref.delete();
    return {deleted: true};
  });
}

function createDuplicateEventToDraft(admin) {
  const db = admin.firestore();
  return onCall(CALL_OPTIONS, async (request) => {
    const uid = requireOrganizer(request);
    const eventId = requireIdentifier(request.data?.eventId, "event ID");
    const eventRef = db.collection("Events").doc(eventId);
    const [eventSnapshot, questionsSnapshot] = await Promise.all([
      eventRef.get(), eventRef.collection("EventQuestions").orderBy("order", "asc").get(),
    ]);
    if (!eventSnapshot.exists || !(await canManageEvent(db, uid, eventSnapshot.data()))) {
      throw new HttpsError("not-found", "Event not found.");
    }
    const draftRef = db.collection("EventDrafts").doc();
    const form = sanitizedDuplicateForm(eventSnapshot.data(),
        questionsSnapshot.docs.map((doc) => doc.data()));
    await draftRef.set({id: draftRef.id, ownerUid: uid, organizationId: form.organizationId,
      mode: "duplicate", sourceEventId: eventId, sourceSeriesId: null, currentStage: 0,
      completedStages: [], formData: form, revision: 1, schemaVersion: WIZARD_SCHEMA_VERSION,
      archived: false, createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()});
    return {draftId: draftRef.id, revision: 1, formData: form};
  });
}

function createEditEventDraft(admin) {
  const db = admin.firestore();
  return onCall(CALL_OPTIONS, async (request) => {
    const uid = requireOrganizer(request);
    const eventId = requireIdentifier(request.data?.eventId, "event ID");
    const eventRef = db.collection("Events").doc(eventId);
    const [eventSnapshot, questionsSnapshot] = await Promise.all([
      eventRef.get(), eventRef.collection("EventQuestions").orderBy("order", "asc").get(),
    ]);
    if (!eventSnapshot.exists || !(await canManageEvent(db, uid, eventSnapshot.data()))) {
      throw new HttpsError("not-found", "Event not found.");
    }
    const existingDraft = await db.collection("EventDrafts").where("ownerUid", "==", uid)
        .where("sourceEventId", "==", eventId).where("archived", "==", false).limit(1).get();
    if (!existingDraft.empty) return {id: existingDraft.docs[0].id, ...existingDraft.docs[0].data()};
    const draftRef = db.collection("EventDrafts").doc();
    const form = editableEventForm(eventSnapshot.data(),
        questionsSnapshot.docs.map((doc) => ({id: doc.id, ...doc.data()})));
    const document = {id: draftRef.id, ownerUid: uid, organizationId: form.organizationId,
      mode: "edit", sourceEventId: eventId, sourceSeriesId: eventSnapshot.get("seriesId") || null,
      sourceEventRevision: Number(eventSnapshot.get("eventRevision") || 0), currentStage: 0,
      completedStages: [0, 1, 2], formData: form, revision: 1,
      schemaVersion: WIZARD_SCHEMA_VERSION, archived: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()};
    await draftRef.set(document);
    return document;
  });
}

function createListEventTemplates(admin) {
  const db = admin.firestore();
  return onCall(CALL_OPTIONS, async (request) => {
    const uid = requireOrganizer(request);
    const personal = await db.collection("EventTemplates").where("ownerUid", "==", uid)
        .orderBy("updatedAt", "desc").limit(50).get();
    const organizationId = request.data?.organizationId ?
      requireIdentifier(request.data.organizationId, "organization ID") : null;
    let group = [];
    if (organizationId) {
      const access = await groupAccess(db, uid, organizationId);
      if (!access.allowed) throw new HttpsError("permission-denied", "Template access denied.");
      const snapshot = await db.collection("EventTemplates").where("organizationId", "==", organizationId)
          .orderBy("updatedAt", "desc").limit(50).get();
      group = snapshot.docs.map((doc) => ({id: doc.id, ...doc.data()}));
    }
    return {curated: TEMPLATE_CATALOG,
      personal: personal.docs.map((doc) => ({id: doc.id, ...doc.data()})), group};
  });
}

function createSaveEventTemplate(admin) {
  const db = admin.firestore();
  return onCall(CALL_OPTIONS, async (request) => {
    const uid = requireOrganizer(request);
    const name = String(request.data?.name || "").trim().slice(0, 100);
    if (!name) throw new HttpsError("invalid-argument", "Template name is required.");
    const organizationId = request.data?.organizationId ?
      requireIdentifier(request.data.organizationId, "organization ID") : null;
    const access = await groupAccess(db, uid, organizationId);
    if (!access.allowed || (organizationId && !access.isAdmin)) {
      throw new HttpsError("permission-denied", "Only group administrators can manage shared templates.");
    }
    const form = sanitizedTemplateForm(request.data?.formData, {
      includeLocation: request.data?.includeLocation === true,
      includeContact: request.data?.includeContact === true,
    });
    const ref = request.data?.templateId ? db.collection("EventTemplates")
        .doc(requireIdentifier(request.data.templateId, "template ID")) : db.collection("EventTemplates").doc();
    const existing = await ref.get();
    if (existing.exists && existing.get("ownerUid") !== uid && !access.isAdmin) {
      throw new HttpsError("permission-denied", "Template access denied.");
    }
    await ref.set({id: ref.id, name, ownerUid: uid, organizationId, scope: organizationId ? "group" : "personal",
      formData: form, schemaVersion: WIZARD_SCHEMA_VERSION,
      createdAt: existing.exists ? existing.get("createdAt") : admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    return {templateId: ref.id};
  });
}

function createDeleteEventTemplate(admin) {
  const db = admin.firestore();
  return onCall(CALL_OPTIONS, async (request) => {
    const uid = requireOrganizer(request);
    const templateId = requireIdentifier(request.data?.templateId, "template ID");
    const ref = db.collection("EventTemplates").doc(templateId);
    const snapshot = await ref.get();
    if (!snapshot.exists) throw new HttpsError("not-found", "Template not found.");
    const access = await groupAccess(db, uid, snapshot.get("organizationId"));
    if (snapshot.get("ownerUid") !== uid && !access.isAdmin) {
      throw new HttpsError("permission-denied", "Template access denied.");
    }
    await ref.delete();
    return {deleted: true};
  });
}

async function consumePublicationAllowance(transaction, db, uid, tier, customerSnapshot) {
  if (tier === "premium") return;
  if (tier === "basic") {
    const subscriptionRef = db.collection("subscriptions").doc(uid);
    const subscriptionSnapshot = await transaction.get(subscriptionRef);
    if (Number(subscriptionSnapshot.get("eventsCreatedThisMonth") || 0) >= 5) {
      throw new HttpsError("resource-exhausted", "Your monthly event limit has been reached.");
    }
    transaction.update(subscriptionRef, {eventsCreatedThisMonth:
      Number(subscriptionSnapshot.get("eventsCreatedThisMonth") || 0) + 1});
    return;
  }
  const created = Number(customerSnapshot.data()?.eventsCreated || 0);
  if (created >= 5) {
    throw new HttpsError("resource-exhausted", "Your event creation limit has been reached.");
  }
  transaction.set(customerSnapshot.ref, {eventsCreated: created + 1}, {merge: true});
}

function createPublishEventDraft(admin) {
  const db = admin.firestore();
  return onCall({...CALL_OPTIONS, timeoutSeconds: 120, memory: "512MiB"}, async (request) => {
    const uid = requireOrganizer(request);
    const draftId = requireIdentifier(request.data?.draftId, "draft ID");
    const draftRef = db.collection("EventDrafts").doc(draftId);
    const draftSnapshot = await draftRef.get();
    if (!draftSnapshot.exists || draftSnapshot.get("ownerUid") !== uid) {
      throw new HttpsError("not-found", "Draft not found.");
    }
    const expectedDraftRevision = requireRevision(request.data?.expectedDraftRevision);
    if (Number(draftSnapshot.get("revision") || 0) !== expectedDraftRevision) {
      throw new HttpsError("aborted", "The draft changed before publication.");
    }
    const draft = draftSnapshot.data();
    const form = normalizeDraftForm(draft.formData);
    const [access, tier, paidEnabled, identity] = await Promise.all([
      groupAccess(db, uid, form.organizationId), tierForUser(db, uid),
      paidCheckoutEnabled(db), customerIdentity(db, uid),
    ]);
    if (!access.allowed) throw new HttpsError("permission-denied", "You cannot publish for this group.");
    const errors = validatePublishable(form, {paidEnabled});
    if (errors.length) throw new HttpsError("invalid-argument", "Complete the highlighted event fields.", {errors});
    const teamUids = [...new Set([...form.experience.coHosts, ...form.experience.checkInStaff])];
    if (teamUids.length) {
      const teamSnapshots = await db.getAll(...teamUids.map((teamUid) =>
        db.collection("Customers").doc(teamUid)));
      if (teamSnapshots.some((snapshot) => !snapshot.exists)) {
        throw new HttpsError("invalid-argument", "Every event team member needs an active Attendus account.");
      }
    }
    const occurrenceMaximum = occurrenceLimitForTier(tier);
    const occurrences = generateOccurrences(
        form.startAt,
        form.recurrence,
        occurrenceMaximum,
        form.eventTimeZone,
    );
    const end = timestampDate(form.endAt);
    const start = timestampDate(form.startAt);
    const durationMs = end - start;
    const isEdit = draft.mode === "edit" && draft.sourceEventId;
    const recurrenceScope = ["this_occurrence", "this_and_future", "entire_series"]
        .includes(request.data?.recurrenceScope) ? request.data.recurrenceScope : "this_occurrence";
    const seriesId = form.recurrence.enabled ? (draft.sourceSeriesId || db.collection("EventSeries").doc().id) : null;
    const status = form.organizationId && access.organization?.requireEventApproval === true && !access.isAdmin ?
      "pending_approval" : "scheduled";
    let editTargets = [];
    if (isEdit && draft.sourceSeriesId && recurrenceScope !== "this_occurrence") {
      const sourceSnapshot = await db.collection("Events").doc(draft.sourceEventId).get();
      if (!sourceSnapshot.exists) throw new HttpsError("not-found", "Event not found.");
      const sourceStart = timestampDate(sourceSnapshot.get("selectedDateTime"));
      const seriesSnapshot = await db.collection("Events").where("seriesId", "==", draft.sourceSeriesId)
          .limit(52).get();
      editTargets = seriesSnapshot.docs.filter((document) => recurrenceScope === "entire_series" ||
        timestampDate(document.get("selectedDateTime")) >= sourceStart)
          .sort((left, right) => timestampDate(left.get("selectedDateTime")) -
            timestampDate(right.get("selectedDateTime")));
    }
    if (isEdit && editTargets.length === 0) {
      editTargets = [await db.collection("Events").doc(draft.sourceEventId).get()];
    }
    const eventIds = isEdit ? editTargets.map((document) => document.id) :
      occurrences.map(() => db.collection("Events").doc().id);
    const existingQuestionSnapshots = isEdit ? await Promise.all(eventIds.map((eventId) =>
      db.collection("Events").doc(eventId).collection("EventQuestions").get())) : [];
    const createdAt = admin.firestore.Timestamp.now();
    await db.runTransaction(async (transaction) => {
      const freshDraft = await transaction.get(draftRef);
      if (!freshDraft.exists || freshDraft.get("ownerUid") !== uid ||
          Number(freshDraft.get("revision") || 0) !== expectedDraftRevision) {
        throw new HttpsError("aborted", "The draft changed before publication.");
      }
      let existingEvents = [];
      if (isEdit) {
        existingEvents = await Promise.all(eventIds.map((eventId) =>
          transaction.get(db.collection("Events").doc(eventId))));
        const existingSnapshot = existingEvents.find((snapshot) => snapshot.id === draft.sourceEventId);
        if (!existingSnapshot?.exists ||
            existingEvents.some((snapshot) => !snapshot.exists ||
              (snapshot.get("customerUid") !== uid && !access.isAdmin &&
               !(snapshot.get("coHosts") || []).includes(uid)))) {
          throw new HttpsError("permission-denied", "Event access denied.");
        }
        const expectedEventRevision = requireRevision(draft.sourceEventRevision);
        if (Number(existingSnapshot.get("eventRevision") || 0) !== expectedEventRevision) {
          throw new HttpsError("aborted", "The published event changed elsewhere.");
        }
      } else {
        await consumePublicationAllowance(transaction, db, uid, tier, identity.snapshot);
      }
      if (seriesId) {
        transaction.set(db.collection("EventSeries").doc(seriesId), {
          id: seriesId, ownerUid: uid, organizationId: form.organizationId,
          recurrence: form.recurrence, eventTimeZone: form.eventTimeZone,
          occurrenceCount: occurrences.length, occurrenceLimit: occurrenceMaximum,
          version: 1, wizardSchemaVersion: WIZARD_SCHEMA_VERSION,
          createdAt, updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }
      for (let index = 0; index < eventIds.length; index++) {
        const eventId = eventIds[index];
        const existingDocument = isEdit ? existingEvents[index].data() : null;
        const sourceDocument = isEdit ? existingEvents.find((snapshot) =>
          snapshot.id === draft.sourceEventId).data() : null;
        const occurrenceStart = !isEdit ? occurrences[index] :
          recurrenceScope === "this_occurrence" ? start :
            seriesOccurrenceStart(existingDocument.selectedDateTime,
                sourceDocument.selectedDateTime, start, form.eventTimeZone);
        const occurrenceEnd = new Date(occurrenceStart.getTime() + durationMs);
        const preserved = isEdit ? existingDocument : null;
        const eventRevision = isEdit ? Number(existingDocument.eventRevision || 0) + 1 : 1;
        const document = eventDocument(admin, form, {eventId, uid,
          status: isEdit ? existingDocument.status : status, createdAt,
          authorName: identity.name, authorRole: access.isAdmin ? "admin" : "member",
          groupName: access.organization?.name || identity.name,
          startAt: occurrenceStart, endAt: occurrenceEnd,
          seriesId: isEdit ? existingDocument.seriesId : seriesId,
          occurrenceIndex: isEdit ? existingDocument.occurrenceIndex : (seriesId ? index : null),
          eventRevision, preserved});
        const eventRef = db.collection("Events").doc(eventId);
        transaction.set(eventRef, document, {merge: isEdit});
        if (isEdit) {
          const retained = new Set(form.questions.map((question) => question.id));
          for (const questionDocument of existingQuestionSnapshots[index].docs) {
            if (!retained.has(questionDocument.id)) transaction.delete(questionDocument.ref);
          }
        }
        for (const question of form.questions) {
          transaction.set(eventRef.collection("EventQuestions").doc(question.id), question);
        }
      }
      transaction.update(draftRef, {archived: true, publishedAt: createdAt,
        publishedEventIds: eventIds, publishedSeriesId: seriesId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()});
    });
    logger.info("Event wizard draft published", {draftId, uid, eventCount: eventIds.length,
      seriesId, mode: draft.mode, status});
    try {
      await promoteDraftMedia(admin, {uid, draftId, imageUrl: form.imageUrl, eventIds});
    } catch (error) {
      logger.warn("Event draft media promotion was deferred", {draftId, uid,
        error: String(error.message || error).slice(0, 300)});
    }
    return {status, eventId: eventIds[0], eventIds, seriesId, occurrenceCount: eventIds.length};
  });
}

function createDecideEventRegistration(admin) {
  const db = admin.firestore();
  return onCall(CALL_OPTIONS, async (request) => {
    const uid = requireOrganizer(request);
    const eventId = requireIdentifier(request.data?.eventId, "event ID");
    const registrationId = requireIdentifier(request.data?.registrationId, "registration ID");
    const decision = request.data?.decision;
    if (!["approve", "decline", "promote"].includes(decision)) {
      throw new HttpsError("invalid-argument", "Choose approve, decline, or promote.");
    }
    const eventRef = db.collection("Events").doc(eventId);
    const registrationRef = db.collection("RegisterAttendance").doc(registrationId);
    const authorizationSnapshot = await eventRef.get();
    if (!authorizationSnapshot.exists) throw new HttpsError("not-found", "Event not found.");
    const authorizationEvent = authorizationSnapshot.data();
    const access = await groupAccess(db, uid, authorizationEvent.organizationId || null);
    if (authorizationEvent.customerUid !== uid && !access.isAdmin &&
        !(authorizationEvent.coHosts || []).includes(uid)) {
      throw new HttpsError("permission-denied", "Event access denied.");
    }
    let resultStatus;
    let ticketId = null;
    const rawManageToken = crypto.randomBytes(32).toString("base64url");
    await db.runTransaction(async (transaction) => {
      const [eventSnapshot, registrationSnapshot] = await Promise.all([
        transaction.get(eventRef), transaction.get(registrationRef),
      ]);
      if (!eventSnapshot.exists ||
          (eventSnapshot.get("customerUid") !== uid && !access.isAdmin &&
           !(eventSnapshot.get("coHosts") || []).includes(uid))) {
        throw new HttpsError("permission-denied", "Event access denied.");
      }
      const expectedStatus = decision === "promote" ? "waitlisted" : "pending";
      if (!registrationSnapshot.exists || registrationSnapshot.get("eventId") !== eventId ||
          registrationSnapshot.get("status") !== expectedStatus) {
        throw new HttpsError("failed-precondition", "Registration status changed before this decision.");
      }
      const registration = registrationSnapshot.data();
      const guestId = registration.guestId || null;
      const guestRef = guestId ? db.collection("GuestAttendees").doc(guestId) : null;
      const guestSnapshot = guestRef ? await transaction.get(guestRef) : null;
      if (guestRef && !guestSnapshot.exists) {
        throw new HttpsError("failed-precondition", "Guest identity is unavailable.");
      }
      if (decision === "decline") {
        resultStatus = "declined";
      } else {
        const policy = eventSnapshot.get("registrationPolicy") || {};
        const capacity = Number(policy.capacity || 0);
        const confirmed = Number(eventSnapshot.get("confirmedRegistrationCount") || 0);
        const full = capacity > 0 && confirmed >= capacity;
        if (decision === "promote" && full) {
          throw new HttpsError("resource-exhausted", "Capacity is still full.");
        }
        resultStatus = full && policy.waitlistEnabled !== false ? "waitlisted" : "confirmed";
        if (resultStatus === "confirmed") {
          transaction.update(eventRef, {confirmedRegistrationCount:
            admin.firestore.FieldValue.increment(1)});
          if (policy.mode === "free_ticket") {
            ticketId = `free_${crypto.createHash("sha256")
                .update(`${eventId}\0${registrationId}`).digest("hex").slice(0, 48)}`;
            transaction.create(db.collection("Tickets").doc(ticketId), {
              id: ticketId, eventId, eventTitle: String(eventSnapshot.get("title") || "Event"),
              eventImageUrl: String(eventSnapshot.get("imageUrl") || ""),
              eventLocation: String(eventSnapshot.get("location") || ""),
              eventDateTime: eventSnapshot.get("selectedDateTime"),
              customerUid: registration.customerUid, guestId,
              identityType: registration.identityType || "guest",
              customerName: registration.realName || registration.userName || "Attendee",
              ticketCode: crypto.randomBytes(4).toString("hex").toUpperCase(),
              issuedDateTime: admin.firestore.Timestamp.now(), price: 0,
              isPaid: false, isUsed: false, isSkipTheLine: false,
              issuanceSource: "server_guest_approval_v3", revoked: false,
            });
            transaction.update(eventRef, {issuedTickets: admin.firestore.FieldValue.increment(1)});
          }
        }
      }
      transaction.update(registrationRef, {status: resultStatus, decisionByUid: uid,
        decidedAt: admin.firestore.FieldValue.serverTimestamp(), ticketId});
      if (guestSnapshot?.exists) {
        const messageId = `${resultStatus}_${registrationId}_${Date.now()}`;
        const manageRef = db.collection("GuestManageTokens")
            .doc(crypto.createHash("sha256").update(rawManageToken).digest("hex"));
        transaction.create(manageRef, {guestId, registrationId,
          ownerUid: registration.customerUid, status: "active",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: new Date(Date.now() + 72 * 3600000)});
        transaction.create(db.collection("OutboundMessages").doc(messageId), {
          templateId: resultStatus === "confirmed" ? "guest_registration_confirmation" :
            resultStatus === "waitlisted" ? "guest_registration_waitlisted" :
              "guest_registration_declined",
          channel: "email", status: "pending", attempts: 0, registrationId,
          guestId, eventId, encryptedEmail: guestSnapshot.get("encryptedEmail"),
          maskedEmail: guestSnapshot.get("maskedEmail"), payload: {
            firstName: guestSnapshot.get("greetingName") || "there",
            eventTitle: String(eventSnapshot.get("title") || "Event"),
            eventStart: eventSnapshot.get("selectedDateTime"),
            eventLocation: String(eventSnapshot.get("location") || ""),
            kind: (eventSnapshot.get("registrationPolicy") || {}).mode || "rsvp",
            manageUrl: `https://attendus.app/manage/${rawManageToken}`,
          }, createdAt: admin.firestore.FieldValue.serverTimestamp(), nextAttemptAt: new Date(),
        });
      }
    });
    return {status: resultStatus, ticketId};
  });
}

function createEventWizardFunctions(admin) {
  return {
    saveEventDraftV1: createSaveEventDraft(admin),
    listEventDraftsV1: createListEventDrafts(admin),
    archiveEventDraftV1: createArchiveEventDraft(admin),
    deleteEventDraftV1: createDeleteEventDraft(admin),
    duplicateEventToDraftV1: createDuplicateEventToDraft(admin),
    createEditEventDraftV1: createEditEventDraft(admin),
    listEventTemplatesV1: createListEventTemplates(admin),
    saveEventTemplateV1: createSaveEventTemplate(admin),
    deleteEventTemplateV1: createDeleteEventTemplate(admin),
    publishEventDraftV1: createPublishEventDraft(admin),
    decideEventRegistrationV1: createDecideEventRegistration(admin),
  };
}

module.exports = {
  createEventWizardFunctions,
  eventDocument,
  groupAccess,
  draftStoragePath,
  signInMethods,
};
