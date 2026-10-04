"use strict";
const {qualificationDecision, captureQualification} = require("../communications/qualification-isolation");
const {publicOrigin} = require("../public-web/origin");
const crypto = require("node:crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentWritten, onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {requireEvent, capabilities} = require("./access");
const {buildRoster, metrics, allDocuments, normalized, key} = require("./roster");
const {CONTACT_HMAC_KEY, CONTACT_KMS_KEY_NAME, emailHash, csvCell, decryptEmail,
  encryptEmail, enforceRateLimit} = require("../public-web/accountless");

const callOptions = {region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
  timeoutSeconds: 120, secrets: [CONTACT_HMAC_KEY, CONTACT_KMS_KEY_NAME]};

function createLaunchOperations(admin) {
  const db = admin.firestore();
  const stamp = () => admin.firestore.FieldValue.serverTimestamp();
  async function rebuild(eventId) {
    const stateRef = db.collection("EventRosters").doc(eventId);
    const [event, before] = await Promise.all([db.collection("Events").doc(eventId).get(), stateRef.get()]);
    if (!event.exists) return null;
    const revision = before.get("revision") || 0;
    const collections = ["RegisterAttendance", "Tickets", "Attendance", "HistoricalAttendance"];
    const snapshots = await Promise.all(collections.map((name) => allDocuments(db.collection(name).where("eventId", "==", eventId))));
    const sources = snapshots.map((list) => list.map((doc) => ({...doc.data(), id: doc.id})));
    const deleting = new Set();
    const subjectUids = [...new Set(sources.flat().map((row) => row.customerUid || row.userId).filter(Boolean))];
    for (const uid of subjectUids) {
      if ((await db.collection("account_deletion_jobs").doc(uid).get()).exists) deleting.add(uid);
    }
    for (let index = 0; index < 3; index++) sources[index] = sources[index].filter((row) => !deleting.has(row.customerUid || row.userId));
    for (let index = 0; index < snapshots[3].length; index++) {
      const changes = await allDocuments(snapshots[3][index].ref.collection("corrections"));
      changes.sort((a, b) => (a.get("createdAt") || a.get("recordedAt"))?.toMillis() - (b.get("createdAt") || b.get("recordedAt"))?.toMillis());
      for (const change of changes) {
        if (change.get("evidence")) Object.assign(sources[3][index], change.get("evidence"));
        if (change.get("operation") === "void") sources[3][index].voided = true;
      }
      if (sources[3][index].voided) {
        for (const active of sources[2]) if (key(active.id) === sources[3][index].sourceAttendanceHash) active.voided = true;
      }
    }
    const rows = buildRoster(...sources, event.data());
    const contacts = new Map();
    for (const row of rows) {
      if (row.status === "attended") continue;
      const path = row.guestId ? `GuestAttendees/${row.guestId}` : row.uid ? `Customers/${row.uid}` : null;
      if (!path) continue;
      if (!contacts.has(path)) contacts.set(path, await db.doc(path).get());
      const contact = contacts.get(path);
      row.emailRef = path;
      row.emailHash = contact.get("emailHash") || (contact.get("email") ? emailHash(contact.get("email")) : row.emailHash);
    }
    const generation = crypto.randomUUID();
    const root = stateRef.collection("generations").doc(generation);
    for (let offset = 0; offset < rows.length; offset += 350) {
      const batch = db.batch();
      for (const row of rows.slice(offset, offset + 350)) batch.set(root.collection("rows").doc(row.id), row);
      await batch.commit();
    }
    const summary = metrics(rows, event.data());
    await root.set({createdAt: stamp(), count: rows.length, summary});
    let published = false;
    await db.runTransaction(async (tx) => {
      const current = await tx.get(stateRef);
      const guards = await Promise.all(subjectUids.map((uid) => tx.get(db.collection("account_deletion_jobs").doc(uid))));
      if (guards.some((guard, index) => guard.exists !== deleting.has(subjectUids[index]))) return;
      if ((current.get("revision") || 0) !== revision) return;
      tx.set(stateRef, {generation, revision, ready: true, count: rows.length, summary, updatedAt: stamp()}, {merge: true});
      published = true;
    });
    if (!published) await db.recursiveDelete(root);
    return published ? {generation, summary, count: rows.length} : null;
  }
  async function roster(eventId) {
    let state = await db.collection("EventRosters").doc(eventId).get();
    if (!state.get("ready")) {
      await rebuild(eventId);
      state = await db.collection("EventRosters").doc(eventId).get();
    }
    if (!state.get("ready")) throw new HttpsError("unavailable", "Roster is updating. Retry shortly.");
    return {state, rows: state.ref.collection("generations").doc(state.get("generation")).collection("rows")};
  }
  function filterRows(query, filters) {
    if (filters.registrationStatus && filters.registrationStatus !== "all") query = query.where("status", "==", filters.registrationStatus);
    if (filters.attendanceStatus && filters.attendanceStatus !== "all") query = filters.attendanceStatus === "arrived" ? query.where("attendanceStatus", "in", ["checked_in", "checked_out"]) : query.where("attendanceStatus", "==", filters.attendanceStatus);
    const text = String(filters.query || "").trim();
    if (text.includes("@")) query = query.where("emailHash", "==", emailHash(text.toLowerCase()));
    else if (text.startsWith("#")) query = query.where("ticketCode", "==", text.slice(1).toUpperCase());
    else if (text) query = query.where("searchPrefixes", "array-contains", normalized(text).slice(0, 80));
    return query;
  }
  const getEventCapabilitiesV1 = onCall(callOptions, async (request) => {
    const uid = request.auth?.uid;
    const id = String(request.data?.eventId || "");
    if (!uid || !/^[A-Za-z0-9._:-]{1,500}$/.test(id)) throw new HttpsError("unauthenticated", "An event session is required.");
    const event = await db.collection("Events").doc(id).get();
    if (!event.exists) throw new HttpsError("not-found", "Event not found.");
    const permissions = await capabilities(db, uid, event.data());
    const staff = [];
    if (permissions.manageEvent) {
      for (const staffId of new Set([event.get("customerUid"), ...(event.get("coHosts") || []), ...(event.get("checkInStaff") || [])].filter(Boolean))) {
        const profile = await db.collection("Customers").doc(staffId).get();
        staff.push({uid: staffId, name: profile.get("name") || profile.get("fullName") || "Unavailable account", role: staffId === event.get("customerUid") || (event.get("coHosts") || []).includes(staffId) ? "Event manager" : "Door staff", available: profile.exists});
      }
    }
    return {permissions, staff};
  });
  const setEventStaffV1 = onCall(callOptions, async (request) => {
    const access = await requireEvent(db, request);
    const staff = request.data.staff;
    if (!Array.isArray(staff) || staff.length > 50 || staff.some((uid) => typeof uid !== "string" || !/^[A-Za-z0-9_-]{1,160}$/.test(uid))) throw new HttpsError("invalid-argument", "Choose up to 50 active staff accounts.");
    await db.runTransaction(async (tx) => {
      const event = await tx.get(access.document.ref);
      if (!(await capabilities(db, access.uid, event.data(), tx)).manageEvent) throw new HttpsError("permission-denied", "Event access changed.");
      for (const uid of new Set(staff)) {
        const profile = await tx.get(db.collection("Customers").doc(uid));
        const deleting = await tx.get(db.collection("account_deletion_jobs").doc(uid));
        if (!profile.exists || deleting.exists) throw new HttpsError("failed-precondition", "A selected account is unavailable.");
      }
      tx.update(access.document.ref, {checkInStaff: [...new Set(staff)]});
    });
    return {status: "updated"};
  });
  const listMyAdmissionsV1 = onCall(callOptions, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Open your registration session or sign in.");
    if ((await db.collection("account_deletion_jobs").doc(uid).get()).exists) throw new HttpsError("failed-precondition", "Account deletion is in progress.");
    const sources = await Promise.all(["RegisterAttendance", "Tickets"].map(async (name) => {
      const docs = (await Promise.all(["customerUid", "userId"].map((field) => allDocuments(db.collection(name).where(field, "==", uid))))).flat();
      return [...new Map(docs.map((doc) => [doc.id, {...doc.data(), id: doc.id}])).values()]
          .filter((row) => (row.customerUid || row.userId) === uid);
    }));
    const ids = [...new Set(sources.flat().map((row) => row.eventId).filter(Boolean))];
    const admissions = [];
    for (const id of ids) {
      const event = await db.collection("Events").doc(id).get();
      if (!event.exists) continue;
      const time = require("./schedule").schedule(event.data());
      if (!request.data?.history && time.end && time.end < new Date()) continue;
      for (const row of buildRoster(...sources.map((items) => items.filter((item) => item.eventId === id)), [], [], event.data())) {
        admissions.push({id: row.id, eventId: id, title: event.get("title") || "Event", status: event.get("cancelled") || event.get("status") === "cancelled" ? "cancelled" : row.status,
          registrationId: row.registrationId, ticketId: row.ticketId, start: time.start?.toISOString() || null, timeZone: time.timeZone});
      }
    }
    const orderKey = (row) => `${row.start || "9999-12-31T23:59:59.999Z"}|${row.eventId}|${row.id}`;
    admissions.sort((a, b) => orderKey(a).localeCompare(orderKey(b)));
    let after = null;
    if (request.data?.cursor) {
      try {
        const cursor = JSON.parse(Buffer.from(request.data.cursor, "base64url").toString());
        if (cursor.uid !== uid || cursor.history !== Boolean(request.data?.history) || typeof cursor.after !== "string" || cursor.after.length > 1100) throw Error("Invalid cursor");
        after = cursor.after;
      } catch (_) { throw new HttpsError("invalid-argument", "Refresh your registrations."); }
    }
    const remaining = after ? admissions.filter((row) => orderKey(row) > after) : admissions;
    const page = remaining.slice(0, 50);
    return {admissions: page, nextCursor: remaining.length > 50 ? Buffer.from(JSON.stringify({uid, history: Boolean(request.data?.history), after: orderKey(page[page.length - 1])})).toString("base64url") : null};
  });
  const listEventRosterV2 = onCall(callOptions, async (request) => {
    const access = await requireEvent(db, request, "operateDoor");
    const filterKey = key(JSON.stringify([request.data.query || "", request.data.registrationStatus || "all", request.data.attendanceStatus || "all"]));
    const {issueRosterCursor, verifyRosterCursor, ROSTER_CURSOR_TTL_MS} = require("./roster-cursor");
    const binding = {eventId: access.eventId, actorUid: access.uid, filterKey};
    const secret = CONTACT_HMAC_KEY.value();
    const cursor = request.data.cursor ? verifyRosterCursor(request.data.cursor, binding, secret) : null;
    const state = cursor ? await db.collection("EventRosters").doc(access.eventId).get() : (await roster(access.eventId)).state;
    const generation = cursor?.generation || state.get("generation");
    const generationRef = state.ref.collection("generations").doc(generation);
    const snapshot = await generationRef.get();
    if (!snapshot.exists) throw new HttpsError("aborted", "Roster snapshot expired. Refresh.");
    const rows = generationRef.collection("rows");
    const issuedAt = cursor?.issuedAt || Date.now();
    const expiresAt = cursor?.expiresAt || issuedAt + ROSTER_CURSOR_TTL_MS;
    const pageSize = Math.max(1, Math.min(100, Number(request.data.pageSize) || 50));
    let query = filterRows(rows, request.data).orderBy("__name__");
    const matchingCount = (await filterRows(rows, request.data).count().get()).data().count;
    if (cursor) {
      if (cursor.filterKey !== filterKey) throw new HttpsError("invalid-argument", "Search changed. Refresh the first page.");
      query = query.startAfter(cursor.id);
    }
    const result = await query.limit(pageSize + 1).get();
    const page = result.docs.slice(0, pageSize);
    await db.runTransaction(async (tx) => {
      const [generationState, currentEvent] = await Promise.all([tx.get(generationRef), tx.get(access.document.ref)]);
      if (!generationState.exists || generationState.get("deleting")) throw new HttpsError("aborted", "Roster snapshot expired. Refresh.");
      if (!(await capabilities(db, access.uid, currentEvent.data(), tx)).operateDoor) throw new HttpsError("permission-denied", "Event access changed.");
      const subjects = [...new Set(page.map((doc) => doc.get("uid")).filter(Boolean))];
      const guards = await Promise.all(subjects.map((uid) => tx.get(db.collection("account_deletion_jobs").doc(uid))));
      if (guards.some((guard) => guard.exists)) throw new HttpsError("aborted", "Roster changed for account deletion. Refresh after reconciliation.");
      tx.update(generationRef, {retainUntil: new Date(Math.max(expiresAt, generationState.get("retainUntil")?.toMillis() || 0))});
    });
    return {rows: page.map((doc) => {
      const row = {...doc.data()};
      delete row.emailHash; delete row.emailRef; delete row.searchPrefixes;
      delete row.registrationAnswers; delete row.attendanceAnswers;
      return row;
    }), permissions: access.permissions, matchingCount, summary: {...snapshot.get("summary"),
      noShow: require("./schedule").schedule(access.event).end && require("./schedule").schedule(access.event).end <= new Date() && !access.event.cancelled && access.event.status !== "cancelled" ? snapshot.get("summary")?.remaining : null},
    snapshotAt: snapshot.get("createdAt"), newerDataAvailable: !state.get("ready") || generation !== state.get("generation"), total: snapshot.get("count"),
    nextCursor: result.size > pageSize ? issueRosterCursor({...binding, generation, issuedAt, expiresAt,
      id: page[page.length - 1].id}, secret) : null};
  });

  async function recipients(eventId, audience) {
    const {rows} = await roster(eventId);
    const snapshot = await allDocuments(audience === "attendees" ? rows.where("attendanceStatus", "in", ["checked_in", "checked_out"]) :
      audience === "active" ? rows.where("status", "in", ["confirmed", "pending", "waitlisted"]) : rows.where("status", "==", audience));
    // One communication per identity, even when it owns several admissions.
    return [...new Map(snapshot.map((doc) => { const row = doc.data(); return [row.guestId || row.uid || row.id, row]; })).values()].filter((row) => row.guestId || row.uid);
  }
  const previewEventAnnouncementV1 = onCall(callOptions, async (request) => {
    const access = await requireEvent(db, request);
    const audience = String(request.data.audience || "confirmed");
    if (!["confirmed", "pending", "waitlisted", "attendees"].includes(audience)) throw new HttpsError("invalid-argument", "Choose a valid audience.");
    const title = String(request.data.title || "").trim(); const body = String(request.data.body || "").trim();
    if (!title || title.length > 160 || !body || body.length > 4000) throw new HttpsError("invalid-argument", "Enter a title and message (up to 4,000 characters).");
    await enforceRateLimit(db, access.uid, "announcement_preview");
    const selected = await recipients(access.eventId, audience);
    const preview = db.collection("EventAnnouncementPreviews").doc();
    await preview.set({eventId: access.eventId, actorUid: access.uid, audience, title, body,
      recipientSource: preview.id, ready: false, count: selected.length,
      expiresAt: new Date(Date.now() + 10 * 60000), createdAt: stamp()});
    for (let offset = 0; offset < selected.length; offset += 350) {
      const batch = db.batch();
      for (const row of selected.slice(offset, offset + 350)) batch.create(preview.collection("recipients").doc(row.id), row);
      await batch.commit();
    }
    await preview.update({ready: true});
    return {previewToken: preview.id, count: selected.length};
  });
  const sendEventAnnouncementV1 = onCall(callOptions, async (request) => {
    const access = await requireEvent(db, request);
    const previewId = String(request.data.previewToken || "");
    if (!/^[A-Za-z0-9_-]+$/.test(previewId)) throw new HttpsError("invalid-argument", "Preview the announcement first.");
    const previewRef = db.collection("EventAnnouncementPreviews").doc(previewId);
    const job = db.collection("EventAnnouncements").doc(previewId);
    return db.runTransaction(async (tx) => {
      const [prior, preview, currentEvent] = await Promise.all([tx.get(job), tx.get(previewRef), tx.get(access.document.ref)]);
      if (!currentEvent.exists || !(await capabilities(db, access.uid, currentEvent.data(), tx)).manageEvent) throw new HttpsError("permission-denied", "Event access changed.");
      if (prior.exists && prior.get("actorUid") === access.uid && prior.get("eventId") === access.eventId) return {announcementId: job.id, count: prior.get("count")};
      if (!preview.exists || preview.get("ready") === false || preview.get("actorUid") !== access.uid || preview.get("eventId") !== access.eventId || preview.get("expiresAt").toMillis() < Date.now()) {
        throw new HttpsError("failed-precondition", "Preview expired. Review recipients again.");
      }
      tx.create(job, {...preview.data(), status: "queued", templateId: "event_announcement", createdAt: stamp()});
      return {announcementId: job.id, count: preview.get("count")};
    });
  });
  async function processAnnouncement(ref, heartbeat) {
    const document = await ref.get(); const job = document.data();
    if (!job || job.status === "complete") return;
    const event = await db.collection("Events").doc(job.eventId).get();
    if (!event.exists) throw new HttpsError("not-found", "Event not found.");
    const lifecycle = ["event_cancelled", "event_rescheduled"].includes(job.templateId);
    if (lifecycle && !job.eventSnapshot) throw new HttpsError("failed-precondition", "Legacy lifecycle job needs its original revision reviewed before delivery.");
    const eventPayload = job.eventSnapshot || require("./lifecycle-snapshot").lifecycleSnapshot(event.data());
    if (job.actorUid && !(await capabilities(db, job.actorUid, event.data())).manageEvent) {
      throw new HttpsError("permission-denied", "Organizer access was removed.");
    }
    let source;
    if (job.recipientSource) {
      source = db.collection("EventAnnouncementPreviews").doc(job.recipientSource).collection("recipients");
    } else {
      const generation = job.recipientGeneration || (await roster(job.eventId)).state.get("generation");
      const root = db.collection("EventRosters").doc(job.eventId).collection("generations").doc(generation);
      await heartbeat.transaction(async (tx) => {
        const snapshot = await tx.get(root);
        if (!snapshot.exists || snapshot.get("deleting")) throw new HttpsError("failed-precondition", "Recipient snapshot expired.");
        tx.update(root, {retainUntil: new Date(Date.now() + 86400000)});
        if (!job.recipientGeneration) tx.update(ref, {recipientGeneration: generation});
      });
      source = root.collection("rows");
      if (!job.recipientIds) source = job.audience === "attendees" ? source.where("attendanceStatus", "in", ["checked_in", "checked_out"]) :
        job.audience === "active" ? source.where("status", "in", ["confirmed", "pending", "waitlisted"]) : source.where("status", "==", job.audience);
    }
    async function* selectedPages() {
      let cursor = job.recipientCursor;
      for (;;) {
        let query = source.orderBy("__name__").limit(100);
        if (cursor) query = query.startAfter(cursor);
        const page = await query.get();
        for (const entry of page.docs) yield entry.data();
        if (page.empty) return;
        cursor = page.docs[page.docs.length - 1].id;
        await heartbeat.transaction(async (tx) => tx.update(ref, {recipientCursor: cursor}));
        if (page.size < 100) return;
      }
    }
    const allowed = job.recipientIds ? new Set(job.recipientIds) : null;
    for await (const row of selectedPages()) {
      await heartbeat();
      if (allowed && !allowed.has(row.id)) continue;
      const id = key(`${ref.id}:${row.guestId || row.uid || row.id}`);
      const marker = ref.collection("recipients").doc(id);
      if ((await marker.get()).exists) continue;
      let encryptedEmail = null; let maskedEmail = null;
      if (row.guestId) {
        const guest = await db.collection("GuestAttendees").doc(row.guestId).get();
        encryptedEmail = guest.get("encryptedEmail") || null; maskedEmail = guest.get("maskedEmail") || null;
      } else if (row.uid) {
        const customer = await db.collection("Customers").doc(row.uid).get();
        const email = customer.get("email");
        if (email) encryptedEmail = await encryptEmail(email);
      }
      await heartbeat.transaction(async (batch) => {
        if ((await batch.get(marker)).exists) return;
        const currentEvent = await batch.get(event.ref);
        if (job.actorUid && !(await capabilities(db, job.actorUid, currentEvent.data(), batch)).manageEvent) throw new HttpsError("permission-denied", "Organizer access was removed.");
        const deleting = row.uid ? await batch.get(db.collection("account_deletion_jobs").doc(row.uid)) : null;
        const customer = row.uid ? await batch.get(db.collection("Customers").doc(row.uid)) : null;
        const guest = row.guestId ? await batch.get(db.collection("GuestAttendees").doc(row.guestId)) : null;
        const registration = row.registrationId ? await batch.get(db.collection("RegisterAttendance").doc(row.registrationId)) : null;
        const ticket = row.ticketId ? await batch.get(db.collection("Tickets").doc(row.ticketId)) : null;
        if (job.templateId === "event_announcement" && job.audience !== "attendees") {
          const currentRows = buildRoster(registration?.exists ? [{id: registration.id, ...registration.data()}] : [], ticket?.exists ? [{id: ticket.id, ...ticket.data()}] : [], [], [], currentEvent.data());
          const eligible = currentRows.some((candidate) => (job.audience === "active" ? ["confirmed", "pending", "waitlisted"].includes(candidate.status) : candidate.status === job.audience) && candidate.uid === row.uid && candidate.guestId === row.guestId);
          if (!eligible) {
            batch.create(marker, {email: false, inApp: false, reason: "admission_ineligible", createdAt: stamp()});
            return;
          }
        }
        if (deleting?.exists || (row.guestId && !guest?.exists) || (!row.guestId && !customer?.exists)) {
          batch.create(marker, {email: false, inApp: false, reason: "account_unavailable", createdAt: stamp()});
          return;
        }
        const context = {actorUid: job.actorUid, recipientUid: row.uid, eventId: job.eventId, deferRecipientEmail: true};
        const isolation = await qualificationDecision(db, context, batch);
        if (isolation.mode === "suppress") {
          batch.create(marker, {email: false, inApp: false, reason: `qualification_${isolation.reason}`, createdAt: stamp()});
          return;
        }
        if (isolation.mode === "capture" && customer?.exists && row.identityType !== "guest") {
          await captureQualification(db, batch, isolation, context, `announcement:${ref.id}`, {
            title: job.title, body: job.body, type: "event_update", eventId: job.eventId, announcementId: ref.id,
          });
        }
        const inApp = isolation.mode === "normal" && customer?.exists && row.identityType !== "guest";
      if (inApp) batch.set(db.collection("users").doc(row.uid).collection("notifications").doc(id), {
        title: job.title, body: job.body, type: "event_update", eventId: job.eventId,
        eventTitle: eventPayload.eventTitle, createdAt: stamp(), isRead: false, data: {announcementId: ref.id, eventRevision: eventPayload.eventRevision},
      });
      if (encryptedEmail) batch.create(db.collection("OutboundMessages").doc(id), {
        ownerUid: row.uid || null, guestId: row.guestId || null, announcementId: ref.id, templateId: job.templateId, eventId: job.eventId,
        registrationId: row.registrationId || null, ticketId: row.ticketId || null,
        channel: "email", status: "pending", attempts: 0, encryptedEmail, maskedEmail,
        payload: {...eventPayload, title: job.title, body: job.body, calendarEligible: row.status === "confirmed",
          calendarPreviouslyConfirmed: job.templateId === "event_cancelled" && row.status === "confirmed" &&
            buildRoster(registration?.exists ? [{id: registration.id, ...registration.data()}] : [], ticket?.exists ? [{id: ticket.id, ...ticket.data()}] : [], [], currentEvent.data()).some((candidate) => candidate.status === "confirmed"),
          manageUrl: `${publicOrigin()}/event/${job.eventId}`},
        createdAt: stamp(), nextAttemptAt: new Date(),
      });
      batch.create(marker, {email: Boolean(encryptedEmail), inApp: Boolean(inApp), createdAt: stamp()});
      });
    }
    const [delivered, unreachable] = await Promise.all([
      ref.collection("recipients").count().get(),
      ref.collection("recipients").where("email", "==", false).where("inApp", "==", false).count().get(),
    ]);
    await heartbeat.transaction(async (tx) => {
      tx.update(ref, {status: "complete", unreachable: unreachable.data().count, count: delivered.data().count, completedAt: stamp()});
    });
  }
  const getEventAnnouncementV1 = onCall(callOptions, async (request) => {
    const access = await requireEvent(db, request);
    const id = String(request.data.announcementId || "");
    if (!/^[A-Za-z0-9_-]+$/.test(id)) throw new HttpsError("invalid-argument", "Invalid announcement.");
    const job = await db.collection("EventAnnouncements").doc(id).get();
    if (!job.exists || job.get("eventId") !== access.eventId) throw new HttpsError("not-found", "Announcement not found.");
    const messages = await allDocuments(db.collection("OutboundMessages").where("announcementId", "==", id));
    const counts = {queued: 0, accepted: 0, failed: 0, unknown: 0};
    for (const doc of messages) { const state = doc.get("status"); counts[state === "delivery_unknown" ? "unknown" : state === "accepted" ? "accepted" : ["failed", "dead_letter"].includes(state) ? "failed" : "queued"]++; }
    const recipients = await allDocuments(job.ref.collection("recipients"));
    if (job.get("status") === "queued") counts.queued += Math.max(0, Number(job.get("count") || 0) - recipients.length);
    return {status: job.get("status"), ...counts, inAppStored: recipients.filter((doc) => doc.get("inApp")).length, unreachable: job.get("unreachable") || 0};
  });

  const previewEventCancellationV1 = onCall(callOptions, async (request) => {
    const access = await requireEvent(db, request);
    const scope = request.data.recurrenceScope || "this_occurrence";
    if (!["this_occurrence", "this_and_future", "entire_series"].includes(scope)) throw new HttpsError("invalid-argument", "Choose an occurrence scope.");
    let targets = [access.document];
    if (scope !== "this_occurrence" && access.event.seriesId) {
      targets = (await allDocuments(db.collection("Events").where("seriesId", "==", access.event.seriesId)))
          .filter((doc) => scope === "entire_series" || require("./schedule").instant(doc.get("selectedDateTime")) >= require("./schedule").instant(access.event.selectedDateTime));
    }
    if (targets.length > 100) throw new HttpsError("failed-precondition", "Cancel at most 100 occurrences at once.");
    let count = 0;
    for (const target of targets) {
      if (!(await capabilities(db, access.uid, target.data())).manageEvent) throw new HttpsError("permission-denied", "Access to every selected occurrence is required.");
      count += (await recipients(target.id, "active")).length;
    }
    const preview = db.collection("EventCancellationPreviews").doc();
    await preview.create({eventId: access.eventId, actorUid: access.uid, scope, count,
      targets: targets.map((doc) => ({eventId: doc.id, revision: Number(doc.get("eventRevision") || 0)})),
      expiresAt: new Date(Date.now() + 10 * 60000)});
    return {previewToken: preview.id, count, occurrences: targets.length};
  });
  const cancelEventV1 = onCall(callOptions, async (request) => {
    const access = await requireEvent(db, request);
    const reason = String(request.data.reason || "").trim().slice(0, 1000);
    const previewId = String(request.data.previewToken || "");
    if (!reason || !/^[A-Za-z0-9_-]+$/.test(previewId)) throw new HttpsError("invalid-argument", "Review affected attendees and enter a cancellation reason.");
    const previewRef = db.collection("EventCancellationPreviews").doc(previewId);
    await db.runTransaction(async (tx) => {
      const preview = await tx.get(previewRef);
      if (!preview.exists || preview.get("actorUid") !== access.uid || preview.get("eventId") !== access.eventId) throw new HttpsError("not-found", "Cancellation preview not found.");
      if (preview.get("applied")) return;
      if (preview.get("expiresAt").toMillis() < Date.now()) throw new HttpsError("failed-precondition", "Preview expired. Review recipients again.");
      const targets = preview.get("targets");
      const events = await Promise.all(targets.map((target) => tx.get(db.collection("Events").doc(target.eventId))));
      for (let index = 0; index < events.length; index++) {
        const current = events[index];
        if (!current.exists || Number(current.get("eventRevision") || 0) !== targets[index].revision) throw new HttpsError("aborted", "An event changed. Refresh and review again.");
        if (!(await capabilities(db, access.uid, current.data(), tx)).manageEvent) throw new HttpsError("permission-denied", "Access to an occurrence changed.");
      }
      for (const current of events) {
        if (current.get("status") === "cancelled") continue;
        const revision = Number(current.get("eventRevision") || 0) + 1;
        tx.update(current.ref, {status: "cancelled", cancelled: true, cancellationReason: reason,
          eventRevision: revision, cancelledAt: stamp(), cancelledBy: access.uid});
        tx.set(db.collection("EventAnnouncements").doc(`cancel_${current.id}_${revision}`), {
          eventId: current.id, actorUid: access.uid, audience: "active", title: `Cancelled: ${current.get("title")}`,
          body: reason, templateId: "event_cancelled", eventSnapshot: require("./lifecycle-snapshot").lifecycleSnapshot({...current.data(), eventRevision: revision}), status: "queued", createdAt: stamp(),
        });
      }
      tx.update(previewRef, {applied: true, appliedAt: stamp()});
    });
    return {status: "cancelled"};
  });
  const deleteEmptyEventV1 = onCall(callOptions, async (request) => {
    const access = await requireEvent(db, request);
    await db.runTransaction(async (tx) => {
      const event = await tx.get(access.document.ref);
      if (!event.exists || !(await capabilities(db, access.uid, event.data(), tx)).manageEvent) throw new HttpsError("permission-denied", "Event access changed.");
      const dependents = await Promise.all(["RegisterAttendance", "Tickets", "Attendance", "HistoricalAttendance", "TicketPayments", "TicketUpgradePayments", "EventFeaturePayments", "FeaturePayments", "Payments"]
          .map((name) => tx.get(db.collection(name).where("eventId", "==", access.eventId).limit(1))));
      if (dependents.some((result) => !result.empty)) throw new HttpsError("failed-precondition", "This event has records. Cancel it to preserve its history.");
      if (event.exists) tx.delete(event.ref);
    });
    return {status: "deleted"};
  });

  const createEventExportV2 = onCall(callOptions, async (request) => {
    const access = await requireEvent(db, request);
    await enforceRateLimit(db, access.uid, "event_export");
    const idempotency = String(request.data.idempotencyKey || "");
    if (!/^[A-Za-z0-9._:-]{8,128}$/.test(idempotency)) throw new HttpsError("invalid-argument", "An export request key is required.");
    const ref = db.collection("EventExportJobs").doc(key(`${access.uid}:${access.eventId}:${idempotency}`));
    const filters = {query: String(request.data.query || ""), registrationStatus: String(request.data.registrationStatus || "all"), attendanceStatus: String(request.data.attendanceStatus || "all")};
    const fingerprint = key(JSON.stringify(filters));
    await db.runTransaction(async (tx) => {
      const existing = await tx.get(ref);
      if (existing.exists) {
        if (existing.get("fingerprint") !== fingerprint) throw new HttpsError("already-exists", "Export request key was used with different filters.");
        return;
      }
      const event = await tx.get(access.document.ref);
      if (!(await capabilities(db, access.uid, event.data(), tx)).manageEvent) throw new HttpsError("permission-denied", "Event access changed.");
      tx.create(ref, {eventId: access.eventId, actorUid: access.uid, status: "queued", createdAt: stamp(), filters, fingerprint});
    });
    return {jobId: ref.id};
  });
  async function processExport(ref, heartbeat) {
    const job = (await ref.get()).data();
    if (!job || job.status === "complete") return;
    const event = await db.collection("Events").doc(job.eventId).get();
    if (!event.exists || !(await capabilities(db, job.actorUid, event.data())).manageEvent) {
      throw new HttpsError("permission-denied", "Event access removed.");
    }
    const rosterState = job.generation ? await db.collection("EventRosters").doc(job.eventId).get() : (await roster(job.eventId)).state;
    const generation = job.generation || rosterState.get("generation");
    const generationRef = rosterState.ref.collection("generations").doc(generation);
    const sourceSnapshot = await generationRef.get();
    if (!sourceSnapshot.exists) throw new HttpsError("failed-precondition", "Export snapshot expired. Start a new export.");
    await heartbeat.transaction(async (tx) => {
      const snapshot = await tx.get(generationRef);
      if (!snapshot.exists || snapshot.get("deleting")) throw new HttpsError("failed-precondition", "Export snapshot expired.");
      tx.update(generationRef, {retainUntil: new Date(Date.now() + 86400000)});
      if (!job.generation) tx.update(ref, {generation, snapshotAt: stamp()});
    });
    const documents = await allDocuments(filterRows(generationRef.collection("rows"), job.filters));
    const output = [["Name", "Email", "Registration", "Attendance", "Checked in", "Checked out", "Generated at", "Event timezone", "Filters", "Row count", "Registration answers", "Attendance answers", "Snapshot ID", "Snapshot time"]];
    const generated = new Date().toISOString();
    const contacts = new Map();
    const subjects = new Set(documents.map((doc) => doc.get("uid")).filter(Boolean));
    const contactFingerprint = (contact) => key(JSON.stringify([contact.exists,
      ...["email", "encryptedEmail", "emailHash", "ownerUid", "claimedByUid"].map((field) => contact.get(field) ?? null)]));
    for (const doc of documents) {
      await heartbeat();
      const row = doc.data(); let email = "";
      if (row.emailRef) {
        if (!contacts.has(row.emailRef)) {
          const contact = await db.doc(row.emailRef).get();
          contacts.set(row.emailRef, {ref: contact.ref, fingerprint: contactFingerprint(contact),
            email: contact.get("encryptedEmail") ? await decryptEmail(contact.get("encryptedEmail")) : contact.get("email") || ""});
          for (const uid of [contact.get("ownerUid"), contact.get("claimedByUid")].filter(Boolean)) subjects.add(uid);
        }
        email = contacts.get(row.emailRef).email;
      }
      output.push([row.name, email, row.status, row.attendanceStatus, row.checkedInAt, row.checkedOutAt, generated, event.get("eventTimeZone") || "UTC", JSON.stringify(job.filters), documents.length, JSON.stringify(row.registrationAnswers || []), JSON.stringify(row.attendanceAnswers || []), generation, sourceSnapshot.get("createdAt")?.toDate().toISOString() || "unknown"]);
    }
    await heartbeat();
    if (!(await capabilities(db, job.actorUid, (await event.ref.get()).data())).manageEvent) throw new HttpsError("permission-denied", "Event access removed.");
    for (const uid of subjects) {
      if ((await db.collection("account_deletion_jobs").doc(uid).get()).exists) throw new HttpsError("failed-precondition", "An attendee is being deleted. Generate a fresh export after reconciliation.");
    }
    const path = `private-event-exports/${ref.id}/${job.leaseToken}.csv`;
    await admin.storage().bucket().file(path).save(output.map((row) => row.map(csvCell).join(",")).join("\r\n"),
        {contentType: "text/csv; charset=utf-8", metadata: {cacheControl: "private, no-store"}});
    try {
      await heartbeat.transaction(async (tx, current) => {
        const actualEvent = await tx.get(event.ref);
        if (current.get("leaseToken") !== job.leaseToken || current.get("leaseUntil")?.toMillis() <= Date.now()) throw new HttpsError("aborted", "Export lease expired.");
        if (!(await capabilities(db, job.actorUid, actualEvent.data(), tx)).manageEvent) throw new HttpsError("permission-denied", "Event access removed.");
        for (const contact of contacts.values()) {
          if (contactFingerprint(await tx.get(contact.ref)) !== contact.fingerprint) throw new HttpsError("failed-precondition", "Attendee contact information changed. Generate a fresh export.");
        }
        for (const uid of subjects) if ((await tx.get(db.collection("account_deletion_jobs").doc(uid))).exists) throw new HttpsError("failed-precondition", "An attendee is being deleted.");
        tx.update(ref, {status: "complete", path, subjectUids: [...subjects], generation, generatedAt: generated, snapshotAt: sourceSnapshot.get("createdAt"), contactsVerifiedAt: stamp(), rowCount: documents.length, completedAt: stamp(), expiresAt: new Date(Date.now() + 86400000)});
        tx.set(db.collection("admin_audit_logs").doc(`export_${ref.id}`), {action: "event.contacts.export", actorUid: job.actorUid, targetId: job.eventId, recordCount: documents.length, createdAt: stamp()});
      });
    } catch (error) {
      // A transport failure may follow a successful publication commit. Retain
      // the object if verification itself is unavailable; orphan cleanup can
      // retry, whereas deleting a committed export cannot be recovered here.
      let publication;
      try { publication = await ref.get(); } catch (_) { throw error; }
      if (!(publication.get("status") === "complete" && publication.get("path") === path)) {
        await admin.storage().bucket().file(path).delete({ignoreNotFound: true});
      }
      throw error;
    }
  }
  const getEventExportV2 = onCall(callOptions, async (request) => {
    const access = await requireEvent(db, request);
    const id = String(request.data.jobId || "");
    if (!/^[a-f0-9]{64}$/.test(id)) throw new HttpsError("invalid-argument", "Invalid export.");
    const job = await db.collection("EventExportJobs").doc(id).get();
    if (!job.exists || job.get("eventId") !== access.eventId || job.get("actorUid") !== access.uid) throw new HttpsError("not-found", "Export not found.");
    if (job.get("status") !== "complete") return {status: job.get("status")};
    const expiry = job.get("expiresAt");
    const expiresAt = typeof expiry?.toMillis === "function" ? expiry.toMillis() : NaN;
    if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) throw new HttpsError("not-found", "Export expired. Generate a new export.");
    for (const uid of job.get("subjectUids") || []) if ((await db.collection("account_deletion_jobs").doc(uid).get()).exists) throw new HttpsError("failed-precondition", "Export contains an attendee undergoing deletion. Generate a new export after reconciliation.");
    const now = Date.now();
    if (expiresAt <= now) throw new HttpsError("not-found", "Export expired. Generate a new export.");
    const [url] = await admin.storage().bucket().file(job.get("path")).getSignedUrl({action: "read", expires: Math.min(expiresAt, now + 5 * 60000)});
    return {status: "complete", url, rowCount: job.get("rowCount"), generation: job.get("generation"), filters: job.get("filters"), snapshotAt: job.get("snapshotAt"), generatedAt: job.get("generatedAt")};
  });

  const result = {setEventStaffV1, getEventCapabilitiesV1, listMyAdmissionsV1, listEventRosterV2, previewEventAnnouncementV1, sendEventAnnouncementV1,
    getEventAnnouncementV1, previewEventCancellationV1, cancelEventV1, deleteEmptyEventV1, createEventExportV2, getEventExportV2};
  result.refreshRosterEvent = onDocumentWritten({document: "Events/{id}", region: "us-central1"}, async (change) => {
    await db.collection("EventRosters").doc(change.params.id).set({ready: false,
      revision: admin.firestore.FieldValue.increment(1)}, {merge: true});
  });
  result.refreshRosterCorrection = onDocumentCreated({document: "HistoricalAttendance/{id}/corrections/{correction}", region: "us-central1"}, async (change) => {
    const record = await db.collection("HistoricalAttendance").doc(change.params.id).get();
    if (record.exists) await db.collection("EventRosters").doc(record.get("eventId")).set({ready: false,
      revision: admin.firestore.FieldValue.increment(1)}, {merge: true});
  });
  for (const name of ["RegisterAttendance", "Attendance", "Tickets", "HistoricalAttendance"]) {
    result[`refreshRoster${name}`] = onDocumentWritten({document: `${name}/{id}`, region: "us-central1"}, async (change) => {
      const ids = new Set([change.data?.before.get("eventId"), change.data?.after.get("eventId")].filter(Boolean));
      for (const id of ids) await db.collection("EventRosters").doc(id).set({ready: false,
        revision: admin.firestore.FieldValue.increment(1)}, {merge: true});
    });
  }
  for (const name of ["Customers", "GuestAttendees"]) {
    result[`refreshRoster${name}`] = onDocumentWritten({document: `${name}/{id}`, region: "us-central1"}, async (change) => {
      const events = new Set();
      for (const source of ["RegisterAttendance", "Tickets"]) {
        for (const doc of await allDocuments(db.collection(source).where(name === "Customers" ? "customerUid" : "guestId", "==", change.params.id))) if (doc.get("eventId")) events.add(doc.get("eventId"));
      }
      for (const id of events) await db.collection("EventRosters").doc(id).set({ready: false, revision: admin.firestore.FieldValue.increment(1)}, {merge: true});
    });
  }
  result.deliverEventAnnouncement = onDocumentCreated({document: "EventAnnouncements/{id}", region: "us-central1",
    timeoutSeconds: 540, secrets: [CONTACT_KMS_KEY_NAME, CONTACT_HMAC_KEY]}, (event) => require("./jobs").runJob(db, event.data.ref, processAnnouncement));
  result.generateEventExport = onDocumentCreated({document: "EventExportJobs/{id}", region: "us-central1",
    timeoutSeconds: 540, secrets: [CONTACT_KMS_KEY_NAME, CONTACT_HMAC_KEY]}, (event) => require("./jobs").runJob(db, event.data.ref, processExport));
  result.retryEventOperations = onSchedule({region: "us-central1", schedule: "every 5 minutes", timeoutSeconds: 540,
    secrets: [CONTACT_KMS_KEY_NAME, CONTACT_HMAC_KEY]}, async () => {
    for (const [collection, process] of [["EventAnnouncements", processAnnouncement], ["EventExportJobs", processExport]]) {
      const checkpoint = db.collection("EventOperationScans").doc(collection);
      const previous = await checkpoint.get();
      let query = db.collection(collection).where("status", "==", "queued").orderBy("__name__").limit(25);
      if (previous.get("cursor")) query = query.startAfter(previous.get("cursor"));
      const jobs = await query.get();
      for (const job of jobs.docs) await require("./jobs").runJob(db, job.ref, process);
      await checkpoint.set({cursor: jobs.size === 25 ? jobs.docs[jobs.size - 1].id : null, updatedAt: stamp()});
    }
    const cutoff = new Date(Date.now() - 86400000);
    const cleanupCheckpoint = db.collection("EventOperationScans").doc("rosterCleanup");
    const previousCleanup = await cleanupCheckpoint.get();
    let rootsQuery = db.collection("EventRosters").orderBy("__name__").limit(20);
    if (previousCleanup.get("cursor")) rootsQuery = rootsQuery.startAfter(previousCleanup.get("cursor"));
    const roots = await rootsQuery.get();
    for (const root of roots.docs) {
      const old = await root.ref.collection("generations").where("createdAt", "<=", cutoff).limit(20).get();
      for (const generation of old.docs) {
        const remove = await db.runTransaction(async (tx) => {
          const [currentRoot, current] = await Promise.all([tx.get(root.ref), tx.get(generation.ref)]);
          if (!current.exists || generation.id === currentRoot.get("generation") || current.get("retainUntil")?.toMillis() > Date.now()) return false;
          tx.update(generation.ref, {deleting: true});
          return true;
        });
        if (remove) await db.recursiveDelete(generation.ref);
      }
    }
    await cleanupCheckpoint.set({cursor: roots.size === 20 ? roots.docs[roots.size - 1].id : null, updatedAt: stamp()});
    for (const name of ["EventAnnouncementPreviews", "EventCancellationPreviews", "EventChangePreviews"]) {
      const expiredPreviews = await db.collection(name).where("expiresAt", "<=", cutoff).limit(50).get();
      for (const preview of expiredPreviews.docs) {
        const job = name === "EventAnnouncementPreviews" ? await db.collection("EventAnnouncements").doc(preview.id).get() : null;
        if (!job?.exists || ["complete", "failed"].includes(job.get("status"))) await db.recursiveDelete(preview.ref);
      }
    }
    const expired = await db.collection("EventExportJobs").where("expiresAt", "<=", new Date()).limit(50).get();
    for (const job of expired.docs) {
      if (job.get("path")) await admin.storage().bucket().file(job.get("path")).delete({ignoreNotFound: true});
      await job.ref.delete();
    }
  });
  return result;
}
module.exports = {createLaunchOperations};
