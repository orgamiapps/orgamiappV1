"use strict";

const crypto = require("node:crypto");
const {onCall} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {Timestamp, FieldValue} = require("firebase-admin/firestore");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {geohashQueryBounds, geohashForLocation} = require("geofire-common");
const core = require("./arrival-core");
const legacy = () => require("./v2");
const read = (reader, reference) => typeof reader.get === "function" ? reader.get(reference) : reference.get();
const SIGNING_KEY = defineSecret("ATTENDANCE_PASS_SIGNING_KEY");
const OPTIONS = {region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true", maxInstances: 40};
const id = (value) => {
  if (typeof value !== "string" || !value || value.length > 500 || value.includes("/")) core.fail("Invalid identifier.", "invalid-argument");
  return value;
};

async function rollout(db, feature, eventId, uid) {
  const doc = await db.collection("AppConfig").doc("attendance").get();
  const settings = doc.data() || {};
  const config = settings[feature] || (feature === "corePasses" ? settings.wallet : null) || {};
  return config.enabled === true && (!Array.isArray(config.userIds) || !config.userIds.length || config.userIds.includes(uid)) && (config.allEvents === true ||
    (eventId && Array.isArray(config.eventIds) && config.eventIds.includes(eventId)) ||
    (!eventId && ["wallet", "corePasses", "appleDelivery", "googleDelivery"].includes(feature) && config.identityEnabled === true));
}

async function requireRollout(db, feature, eventId, uid) {
  if (!(await rollout(db, feature, eventId, uid))) core.fail("This feature is not available for this event yet.");
}

async function readEvent(reader, db, eventId) {
  const snapshot = await read(reader, db.collection("Events").doc(id(eventId)));
  if (!snapshot.exists || !core.activeEvent(snapshot.data())) core.fail("This event is not available.");
  return {...snapshot.data(), id: snapshot.id};
}

// Reader is either Firestore or its transaction. All authoritative eligibility
// reads are repeated within the attendance transaction before any write.
async function entitlement(reader, db, event, uid, selection = {}, requireAdmission = false, staffOverride = false) {
  const sources = await Promise.all(["RegisterAttendance", "Tickets"].map(async (collection) => {
    const snapshots = await Promise.all(["customerUid", "userId"].map((field) => read(reader,
        db.collection(collection).where("eventId", "==", event.id).where(field, "==", uid))));
    const docs = [...new Map(snapshots.flatMap((snapshot) => snapshot.docs).map((doc) => [doc.id, doc])).values()]
        .filter((doc) => (doc.get("customerUid") || doc.get("userId")) === uid);
    return {docs, size: docs.length};
  }));
  const [regs, tickets] = sources;
  const rows = require("../events/roster").buildRoster(...sources.map((source) => source.docs.map((doc) => ({...doc.data(), id: doc.id}))), [], [], event)
      .filter((row) => row.status === "confirmed");
  const matches = rows.filter((row) => (!selection.registrationId || row.registrationId === selection.registrationId) &&
    (!selection.ticketId || row.ticketId === selection.ticketId));
  if (matches.length > 1) {
    throw new (require("firebase-functions/v2/https").HttpsError)("failed-precondition",
        "Select the individual admission to use.", {admissions: matches.map((row) => ({registrationId: row.registrationId, ticketId: row.ticketId, label: row.name})),
          tickets: matches.filter((row) => row.ticketId).map((row) => ({id: row.ticketId, label: row.name}))});
  }
  const selected = matches[0];
  if (!selected && (selection.registrationId || selection.ticketId || regs.size || tickets.size)) core.fail("This admission is no longer confirmed.", "permission-denied");
  const registration = selected?.registrationId ? regs.docs.find((doc) => doc.id === selected.registrationId) || null : null;
  const ticket = selected?.ticketId ? tickets.docs.find((doc) => doc.id === selected.ticketId) || null : null;
  if (registration && ticket && ((ticket.get("registrationId") && ticket.get("registrationId") !== registration.id) ||
      (registration.get("ticketId") && registration.get("ticketId") !== ticket.id))) core.fail("Admission links require organizer review.", "failed-precondition");
  const policy = legacy().normalizePolicy(event);
  if ((tickets.size > 0 && !ticket) || (event.ticketsEnabled && Number(event.ticketPrice) > 0 && !ticket)) core.fail("A valid paid ticket is required.", "permission-denied");
  if (event.private === true && !(await require("../events/access").capabilities(db, uid, event, reader === db ? null : reader)).operateDoor &&
      !(event.accessList || []).includes(uid) && !registration && !ticket) {
    const attendee = await read(reader, db.collection("Events").doc(event.id).collection("Attendees").doc(uid));
    if (!attendee.exists) core.fail("Event access is required.", "permission-denied");
  }
  if (!staffOverride && ((policy.eligibility === "registered_only" && !registration) ||
      (policy.eligibility === "ticket_required" && !ticket) ||
      (requireAdmission && !registration && !ticket))) core.fail("A confirmed registration or valid ticket is required.", "permission-denied");
  const key = ticket ? `ticket:${ticket.id}` : registration ? `registration:${registration.id}` : `user:${uid}`;
  return {registration, ticket, key, uid, ticketCount: tickets.docs.filter((doc) => core.validTicket(doc.data(), event)).length,
    name: ticket?.data().customerName || registration?.data().realName || registration?.data().userName,
    answers: registration?.data().answers || []};
}

async function keys(db) {
  const snapshot = await db.collection("AttendanceSigningKeys").get();
  return Object.fromEntries(snapshot.docs.map((d) => [d.id, d.data()]));
}

async function issuePass(db, uid, input, options = {}) {
  const startedAt = Date.now();
  try {
    return await issuePassInternal(db, uid, input, options);
  } catch (error) {
    // Deliberately whitelist fields: requests may contain credentials, answers,
    // or coordinates and provider error messages can contain sensitive data.
    const safeId = value => typeof value === "string" && value.length <= 500 && !value.includes("/") ? value : null;
    const allowedCodes = ["invalid-argument", "unauthenticated", "permission-denied", "failed-precondition",
      "not-found", "resource-exhausted", "unavailable", "deadline-exceeded", "aborted", "internal"];
    try {
      await db.collection("CheckInAudit").doc().set({action: "attendance_pass_issue_failed",
        kind: input?.kind === "identity" ? "identity" : "event",
        eventId: input?.kind === "identity" ? null : safeId(input?.eventId), actorUid: safeId(uid),
        failureCode: allowedCodes.includes(error?.code) ? error.code : "internal",
        durationMs: Math.max(0, Date.now() - startedAt), createdAt: Timestamp.now()});
    } catch (_) { /* Telemetry must never replace the original issuance denial. */ }
    throw error;
  }
}

async function issuePassInternal(db, uid, input, {fullAccount = false} = {}) {
  const kind = input.kind === "identity" ? "identity" : "event";
  if (kind === "identity" && !fullAccount) core.fail("Sign in to get your reusable Attendus pass.", "unauthenticated");
  const eventId = kind === "event" ? id(input.eventId) : null;
  await requireRollout(db, "corePasses", eventId, uid);
  const material = JSON.parse(SIGNING_KEY.value() || "{}");
  if (!material.kid || !material.privateKey) core.fail("Pass signing is not configured.");
  const publicKey = crypto.createPublicKey(material.privateKey).export({format: "jwk"}).x;
  const keyRef = db.collection("AttendanceSigningKeys").doc(id(material.kid));
  const now = Date.now();
  let result;
  await db.runTransaction(async (tx) => {
    const event = eventId ? await readEvent(tx, db, eventId) : null;
    const eligible = event ? await entitlement(tx, db, event, uid, input, true) : null;
    const customer = await tx.get(db.collection("Customers").doc(uid));
    if (kind === "identity" && !customer.exists) core.fail("Complete your account profile before creating a pass.");
    const passId = core.digest(`${kind}:${eventId || ""}:${eligible?.key || uid}`);
    const ref = db.collection("AttendancePasses").doc(passId);
    const [existing, keyDoc] = await Promise.all([tx.get(ref), tx.get(keyRef)]);
    if (keyDoc.data()?.revoked) core.fail("Pass signing is temporarily unavailable.");
    const previous = existing.data();
    if (previous?.status === "revoked" && previous.revocationReason !== "eligibility") core.fail("This pass was revoked. Ask event staff for assistance.", "permission-denied");
    const expiry = event ? legacy().policyWindow(event, legacy().normalizePolicy(event)).closesAtMs + core.DAY :
      previous?.expiresAtMs > now + 30 * core.DAY ? previous.expiresAtMs : now + 365 * core.DAY;
    if (expiry <= now) core.fail("This event has ended.");
    const changed = previous && (previous.expiresAtMs !== expiry || previous.status !== "active" || input.replace === true);
    const record = {id: passId, kind, eventId, ownerUid: uid,
      registrationId: eligible?.registration?.id || null, ticketId: eligible?.ticket?.id || null,
      admissionKey: eligible?.key || null,
      attendeeName: eligible?.name || customer.data()?.name || "Attendee",
      title: event?.title || "My Attendus pass", location: event?.location || "",
      startsAt: event ? new Date(legacy().eventDateMillis(event)).toISOString() : null,
      status: "active", revocationReason: null, credentialVersion: (previous?.credentialVersion || 1) + (changed ? 1 : 0),
      expiresAtMs: expiry, kid: material.kid, updatedAt: Timestamp.now(),
      appleAuthenticationToken: previous?.appleAuthenticationToken || crypto.randomBytes(32).toString("hex")};
    record.qrData = core.signPass(record, material);
    tx.set(keyRef, {publicKey, revoked: false}, {merge: true});
    tx.set(ref, record);
    tx.create(db.collection("CheckInAudit").doc(), {action: "attendance_pass_issued", kind, eventId, passId, actorUid: uid, createdAt: Timestamp.now()});
    tx.set(db.collection("AttendanceWalletJobs").doc(passId), {passId, status: "pending", attempts: 0, nextAttemptAtMs: 0, updatedAt: Timestamp.now()});
    result = {...record, passLockRequired: event?.checkInPolicy?.passLockEnabled === true};
  });
  return result;
}

async function passResponse(db, record) {
  const wallet = await require("./wallet").deliveryLinks(db, record);
  return {passId: record.id, kind: record.kind, eventId: record.eventId || "", sessionId: "",
    attendeeName: record.attendeeName, title: record.title, qrData: record.qrData,
    expiresAt: new Date(record.expiresAtMs).toISOString(), passLockRequired: record.passLockRequired || false,
    ...wallet};
}

async function resolvePass(db, token, at) {
  const payload = core.verifyPass(token, await keys(db), at);
  const snapshot = await db.collection("AttendancePasses").doc(payload.id).get();
  const pass = snapshot.data();
  if (!pass || pass.status !== "active" || pass.credentialVersion !== payload.cv || pass.kind !== payload.kind) core.fail("This pass is no longer valid.", "permission-denied");
  if (pass.kind === "event") {
    const linked = await (pass.registrationId ? db.collection("RegisterAttendance").doc(pass.registrationId) : db.collection("Tickets").doc(pass.ticketId)).get();
    if (!linked.exists) core.fail("This admission no longer exists.");
    pass.ownerUid = linked.data().customerUid;
  }
  return {payload, pass, ref: snapshot.ref};
}

async function prepareCredential(db, input, event, actorUid, manager) {
  if (input.credential.type === "location") {
    await requireRollout(db, "smartArrival", event.id, actorUid);
    core.verifyLocation(event, input.credential.position);
    const eligible = await entitlement(db, db, event, actorUid, input.credential);
    const customer = await db.collection("Customers").doc(actorUid).get();
    return {uid: actorUid, ticket: eligible.ticket,
      name: eligible.name || customer.data()?.name || legacy().cleanName(input.credential.fullName),
      verificationLevel: "location_assisted"};
  }
  if (!manager) core.fail("Only event staff can scan personal passes.", "permission-denied");
  const resolved = await resolvePass(db, input.credential.token || input.credential.value, input.observedAtMs);
  if (resolved.pass.eventId && resolved.pass.eventId !== event.id) core.fail("This pass is for another event.", "permission-denied");
  const eligible = await entitlement(db, db, event, resolved.pass.ownerUid, {
    registrationId: resolved.pass.registrationId, ticketId: resolved.pass.ticketId || input.credential.ticketId,
  }, resolved.pass.kind === "event");
  return {uid: resolved.pass.ownerUid, ticket: eligible.ticket, name: eligible.name || resolved.pass.attendeeName,
    passRef: resolved.ref, passPayload: resolved.payload,
    verificationLevel: "signed_personal_pass"};
}

async function ensureSession(db, event, actorUid, position, selection = {}) {
  await requireRollout(db, "smartArrival", event.id, actorUid);
  core.verifyLocation(event, position);
  const stateRef = db.collection("check_in_event_state").doc(event.id);
  const newRef = db.collection("CheckInSessions").doc();
  const secret = crypto.randomBytes(32).toString("base64url");
  const pair = crypto.generateKeyPairSync("ed25519");
  return db.runTransaction(async (tx) => {
    const fresh = await readEvent(tx, db, event.id);
    core.verifyLocation(fresh, position);
    await entitlement(tx, db, fresh, actorUid, selection);
    const state = await tx.get(stateRef);
    const window = legacy().policyWindow(fresh, legacy().normalizePolicy(fresh));
    core.assertWindow(window, state.data(), Date.now());
    const activeId = state.data()?.activeSessionId;
    if (activeId) {
      const active = await tx.get(db.collection("CheckInSessions").doc(activeId));
      if (active.data()?.status === "active") return activeId;
    }
    if (core.arrivalPolicy(fresh.checkInPolicy).openingMode !== "scheduled") core.fail("Check-in must be opened by staff.");
    tx.create(newRef, {id: newRef.id, eventId: event.id, status: "active",
      opensAt: Timestamp.fromMillis(window.opensAtMs), closesAt: Timestamp.fromMillis(window.closesAtMs),
      startedAt: Timestamp.now(), startedBy: "scheduled", tokenVersion: 1,
      passPublicKey: pair.publicKey.export({format: "jwk"}).x,
      venueCode: legacy().venueCode(secret), venueCodeExpiresAt: Timestamp.now()});
    tx.create(db.collection("check_in_session_secrets").doc(newRef.id), {sessionId: newRef.id, secret,
      passPrivateKey: pair.privateKey.export({format: "pem", type: "pkcs8"})});
    tx.set(stateRef, {eventId: event.id, activeSessionId: newRef.id, status: "active", updatedAt: Timestamp.now()}, {merge: true});
    return newRef.id;
  });
}

// All methods share this transaction, including legacy venue and staffed entry.
async function commitAttendance(db, context) {
  const {input, actorUid, subjectUid, displayName, source, verificationLevel,
    overrideReason, offlineStaff, ticket: selectedTicket, prepared} = context;
  return db.runTransaction(async (tx) => {
    const event = await readEvent(tx, db, input.eventId);
    const policy = legacy().normalizePolicy(event);
    const manager = (await require("../events/access").capabilities(db, actorUid, event)).operateDoor;
    const staffMethod = ["personal_pass", "attendance_pass", "staff_roster", "staff_guest"].includes(input.credential.type);
    if (staffMethod && !manager) core.fail("Event staff access is required.", "permission-denied");
    if (staffMethod && policy.profile === "self_check_in" && !policy.staffFallback) core.fail("Staff entry is not enabled.");
    if (!staffMethod && policy.profile === "staff_entry") core.fail("Self check-in is not enabled.");
    const at = offlineStaff ? input.observedAtMs : Date.now();
    const state = await tx.get(db.collection("check_in_event_state").doc(event.id));
    const session = await tx.get(db.collection("CheckInSessions").doc(input.sessionId));
    if (!session.exists || session.data().eventId !== event.id || (!offlineStaff && session.data().status !== "active")) core.fail("Check-in is closed.");
    const window = legacy().policyWindow(event, policy);
    core.assertWindow(window, state.data(), at);
    if (offlineStaff && input.offlineKitRevision && input.offlineKitRevision !== core.windowRevision(event, window)) {
      core.fail("The event schedule or policy changed after this roster was downloaded. Staff review is required.");
    }
    if (policy.needsOrganizerReview) core.fail("The organizer must review the check-in policy.");
    if (input.credential.type === "location") {
      const config = await tx.get(db.collection("AppConfig").doc("attendance"));
      const flag = config.data()?.smartArrival;
      if (!flag?.enabled || !(flag.allEvents || flag.eventIds?.includes(event.id)) ||
          (flag.userIds?.length && !flag.userIds.includes(actorUid))) core.fail("Smart Arrival is unavailable.");
      core.verifyLocation(event, input.credential.position);
    }
    let selected = {ticketId: selectedTicket?.id || input.credential.ticketId,
      registrationId: input.credential.registrationId};
    if (subjectUid && (await tx.get(db.collection("account_deletion_jobs").doc(subjectUid))).exists) {
      core.fail("This account is being deleted.", "permission-denied");
    }
    if (prepared?.passRef) {
      const pass = (await tx.get(prepared.passRef)).data();
      const key = (await tx.get(db.collection("AttendanceSigningKeys").doc(prepared.passPayload.kid))).data();
      core.verifyPass(input.credential.token || input.credential.value, {[prepared.passPayload.kid]: key}, at);
      const linkedOwner = pass?.kind === "event" ? (await tx.get(pass.registrationId ? db.collection("RegisterAttendance").doc(pass.registrationId) : db.collection("Tickets").doc(pass.ticketId))).data()?.customerUid : pass?.ownerUid;
      if (!pass || !key || key.revoked || pass.status !== "active" || pass.expiresAtMs < at ||
          linkedOwner !== subjectUid || pass.credentialVersion !== prepared.passPayload.cv ||
          (pass.eventId && pass.eventId !== event.id)) core.fail("This pass has changed. Refresh it before entry.");
      if (pass.kind === "identity" && !(await tx.get(db.collection("Customers").doc(subjectUid))).exists) core.fail("This account is no longer available.");
      selected = {ticketId: pass.ticketId || selected.ticketId, registrationId: pass.registrationId};
    }
    const override = manager && Boolean(overrideReason);
    const staffGuest = input.credential.type === "staff_guest";
    const eligible = staffGuest ? null : await entitlement(tx, db, event, subjectUid, selected, false, override);
    if (staffGuest && policy.eligibility !== "open" && !override) core.fail("A staff override reason is required.");
    const admissionKey = eligible?.key || context.subjectKey;
    const subjectRef = db.collection("AttendanceSubjects").doc(core.digest(`${event.id}:${admissionKey}`));
    const idemRef = db.collection("check_in_idempotency").doc(legacy().hash(`${actorUid}:${input.idempotencyKey}`, 20));
    const [subject, idem, historical, questions] = await Promise.all([
      tx.get(subjectRef), tx.get(idemRef),
      tx.get(db.collection("Attendance").where("eventId", "==", event.id).where("customerUid", "==", subjectUid)),
      tx.get(db.collection("Events").doc(event.id).collection("EventQuestions")),
    ]);
    const answers = require("./questions").mergeAttendanceAnswers(eligible?.answers, input.answers);
    if (require("./questions").requiredCheckInQuestions(questions.docs, answers).length) core.fail("Answer all required event questions before checking in.");
    const legacyHistory = historical.docs.filter((d) => !d.data().admissionKey);
    if (!subject.exists && eligible?.ticketCount > 1 && legacyHistory.some((d) => !d.data().ticketId)) {
      core.fail("Older attendance cannot be assigned to one of these tickets automatically. Staff must resolve the admission.");
    }
    const history = historical.docs.filter((d) =>
      (d.data().admissionKey === admissionKey || (!d.data().admissionKey &&
        (d.data().ticketId ? d.data().ticketId === eligible?.ticket?.id :
          staffGuest ? d.data().subjectKey === context.subjectKey : true))))
        .sort((a, b) => core.millis(b.data().checkedInAt || b.data().attendanceDateTime) - core.millis(a.data().checkedInAt || a.data().attendanceDateTime));
    const attendanceId = idem.data()?.attendanceId || subject.data()?.attendanceId || history[0]?.id || `v3_${core.digest(`${event.id}:${admissionKey}`).slice(0, 40)}`;
    if (idem.exists && (idem.data().eventId !== event.id ||
        (idem.data().admissionKey && idem.data().admissionKey !== admissionKey))) {
      core.fail("This request key belongs to a different check-in.", "invalid-argument");
    }
    const ref = db.collection("Attendance").doc(attendanceId);
    const existing = await tx.get(ref);
    const old = existing.data();
    if (existing.exists && (old.eventId !== event.id || old.status === "voided")) core.fail("Staff must review this attendance record.");
    if (idem.exists || (existing.exists && (!old.status || old.status === "checked_in"))) {
      if (!subject.exists) tx.set(subjectRef, {eventId: event.id, attendanceId, admissionKey});
      if (idem.data()?.receipt) return {...idem.data().receipt, created: false};
      const receipt = {attendanceId, created: false, status: old?.status || "checked_in",
        conflict: offlineStaff && !idem.exists, conflictReason: offlineStaff && !idem.exists ? "already_checked_in" : null,
        checkedInAt: new Date(core.millis(old?.checkedInAt || old?.attendanceDateTime) || Date.now()).toISOString()};
      if (!idem.exists) tx.create(idemRef, {actorUid, eventId: event.id, admissionKey, attendanceId, receipt,
        createdAt: Timestamp.now(), expiresAt: Timestamp.fromMillis(Date.now() + core.DAY)});
      return receipt;
    }
    if (existing.exists && (old.status === "voided" || !policy.allowReentry)) core.fail("Ask staff to review this previous attendance record.");
    if (eligible?.ticket?.data().isUsed && !existing.exists) core.fail("This ticket was already used.");
    const now = Timestamp.now();
    tx.set(ref, {id: attendanceId, eventId: event.id, sessionId: input.sessionId,
      admissionKey, subjectKey: context.subjectKey, customerUid: subjectUid,
      guestSessionId: context.anonymous ? subjectUid : null,
      userName: displayName, realName: displayName, attendanceDateTime: now,
      checkedInAt: now, observedAt: Timestamp.fromMillis(at), answers,
      isAnonymous: staffGuest || (eligible?.registration?.data().isAnonymous ?? context.anonymous), signInMethod: input.credential.type,
      source, verificationLevel, actorUid, status: "checked_in",
      reentryCount: existing.exists ? Number(old.reentryCount || 0) + 1 : 0,
      overrideReason: overrideReason || null, offlineReconciled: offlineStaff,
      ticketId: eligible?.ticket?.id || null, registrationId: eligible?.registration?.id || null,
      updatedAt: now}, {merge: true});
    tx.set(subjectRef, {eventId: event.id, admissionKey, attendanceId});
    const receipt = {attendanceId, created: !existing.exists, status: "checked_in", conflict: false, conflictReason: null,
      checkedInAt: now.toDate().toISOString()};
    tx.create(idemRef, {actorUid, eventId: event.id, admissionKey, attendanceId, receipt, createdAt: now,
      expiresAt: Timestamp.fromMillis(Date.now() + core.DAY)});
    if (eligible?.ticket) tx.update(eligible.ticket.ref, {isUsed: true, usedDateTime: now, usedBy: actorUid});
    return receipt;
  });
}

async function candidates(db, uid, position, eventId) {
  core.validatePosition(position);
  let docs;
  if (eventId) {
    docs = [await db.collection("Events").doc(id(eventId)).get()];
  } else {
    const registrations = await db.collection("RegisterAttendance").where("customerUid", "==", uid).get();
    const bounds = geohashQueryBounds([position.latitude, position.longitude], 1500);
    const results = await Promise.all(bounds.map(([start, end]) => db.collection("Events")
        .where("private", "==", false).orderBy("smartArrivalGeohash").startAt(start).endAt(end).limit(100).get()));
    const registeredDocs = await Promise.all([...new Set(registrations.docs.filter((d) => core.confirmedRegistration(d.data())).map((d) => d.data().eventId))]
        .map((value) => db.collection("Events").doc(id(value)).get()));
    docs = [...new Map([...results.flatMap((s) => s.docs), ...registeredDocs].map((d) => [d.id, d])).values()];
  }
  const found = [];
  for (const doc of docs) {
    if (!doc.exists) continue;
    const event = {...doc.data(), id: doc.id};
    try {
      if (!core.activeEvent(event) || !(await rollout(db, "smartArrival", doc.id, uid))) continue;
      core.verifyLocation(event, position);
      let eligible;
      let ticketOptions = [];
      try { eligible = await entitlement(db, db, event, uid); } catch (error) {
        if (!error.details?.tickets) throw error;
        ticketOptions = error.details.tickets;
        eligible = {ticket: true, answers: []};
      }
      const state = await db.collection("check_in_event_state").doc(doc.id).get();
      core.assertWindow(legacy().policyWindow(event, legacy().normalizePolicy(event)), state.data(), Date.now());
      if (core.arrivalPolicy(event.checkInPolicy).openingMode !== "scheduled" && state.data()?.status !== "active") continue;
      const questions = await db.collection("Events").doc(doc.id).collection("EventQuestions").get();
      found.push({eventId: doc.id, title: event.title, location: event.location,
        sessionId: state.data()?.activeSessionId || "", registered: Boolean(eligible.registration || eligible.ticket),
        distanceMeters: Math.round(core.distanceMeters(position, core.arrivalPolicy(event.checkInPolicy))),
        answers: eligible.answers, attendeeName: eligible.name || "", ticketOptions,
        questions: questions.docs.map((q) => ({id: q.id, ...q.data()}))});
    } catch (error) {
      if (eventId) throw error;
    }
  }
  return {events: found.sort((a, b) => Number(b.registered) - Number(a.registered) || a.distanceMeters - b.distanceMeters).slice(0, 20)};
}

async function offlineKit(db, eventId, sessionId, uid) {
  const event = await readEvent(db, db, eventId);
  if (!(await require("../events/access").capabilities(db, uid, event)).operateDoor) core.fail("Event staff access is required.", "permission-denied");
  const bundle = await legacy().getSessionBundle(db, id(sessionId));
  if (bundle.session.eventId !== eventId || bundle.session.status !== "active") core.fail("Open check-in before downloading a roster.");
  const window = legacy().policyWindow(event, legacy().normalizePolicy(event));
  const [passDocs, registrations, publicKeys, state, ticketDocs] = await Promise.all([
    db.collection("AttendancePasses").where("eventId", "==", eventId).get(),
    db.collection("RegisterAttendance").where("eventId", "==", eventId).get(), keys(db),
    db.collection("check_in_event_state").doc(eventId).get(),
    db.collection("Tickets").where("eventId", "==", eventId).get(),
  ]);
  core.assertWindow(window, state.data(), Math.max(Date.now(), window.opensAtMs));
  const rosterIds = [...new Set([...registrations.docs.filter((d) => core.confirmedRegistration(d.data())).map((d) => d.data().customerUid),
    ...ticketDocs.docs.filter((d) => core.validTicket(d.data(), event)).map((d) => d.data().customerUid)])];
  const identityDocs = await Promise.all(rosterIds.map((ownerUid) => db.collection("AttendancePasses").doc(core.digest(`identity::${ownerUid}`)).get()));
  const rosterAdmissions = {};
  const rosterAnswers = {};
  const admissionAnswers = {};
  for (const ownerUid of rosterIds) {
    try {
      const eligible = await entitlement(db, db, event, ownerUid);
      if (!eligible.ticket?.data().isUsed) {
        rosterAdmissions[ownerUid] = eligible.key;
        admissionAnswers[eligible.key] = eligible.answers;
        rosterAnswers[ownerUid] = eligible.answers;
      }
    } catch (_) { /* Multiple or invalid admissions require online selection. */ }
  }
  const eligibleTickets = [];
  for (const doc of ticketDocs.docs) {
    const ticket = doc.data();
    if (!core.validTicket(ticket, event)) continue;
    try {
      const eligible = await entitlement(db, db, event, ticket.customerUid, {ticketId: doc.id}, true);
      if (eligible.ticket?.id !== doc.id) continue;
      admissionAnswers[eligible.key] = eligible.answers;
      eligibleTickets.push({id: doc.id, admissionKey: eligible.key, ticketCode: ticket.ticketCode || null,
        isUsed: ticket.isUsed === true, answers: eligible.answers});
    } catch (error) {
      if (!["permission-denied", "failed-precondition", "not-found"].includes(error.code)) throw error;
      // Cached ticket codes receive the same current registration/access checks
      // as signed passes; a superficially active ticket alone is insufficient.
    }
  }
  const attendance = await db.collection("Attendance").where("eventId", "==", eventId).get();
  const checkedInAdmissions = [...new Set(attendance.docs.filter((d) => !d.data().status || d.data().status === "checked_in")
      .map((d) => d.data().admissionKey || (d.data().ticketId ? `ticket:${d.data().ticketId}` : rosterAdmissions[d.data().customerUid]))
      .filter(Boolean))];
  const passes = {};
  for (const doc of [...passDocs.docs, ...identityDocs]) {
    const pass = doc.data();
    if (!pass || pass.status !== "active") continue;
    try {
      const linked = pass.kind === "event" ? (pass.registrationId ? registrations.docs.find((d) => d.id === pass.registrationId) :
        ticketDocs.docs.find((d) => d.id === pass.ticketId)) : null;
      const eligible = await entitlement(db, db, event, linked?.data().customerUid || pass.ownerUid, pass, pass.kind === "event");
      if (eligible.ticket?.data().isUsed) continue;
      passes[pass.id] = {kind: pass.kind, credentialVersion: pass.credentialVersion,
        admissionKey: eligible.key, attendeeName: pass.attendeeName,
        answers: eligible.answers, status: pass.status, expiresAtMs: pass.expiresAtMs};
    } catch (_) { /* Ineligible or ambiguous admissions are resolved online. */ }
  }
  return {version: 2, eventId, sessionId, staffUid: uid, passPublicKey: bundle.session.passPublicKey,
    publicKeys, passes, rosterIds: Object.keys(rosterAdmissions), rosterAdmissions, rosterAnswers, checkedInAdmissions, admissionAnswers,
    tickets: eligibleTickets,
    questions: (await db.collection("Events").doc(eventId).collection("EventQuestions").get()).docs.map((d) => ({id: d.id, ...d.data()})),
    eligibility: legacy().normalizePolicy(event).eligibility,
    preparedAt: new Date().toISOString(), opensAt: new Date(window.opensAtMs).toISOString(),
    closesAt: new Date(window.closesAtMs).toISOString(), revision: core.windowRevision(event, window)};
}

function createArrivalFunctions(admin) {
  const db = admin.firestore();
  return {
    maintainSmartArrivalBoundary: onDocumentWritten({document: "Events/{eventId}", region: "us-central1", retry: true}, async (change) => {
      const snapshot = change.data?.after;
      if (!snapshot?.exists) return;
      let geohash = null;
      try {
        const boundary = core.validateBoundary(snapshot.data());
        geohash = geohashForLocation([boundary.latitude, boundary.longitude]);
      } catch (_) { /* Disabled or invalid boundaries never enter nearby discovery. */ }
      if ((snapshot.data().smartArrivalGeohash || null) !== geohash) await snapshot.ref.update({smartArrivalGeohash: geohash});
    }),
    getSmartArrivalCandidates: onCall(OPTIONS, async (request) => {
      const uid = legacy().requireAuth(request);
      await legacy().enforceRateLimit(db, uid, "smart_arrival_candidates");
      return candidates(db, uid, request.data?.position, request.data?.eventId);
    }),
    getAttendancePass: onCall({...OPTIONS, secrets: [SIGNING_KEY]}, async (request) => {
      const uid = legacy().requireAuth(request);
      await legacy().enforceRateLimit(db, uid, "attendance_pass_issue");
      return passResponse(db, await issuePass(db, uid, request.data || {}, {fullAccount: !legacy().isAnonymous(request)}));
    }),
    getAttendanceOfflineKit: onCall(OPTIONS, async (request) => {
      const uid = legacy().requireFullAccount(request);
      await legacy().enforceRateLimit(db, uid, "attendance_offline_kit");
      return offlineKit(db, id(request.data?.eventId), id(request.data?.sessionId), uid);
    }),
    getAttendanceScanContext: onCall(OPTIONS, async (request) => {
      const uid = legacy().requireFullAccount(request);
      await legacy().enforceRateLimit(db, uid, "attendance_scan_context", Date.now(), 1200);
      const event = await readEvent(db, db, id(request.data?.eventId));
      if (!(await require("../events/access").capabilities(db, uid, event)).operateDoor) core.fail("Event staff access is required.", "permission-denied");
      const token = request.data?.token;
      const resolved = await resolvePass(db, token, Date.now());
      if (resolved.pass.eventId && resolved.pass.eventId !== event.id) core.fail("This pass is for another event.");
      const eligible = await entitlement(db, db, event, resolved.pass.ownerUid, {
        registrationId: resolved.pass.registrationId, ticketId: resolved.pass.ticketId || request.data?.ticketId,
      }, resolved.pass.kind === "event");
      const questions = await db.collection("Events").doc(event.id).collection("EventQuestions").get();
      return {answers: eligible.answers, questions: questions.docs.map((d) => ({id: d.id, ...d.data()}))};
    }),
    getAttendanceControl: onCall(OPTIONS, async (request) => {
      const uid = legacy().requireFullAccount(request);
      const event = await readEvent(db, db, id(request.data?.eventId));
      if (!(await require("../events/access").capabilities(db, uid, event)).operateDoor) core.fail("Event staff access is required.", "permission-denied");
      const state = (await db.collection("check_in_event_state").doc(event.id).get()).data();
      const window = legacy().policyWindow(event, legacy().normalizePolicy(event));
      return {status: core.controlAt(state?.transitions), openingMode: core.arrivalPolicy(event.checkInPolicy).openingMode,
        opensAt: new Date(window.opensAtMs).toISOString(), closesAt: new Date(window.closesAtMs).toISOString()};
    }),
    setAttendanceControl: onCall(OPTIONS, async (request) => {
      const uid = legacy().requireFullAccount(request);
      const eventId = id(request.data?.eventId);
      await legacy().enforceRateLimit(db, uid, "attendance_control");
      const status = request.data?.status;
      if (!["paused", "closed", "open"].includes(status)) core.fail("Invalid check-in control.", "invalid-argument");
      await db.runTransaction(async (tx) => {
        const event = await readEvent(tx, db, eventId);
        if (!(await require("../events/access").capabilities(db, uid, event)).operateDoor) core.fail("Event staff access is required.", "permission-denied");
        const ref = db.collection("check_in_event_state").doc(eventId);
        await tx.get(ref);
        tx.set(ref, {eventId, transitions: FieldValue.arrayUnion({status, atMs: Date.now(), actorUid: uid}), updatedAt: Timestamp.now()}, {merge: true});
      });
      return {status};
    }),
  };
}

module.exports = {SIGNING_KEY, OPTIONS, rollout, requireRollout, readEvent, entitlement, keys,
  issuePass, passResponse, resolvePass, prepareCredential, ensureSession, commitAttendance,
  candidates, offlineKit, createArrivalFunctions};
