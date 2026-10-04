"use strict";
const {publicOrigin} = require("../public-web/origin");

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

async function groupAccess(db, uid, organizationId, transaction = null) {
  const read = (ref) => transaction ? transaction.get(ref) : ref.get();
  if ((await read(db.collection("account_deletion_jobs").doc(uid))).exists) return {allowed: false, isAdmin: false, organization: null};
  if (!organizationId) return {allowed: true, isAdmin: false, organization: null};
  const [organizationSnapshot, memberSnapshot] = await Promise.all([
    read(db.collection("Organizations").doc(organizationId)),
    read(db.collection("Organizations").doc(organizationId).collection("Members").doc(uid)),
  ]);
  if (!organizationSnapshot.exists) return {allowed: false, isAdmin: false, organization: null};
  const organization = organizationSnapshot.data() || {};
  if (organization.createdBy === uid) return {allowed: true, isAdmin: true, organization};
  const member = memberSnapshot.data() || {};
  const approved = memberSnapshot.exists && String(member.status || "").toLowerCase() === "approved";
  const role = String(member.role || "").toLowerCase();
  const isAdmin = ["owner", "admin"].includes(role);
  return {allowed: approved && (organization.allowMemberEventCreation !== false || isAdmin),
    isAdmin: approved && isAdmin, organization};
}

function tierFromSubscription(subscription) {
  const data = subscription.data() || {};
  if (data.isActive === true || String(data.status || "").toLowerCase() === "active") {
    const tier = String(data.tier || data.subscriptionTier || "").toLowerCase();
    if (tier === "premium" || tier === "basic") return tier;
  }
  return "free";
}

async function tierForUser(db, uid) {
  return tierFromSubscription(await db.collection("subscriptions").doc(uid).get());
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
  return (await require("./access").capabilities(db, uid, event)).manageEvent;
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
    launchScheduleNeedsReview: false,
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
    ...(!context.preserved ? {confirmedRegistrationCount: 0} : {}),
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
      publicContact: require("./public-contact-privacy").publishedContact(form.experience.publicContact),
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
        if (current.publishedAt) throw new HttpsError("failed-precondition", "Create an edit draft for the published event.");
        if (Number(current.revision || 0) !== expectedRevision) {
          throw new HttpsError("aborted", "This draft changed elsewhere. Your local copy was preserved.",
              {serverRevision: Number(current.revision || 0)});
        }
        revision = expectedRevision + 1;
      } else {
        if (incomingId && expectedRevision !== 0) throw new HttpsError("not-found", "Draft not found.");
        revision = 1;
      }
      if (!(await groupAccess(db, uid, form.organizationId, transaction)).allowed) throw new HttpsError("permission-denied", "Organization access denied.");
      const sourceEventId = request.data?.sourceEventId || null;
      const sourceSeriesId = request.data?.sourceSeriesId || null;
      if (snapshot.exists && (snapshot.get("mode") !== mode || (snapshot.get("sourceEventId") || null) !== sourceEventId || (snapshot.get("sourceSeriesId") || null) !== sourceSeriesId)) {
        throw new HttpsError("permission-denied", "A draft cannot be retargeted. Create a new authorized draft.");
      }
      if (mode === "edit") {
        if (!sourceEventId) throw new HttpsError("invalid-argument", "An edit source is required.");
        const source = await transaction.get(db.collection("Events").doc(requireIdentifier(sourceEventId, "source event")));
        if (!source.exists || !(await require("./access").capabilities(db, uid, source.data(), transaction)).manageEvent || (source.get("seriesId") || null) !== sourceSeriesId) {
          throw new HttpsError("permission-denied", "Source event access denied.");
        }
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

function publicationCounter(value) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new HttpsError("failed-precondition", "Your event usage requires review before publishing.");
  }
  return value;
}

async function consumePublicationAllowance(transaction, db, uid, tier, customerSnapshot) {
  const entitlement = await transaction.get(db.collection("account_entitlements").doc(uid));
  const subscriptionRef = db.collection("subscriptions").doc(uid);
  const subscriptionSnapshot = await transaction.get(subscriptionRef);
  if (tierFromSubscription(subscriptionSnapshot) !== tier) {
    throw new HttpsError("aborted", "Your subscription changed. Review the event and retry publication.");
  }
  if (entitlement.get("unlimitedEventCreation") === true) return;
  if (tier === "premium") return;
  if (tier === "basic") {
    const created = publicationCounter(subscriptionSnapshot.get("eventsCreatedThisMonth"));
    if (created >= 5) {
      throw new HttpsError("resource-exhausted", "Your monthly event limit has been reached.");
    }
    transaction.update(subscriptionRef, {eventsCreatedThisMonth: created + 1});
    return;
  }
  // The organizer identity was loaded before this transaction. Read its usage
  // again here so concurrent draft publications contend on the current counter.
  const currentCustomer = await transaction.get(customerSnapshot.ref);
  const created = publicationCounter(currentCustomer.data()?.eventsCreated);
  if (created >= 5) {
    throw new HttpsError("resource-exhausted", "Your event creation limit has been reached.");
  }
  transaction.set(customerSnapshot.ref, {eventsCreated: created + 1}, {merge: true});
}

function changeFingerprint(draft) {
  return crypto.createHash("sha256").update(JSON.stringify(normalizeDraftForm(draft.formData))).digest("hex");
}

function createPreviewEventChange(admin) {
  const db = admin.firestore();
  return onCall(CALL_OPTIONS, async (request) => {
    const uid = requireOrganizer(request);
    const draftId = requireIdentifier(request.data?.draftId, "draft ID");
    const draft = await db.collection("EventDrafts").doc(draftId).get();
    if (!draft.exists || draft.get("ownerUid") !== uid || draft.get("mode") !== "edit" || draft.get("revision") !== request.data.expectedDraftRevision) throw new HttpsError("aborted", "Save the current edit before previewing.");
    const source = await db.collection("Events").doc(draft.get("sourceEventId")).get();
    const scope = request.data.recurrenceScope || "this_occurrence";
    if (!["this_occurrence", "this_and_future", "entire_series"].includes(scope)) throw new HttpsError("invalid-argument", "Invalid recurrence scope.");
    let targets = [source];
    if (scope !== "this_occurrence" && source.get("seriesId")) {
      const series = await db.collection("Events").where("seriesId", "==", source.get("seriesId")).limit(101).get();
      if (series.size > 100) throw new HttpsError("failed-precondition", "This series exceeds the supported atomic change scope.");
      targets = series.docs.filter((event) => scope === "entire_series" || timestampDate(event.get("selectedDateTime")) >= timestampDate(source.get("selectedDateTime")));
    }
    let count = 0;
    for (const target of targets) {
      if (!target.exists || !(await require("./access").capabilities(db, uid, target.data())).manageEvent) throw new HttpsError("permission-denied", "Source event access denied.");
      const snapshots = await Promise.all(["RegisterAttendance", "Tickets"].map((name) => require("./roster").allDocuments(db.collection(name).where("eventId", "==", target.id))));
      const rows = require("./roster").buildRoster(...snapshots.map((list) => list.map((doc) => ({id: doc.id, ...doc.data()}))), []);
      count += new Set(rows.filter((row) => ["confirmed", "pending", "waitlisted"].includes(row.status)).map((row) => row.guestId || row.uid).filter(Boolean)).size;
    }
    const preview = db.collection("EventChangePreviews").doc();
    await preview.create({actorUid: uid, eventId: source.id, draftId, draftRevision: draft.get("revision"), fingerprint: changeFingerprint(draft.data()), scope, count,
      targets: targets.map((event) => ({eventId: event.id, revision: Number(event.get("eventRevision") || 0)})), expiresAt: new Date(Date.now() + 10 * 60000)});
    return {previewToken: preview.id, count, occurrences: targets.length};
  });
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
    const publicationFingerprint = crypto.createHash("sha256").update(JSON.stringify([expectedDraftRevision, request.data?.recurrenceScope || "this_occurrence", request.data?.changeReason || "", request.data?.changePreviewToken || null])).digest("hex");
    async function replay(transaction, snapshot) {
      if (!snapshot.get("publishedAt")) return null;
      if (snapshot.get("publicationFingerprint") !== publicationFingerprint || !snapshot.get("publicationResult")) throw new HttpsError("already-exists", "This draft was already published with different inputs.");
      for (const id of snapshot.get("publishedEventIds") || []) {
        const event = await transaction.get(db.collection("Events").doc(id));
        if (!(await require("./access").capabilities(db, uid, event.data(), transaction)).manageEvent) throw new HttpsError("permission-denied", "Event access is required.");
      }
      return snapshot.get("publicationResult");
    }
    if (draftSnapshot.get("publishedAt")) return db.runTransaction(async (transaction) => replay(transaction, await transaction.get(draftRef)));
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
    const changeReason = String(request.data?.changeReason || "").trim().slice(0, 1000);
    const changePreviewToken = request.data?.changePreviewToken;
    if (changePreviewToken && (!/^[A-Za-z0-9_-]+$/.test(changePreviewToken) || changeReason.length < 5)) {
      throw new HttpsError("invalid-argument", "Explain the change and review affected attendees.");
    }
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
          .limit(101).get();
      if (seriesSnapshot.size > 100) throw new HttpsError("failed-precondition", "This series exceeds the supported atomic change scope.");
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
    const publicationResult = {status, eventId: eventIds[0], eventIds, seriesId, occurrenceCount: eventIds.length};
    const replayed = await db.runTransaction(async (transaction) => {
      const freshDraft = await transaction.get(draftRef);
      if (!freshDraft.exists || freshDraft.get("ownerUid") !== uid ||
          Number(freshDraft.get("revision") || 0) !== expectedDraftRevision) {
        throw new HttpsError("aborted", "The draft changed before publication.");
      }
      const previous = await replay(transaction, freshDraft);
      if (previous) return previous;
      let existingEvents = [];
      if (isEdit) {
        existingEvents = await Promise.all(eventIds.map((eventId) =>
          transaction.get(db.collection("Events").doc(eventId))));
        if (changePreviewToken) {
          const preview = await transaction.get(db.collection("EventChangePreviews").doc(changePreviewToken));
          const targets = preview.get("targets") || [];
          if (!preview.exists || preview.get("draftId") !== draftId || preview.get("draftRevision") !== expectedDraftRevision || preview.get("fingerprint") !== changeFingerprint(draft) || preview.get("actorUid") !== uid || preview.get("eventId") !== draft.sourceEventId ||
              preview.get("scope") !== recurrenceScope || preview.get("expiresAt").toMillis() < Date.now() ||
              targets.length !== existingEvents.length || existingEvents.some((event) =>
                !targets.some((target) => target.eventId === event.id && target.revision === Number(event.get("eventRevision") || 0)))) {
            throw new HttpsError("aborted", "The event changed. Review affected attendees again.");
          }
        }
        const existingSnapshot = existingEvents.find((snapshot) => snapshot.id === draft.sourceEventId);
        if (!existingSnapshot?.exists) throw new HttpsError("not-found", "Source event not found.");
        for (const source of existingEvents) {
          if (!source.exists || !(await require("./access").capabilities(db, uid, source.data(), transaction)).manageEvent ||
              (source.get("seriesId") || null) !== (draft.sourceSeriesId || null)) throw new HttpsError("permission-denied", "Source event access denied.");
        }
        if (!(await groupAccess(db, uid, form.organizationId, transaction)).allowed) throw new HttpsError("permission-denied", "Destination organization access denied.");
        const previous = existingSnapshot.data();
        const material = timestampDate(previous.selectedDateTime)?.getTime() !== start.getTime() || require("./schedule").schedule(previous).end?.getTime() !== end.getTime() || previous.eventTimeZone !== form.eventTimeZone || previous.location !== form.location;
        if (material && (!changePreviewToken || changeReason.length < 5)) throw new HttpsError("failed-precondition", "Update the app, save the edit and review affected attendees before changing the schedule or location.");
        const expectedEventRevision = requireRevision(draft.sourceEventRevision);
        if (Number(existingSnapshot.get("eventRevision") || 0) !== expectedEventRevision) {
          throw new HttpsError("aborted", "The published event changed elsewhere.");
        }
      } else {
        if (!(await groupAccess(db, uid, form.organizationId, transaction)).allowed) throw new HttpsError("permission-denied", "Publication access denied.");
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
        if (isEdit && (require("./schedule").instant(existingDocument.selectedDateTime)?.getTime() !== occurrenceStart.getTime() ||
            existingDocument.eventDurationMinutes !== document.eventDurationMinutes ||
            existingDocument.eventTimeZone !== document.eventTimeZone || existingDocument.location !== document.location)) {
          transaction.create(db.collection("EventAnnouncements").doc(`reschedule_${eventId}_${eventRevision}`), {
            eventId, actorUid: uid, audience: "active", title: `Event updated: ${document.title}`,
            body: `${changeReason || "The organizer changed the event schedule or location."} Review the updated details at ${publicOrigin()}/event/${eventId}`,
            templateId: "event_rescheduled", eventSnapshot: require("./lifecycle-snapshot").lifecycleSnapshot(document), status: "queued", createdAt,
          });
        }
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
      transaction.update(draftRef, {archived: true, publishedAt: createdAt, publicationFingerprint, publicationResult,
        publishedEventIds: eventIds, publishedSeriesId: seriesId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()});
    });
    if (replayed) return replayed;
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
    const requestKey = String(request.data?.idempotencyKey || `${registrationId}:${decision}`);
    if (!/^[A-Za-z0-9._:-]{1,180}$/.test(requestKey)) throw new HttpsError("invalid-argument", "Invalid decision request key.");
    const fingerprint = crypto.createHash("sha256").update(JSON.stringify([eventId, registrationId, decision])).digest("hex");
    const decisionRef = db.collection("RegistrationDecisions").doc(crypto.createHash("sha256").update(`${uid}:${eventId}:${requestKey}`).digest("hex"));
    let resultStatus;
    let ticketId = null;
    const rawManageToken = crypto.randomBytes(32).toString("base64url");
    await db.runTransaction(async (transaction) => {
      const [eventSnapshot, registrationSnapshot] = await Promise.all([
        transaction.get(eventRef), transaction.get(registrationRef),
      ]);
      if (!eventSnapshot.exists || !(await require("./access").capabilities(db, uid, eventSnapshot.data(), transaction)).manageEvent) {
        throw new HttpsError("permission-denied", "Event access denied.");
      }
      const prior = await transaction.get(decisionRef);
      if (prior.exists) {
        if (prior.get("fingerprint") !== fingerprint) throw new HttpsError("already-exists", "A request key cannot be reused with a different decision.");
        resultStatus = prior.get("status"); ticketId = prior.get("ticketId"); return;
      }
      require("./capacity").assertDecidable(eventSnapshot.data());
      const expectedStatus = decision === "promote" ? "waitlisted" : "pending";
      if (!registrationSnapshot.exists || registrationSnapshot.get("eventId") !== eventId ||
          registrationSnapshot.get("status") !== expectedStatus) {
        throw new HttpsError("failed-precondition", "Registration status changed before this decision.");
      }
      const registration = registrationSnapshot.data();
      const subjectUid = registration.customerUid || registration.userId;
      if (subjectUid && (await transaction.get(db.collection("account_deletion_jobs").doc(subjectUid))).exists) throw new HttpsError("failed-precondition", "The attendee is being deleted.");
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
        const {full} = require("./capacity").capacityState(eventSnapshot.data());
        if (full && (decision === "promote" || policy.waitlistEnabled === false)) {
          throw new HttpsError("resource-exhausted", "Capacity is still full.");
        }
        resultStatus = full && policy.waitlistEnabled !== false ? "waitlisted" : "confirmed";
        if (resultStatus === "confirmed") {
          transaction.update(eventRef, {confirmedRegistrationCount:
            admin.firestore.FieldValue.increment(1)});
          if (policy.mode === "free_ticket" || (!policy.mode && eventSnapshot.get("ticketsEnabled") && Number(eventSnapshot.get("ticketPrice") || 0) === 0)) {
            ticketId = `free_${crypto.createHash("sha256")
                .update(`${eventId}\0${registrationId}`).digest("hex").slice(0, 48)}`;
            transaction.create(db.collection("Tickets").doc(ticketId), {
              id: ticketId, eventId, registrationId, eventTitle: String(eventSnapshot.get("title") || "Event"),
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
      transaction.create(decisionRef, {actorUid: uid, eventId, registrationId, fingerprint, status: resultStatus, ticketId, createdAt: admin.firestore.FieldValue.serverTimestamp()});
      transaction.update(registrationRef, {status: resultStatus, decisionByUid: uid,
        decidedAt: admin.firestore.FieldValue.serverTimestamp(), ticketId});
      if (guestSnapshot?.exists) {
        const messageId = `decision_${decisionRef.id}`;
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
            eventDurationMinutes: eventSnapshot.get("eventDurationMinutes") || null,
            eventDuration: eventSnapshot.get("eventDuration") || null,
            eventTimeZone: eventSnapshot.get("eventTimeZone") || "UTC",
            eventRevision: eventSnapshot.get("eventRevision") || 0,
            eventLocation: String(eventSnapshot.get("location") || ""),
            kind: (eventSnapshot.get("registrationPolicy") || {}).mode || "rsvp",
            manageUrl: `${publicOrigin()}/manage/${rawManageToken}`,
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
    previewEventChangeV1: createPreviewEventChange(admin),
    publishEventDraftV1: createPublishEventDraft(admin),
    decideEventRegistrationV1: createDecideEventRegistration(admin),
  };
}

module.exports = {
  consumePublicationAllowance,
  tierFromSubscription,
  createEventWizardFunctions,
  eventDocument,
  groupAccess,
  draftStoragePath,
  signInMethods,
};
