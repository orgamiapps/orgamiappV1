"use strict";

// Mutations use only browser-authenticated, App-Check-protected callables.
// The optional database adapter below only observes private QA evidence.
const crypto = require("node:crypto");
const {isDeepStrictEqual} = require("node:util");
const {bindingId, emailHash, validScope} = require("../../functions/communications/qualification-isolation");
const {schedule} = require("../../functions/events/schedule");
const {digest} = require("../web_release_contract");
const {normalizePolicy, policyWindow} = require("../../functions/attendance/v2");
const PROJECT = "attendus-staging";
const ROLES = ["owner", "attendee", "staff", "unauthorized"];
const hash = (value) => crypto.createHash("sha256").update(value).digest("hex");
const safeId = (value) => typeof value === "string" && /^[A-Za-z0-9_.:-]{1,500}$/.test(value);
const announcementTitle = (fixture) => `Controlled pilot ${fixture.runId}`;
const announcementBody = "Synthetic qualification announcement; delivery must remain captured.";

function validatePilot(fixture, candidateIdentity) {
  if (candidateIdentity?.projectId !== PROJECT || !/^[a-f0-9]{40}$/.test(candidateIdentity.sourceSha || "") ||
      !candidateIdentity.candidateRunId || fixture?.projectId !== PROJECT ||
      fixture.candidateRunId !== candidateIdentity.candidateRunId || fixture.sourceSha !== candidateIdentity.sourceSha ||
      !/^webqa-[0-9]{8}-[a-f0-9]{10}$/.test(fixture.runId || "") ||
      fixture.controlledRecipientDomain !== "example.test" || !Array.isArray(fixture.ownedFixtureIds) ||
      !safeId(fixture.event?.id) || !fixture.ownedFixtureIds.includes(fixture.event.id) ||
      !Number.isFinite(Date.parse(fixture.eventClosesAt))) throw Error("Pilot requires the bound synthetic staging candidate.");
  for (const role of ROLES) {
    const account = fixture[role];
    if (!safeId(account?.uid) || !fixture.ownedFixtureIds.includes(account.uid) ||
        account.email !== `${fixture.runId}-${role}@example.test`) throw Error("Pilot actor is outside the controlled fixture.");
  }
  if (new Set(ROLES.map((role) => fixture[role].uid)).size !== ROLES.length) throw Error("Pilot roles must use distinct accounts.");
  return {schemaVersion: 1, projectId: PROJECT, sourceSha: candidateIdentity.sourceSha,
    candidateRunId: candidateIdentity.candidateRunId, runId: fixture.runId, eventId: fixture.event.id};
}

// No write methods are used by this observer. Callers supply an evidence ADC
// Firestore instance; browser credentials remain entirely inside callAs.
function createPilotObserver({fixture, candidateIdentity, db}) {
  const identity = validatePilot(fixture, candidateIdentity);
  if (db.projectId !== PROJECT || process.env.FIRESTORE_EMULATOR_HOST) throw Error("Pilot observation requires staging Firestore.");
  const bounded = async (query, limit = 100) => {
    const result = await query.limit(limit + 1).get();
    if (result.size > limit) throw Error("Pilot observation exceeded its owned fixture budget.");
    return result.docs;
  };
  return async function observe(selection = {}) {
    const event = await db.runTransaction(async (tx) => {
      const refs = [db.doc(`Events/${identity.eventId}`), db.doc(`QualificationScopes/${identity.runId}`),
        db.doc(`QualificationSetup/${identity.runId}`), db.doc(`QualificationBindings/${bindingId("event", identity.eventId)}`),
        ...ROLES.map((role) => db.doc(`QualificationBindings/${bindingId("account", fixture[role].uid)}`)),
        ...ROLES.map((role) => db.doc(`account_deletion_jobs/${fixture[role].uid}`))];
      const [event, scope, setup, ...rest] = await Promise.all(refs.map((ref) => tx.get(ref)));
      const bindings = rest.slice(0, ROLES.length + 1), deletions = rest.slice(ROLES.length + 1);
      if (!event.exists || event.get("customerUid") !== fixture.owner.uid || event.get("status") !== "active" || event.get("private") !== false ||
          event.get("isHidden") === true || event.get("isDeleted") === true ||
          event.get("checkInPolicy")?.eligibility !== "registered_only" ||
          !(event.get("checkInStaff") || []).includes(fixture.staff.uid) ||
          !validScope(scope.data(), identity.runId, PROJECT, Date.now()) ||
          !scope.get("eventIds").includes(identity.eventId) || ROLES.some((role) =>
            !scope.get("actorUids").includes(fixture[role].uid) || !scope.get("recipientUids").includes(fixture[role].uid)) ||
          setup.get("state") !== "seeded" || setup.get("projectId") !== PROJECT ||
          setup.get("sourceSha") !== identity.sourceSha || setup.get("candidateRunId") !== identity.candidateRunId ||
          bindings.some((row) => row.get("schemaVersion") !== 1 || row.get("projectId") !== PROJECT ||
            row.get("runId") !== identity.runId || row.get("state") !== "bound") || deletions.some((row) => row.exists)) {
        throw Error("Live pilot ownership, candidate identity or capture scope changed.");
      }
      const time = schedule(event.data());
      if (time.end?.toISOString() !== fixture.eventClosesAt) throw Error("Pilot schedule changed; use a separate lifecycle event.");
      const policy = normalizePolicy(event.data());
      return {id: event.id, revision: event.get("eventRevision") || 0, closesAt: time.end.toISOString(),
        effectiveClosesAt: new Date(policyWindow(event.data(), policy).closesAtMs).toISOString(),
        policySha256: digest(policy)};
    }, {readOnly: true});
    if (selection.guardOnly) return {event};
    const eventQuery = (collection) => db.collection(collection).where("eventId", "==", identity.eventId);
    const [registrations, attendance, previews, announcements, captures, messages, inbox, exports] = await Promise.all([
      bounded(eventQuery("RegisterAttendance")), bounded(eventQuery("Attendance")),
      bounded(eventQuery("EventAnnouncementPreviews")), bounded(eventQuery("EventAnnouncements")),
      bounded(db.collection("QualificationCaptures").where("runId", "==", identity.runId), 1000),
      bounded(eventQuery("OutboundMessages"), 500),
      bounded(db.collection("users").doc(fixture.attendee.uid).collection("notifications")),
      bounded(eventQuery("EventExportJobs")),
    ]);
    const matchesAnnouncement = (doc) => doc.get("actorUid") === fixture.owner.uid &&
      doc.get("title") === announcementTitle(fixture) && doc.get("body") === announcementBody && doc.get("audience") === "attendees";
    const existingAnnouncements = announcements.filter(matchesAnnouncement);
    const existingPreviews = previews.filter(matchesAnnouncement).filter((doc) => doc.get("ready") !== false);
    if (existingAnnouncements.length > 1 || existingPreviews.length > 1) throw Error("Pilot announcement identity is ambiguous; review before another send.");
    const prior = existingAnnouncements[0] || existingPreviews[0];
    return {event, observedAt: new Date().toISOString(),
      registrations: registrations.filter((doc) => doc.get("customerUid") === fixture.attendee.uid)
          .map((doc) => ({id: doc.id, status: doc.get("status"), identityType: doc.get("identityType")})),
      attendance: attendance.filter((doc) => doc.get("customerUid") === fixture.attendee.uid)
          .map((doc) => ({id: doc.id, registrationId: doc.get("registrationId"), status: doc.get("status")})),
      priorAnnouncement: prior ? {previewToken: prior.id, count: prior.get("count"), status: prior.get("status") || "preview",
        expiresAt: prior.get("expiresAt")?.toDate?.().toISOString() || null} : null,
      captures: captures.filter((doc) => (doc.get("eventIds") || []).includes(identity.eventId)).map((doc) => {
        const value = doc.data();
        return {id: doc.id, sourceKey: value.sourceKey, recipientUid: value.recipientUid || null, provider: value.provider,
          contentMatches: hash(JSON.stringify(value.payload)) === value.fingerprint,
          identityMatches: doc.id === hash(JSON.stringify([value.runId, value.recipientUid || value.recipientEmailHash, value.sourceKey]))};
      }),
      messages: messages.map((doc) => ({id: doc.id, announcementId: doc.get("announcementId") || null,
        status: doc.get("status"), provider: doc.get("provider") || null})),
      exports: exports.filter((doc) => doc.get("actorUid") === fixture.owner.uid).map((doc) => ({jobId: doc.id,
        status: doc.get("status"), generation: doc.get("generation") || null, rowCount: doc.get("rowCount") ?? null,
        objectPath: doc.get("path") || null, expiresAt: doc.get("expiresAt")?.toDate?.().toISOString() || null})),
      inboxCount: inbox.length};
  };
}

async function runBrowserPilot({fixture, candidateIdentity, callAs, observe, timeoutMs = 360000, pollIntervalMs = 3000}) {
  const identity = validatePilot(fixture, candidateIdentity);
  if (typeof callAs !== "function" || typeof observe !== "function" ||
      !Number.isFinite(timeoutMs) || timeoutMs < 1 || timeoutMs > 600000 ||
      !Number.isFinite(pollIntervalMs) || pollIntervalMs < 0 || pollIntervalMs > 15000) throw Error("Authenticated calls and bounded private observation are required.");
  const report = {schemaVersion: 1, identity, startedAt: new Date().toISOString(), assertions: [], observations: [],
    pilot: {registrationIds: [], attendanceIds: [], exportJobId: null, announcementId: null}, replayRequests: {}};
  const check = (id, expected, actual) => {
    report.assertions.push({id, expected, actual: actual ?? null});
    if (!isDeepStrictEqual(expected, actual)) throw Error(`Pilot assertion failed: ${id}`);
  };
  const call = async (role, name, data) => {
    await observe({guardOnly: true});
    return callAs(role, name, data);
  };
  const poll = async (name, read, ready) => {
    const until = Date.now() + timeoutMs;
    for (;;) {
      const result = await read();
      if (ready(result)) return result;
      if (Date.now() >= until) throw Error(`Pilot timed out waiting for ${name}.`);
      await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
    }
  };
  const deny = async (id, name, data) => {
    let code = "unexpected-success";
    try {await call("unauthorized", name, data);} catch (error) {code = String(error.status || error.code || "unknown").replace(/^functions\//, "").replaceAll("-", "_").toUpperCase();}
    check(id, "PERMISSION_DENIED", code);
  };
  try {
    const initial = await observe();
    report.observations.push({phase: "before", ...initial});
    const eventId = identity.eventId;
    const registrationInput = {eventId, idempotencyKey: `${fixture.runId}:account-registration`,
      fullName: "Controlled pilot attendee", email: fixture.attendee.email, answers: {access: "Controlled accessibility answer"}};
    report.replayRequests.registration = {role: "attendee", name: "startPublicRegistrationV3", data: registrationInput, requestSha256: digest(registrationInput)};
    const registered = await call("attendee", "startPublicRegistrationV3", registrationInput);
    check("account_registration_confirmed", "confirmed", registered.status);
    check("registration_receipt_has_id", true, safeId(registered.registrationId));
    report.pilot.registrationIds = [registered.registrationId];
    const registrationRetry = await call("attendee", "startPublicRegistrationV3", registrationInput);
    check("registration_retry_same_receipt", registered.registrationId, registrationRetry.registrationId);
    const session = await call("staff", "startCheckInSession", {eventId});
    check("staff_session_receipt_has_id", true, safeId(session.sessionId));
    check("staff_session_retry_same_receipt", session.sessionId, (await call("staff", "startCheckInSession", {eventId})).sessionId);
    const admission = {eventId, sessionId: session.sessionId, idempotencyKey: `${fixture.runId}:manual-admission`,
      credential: {type: "staff_roster", attendeeId: fixture.attendee.uid, registrationId: registered.registrationId},
      answers: ["Door access code--ans--Controlled door answer"]};
    report.replayRequests.admission = {role: "staff", name: "submitCheckIn", data: admission, requestSha256: digest(admission)};
    await deny("unauthorized_manual_admission_denied", "submitCheckIn", {...admission, idempotencyKey: `${fixture.runId}:unauthorized-admission`});
    const admitted = await call("staff", "submitCheckIn", admission);
    check("manual_admission_checked_in", "checked_in", admitted.status);
    check("attendance_receipt_has_id", true, safeId(admitted.attendanceId));
    report.pilot.attendanceIds = [admitted.attendanceId];
    const retry = await call("staff", "submitCheckIn", admission);
    check("admission_retry_same_receipt", admitted.attendanceId, retry.attendanceId);
    check("admission_retry_not_created", false, retry.created);
    const duplicate = await call("staff", "submitCheckIn", {...admission, idempotencyKey: `${fixture.runId}:duplicate-admission`});
    check("duplicate_admission_same_receipt", admitted.attendanceId, duplicate.attendanceId);
    check("duplicate_admission_not_created", false, duplicate.created);
    await deny("unauthorized_export_denied", "createEventExportV2", {eventId, idempotencyKey: `${fixture.runId}:unauthorized-export`});
    const materialized = await poll("authoritative roster", () => call("owner", "listEventRosterV2", {eventId, pageSize: 100}),
      (value) => (value.rows || []).some((row) => row.registrationId === registered.registrationId && row.attendanceIds?.includes(admitted.attendanceId)));
    check("roster_has_one_account_admission", 1, materialized.rows.filter((row) => row.registrationId === registered.registrationId).length);
    const exportInput = {eventId, idempotencyKey: `${fixture.runId}:pilot-export`};
    report.replayRequests.export = {role: "owner", name: "createEventExportV2", data: exportInput, requestSha256: digest(exportInput)};
    const exported = await call("owner", "createEventExportV2", exportInput);
    check("export_receipt_has_id", true, safeId(exported.jobId));
    report.pilot.exportJobId = exported.jobId;
    check("export_retry_same_receipt", exported.jobId, (await call("owner", "createEventExportV2", {eventId, idempotencyKey: `${fixture.runId}:pilot-export`})).jobId);
    const exportResult = await poll("completed export", () => call("owner", "getEventExportV2", {eventId, jobId: exported.jobId}), (value) => {
      if (["failed", "dead_letter", "cancelled"].includes(value.status)) throw Error("Pilot export did not complete.");
      return value.status === "complete";
    });
    check("export_includes_registered_admission", true, Number.isInteger(exportResult.rowCount) && exportResult.rowCount >= 1);
    check("export_has_immutable_generation", true, typeof exportResult.generation === "string" && exportResult.generation.length > 0);
    report.observations.push({phase: "export", jobId: exported.jobId, status: exportResult.status,
      rowCount: exportResult.rowCount, generation: exportResult.generation || null}); // Signed URL deliberately omitted.
    const beforeAnnouncement = await observe();
    report.pilotExport = beforeAnnouncement.exports?.find((value) => value.jobId === exported.jobId);
    check("original_export_completion_and_expiry_retained", true, report.pilotExport?.status === "complete" &&
      report.pilotExport.generation === exportResult.generation && report.pilotExport.rowCount === exportResult.rowCount &&
      new RegExp(`^private-event-exports/${exported.jobId}/[A-Za-z0-9_-]+\\.csv$`).test(report.pilotExport.objectPath || "") &&
      Date.parse(report.pilotExport.expiresAt) > Date.now());
    let preview = beforeAnnouncement.priorAnnouncement;
    if (preview && preview.status === "preview" && Date.parse(preview.expiresAt) <= Date.now()) throw Error("Existing pilot announcement preview expired; explicit review is required.");
    if (!preview) preview = await call("owner", "previewEventAnnouncementV1", {eventId, audience: "attendees",
      title: announcementTitle(fixture), body: announcementBody});
    check("announcement_has_attended_recipient", true, Number.isInteger(preview.count) && preview.count >= 1);
    const announcementInput = {eventId, previewToken: preview.previewToken};
    // This is permission-bound, not an authentication bearer. Still retain only
    // its digest; the replay observer resolves the exact original value privately.
    report.replayRequests.announcement = {role: "owner", name: "sendEventAnnouncementV1", requestSha256: digest(announcementInput)};
    const announced = await call("owner", "sendEventAnnouncementV1", announcementInput);
    check("announcement_receipt_has_id", true, safeId(announced.announcementId));
    report.pilot.announcementId = announced.announcementId;
    check("announcement_retry_same_receipt", announced.announcementId,
      (await call("owner", "sendEventAnnouncementV1", {eventId, previewToken: preview.previewToken})).announcementId);
    const completed = await poll("captured announcement", () => observe(), (value) => {
      const messages = value.messages.filter((row) => row.announcementId === announced.announcementId);
      if (messages.some((row) => ["failed", "dead_letter", "delivery_unknown"].includes(row.status) ||
          row.provider && row.provider !== "qualification_capture")) throw Error("Pilot delivery requires review.");
      return messages.length > 0 && messages.every((row) => row.status === "accepted" && row.provider === "qualification_capture") &&
        value.captures.some((row) => row.sourceKey === `announcement:${announced.announcementId}` && row.recipientUid === fixture.attendee.uid);
    });
    const state = await call("owner", "getEventAnnouncementV1", {eventId, announcementId: announced.announcementId});
    check("announcement_job_complete", "complete", state.status);
    check("announcement_no_failed_or_unknown_deliveries", 0, Number(state.failed) + Number(state.unknown));
    check("announcement_inbox_not_written", 0, state.inAppStored);
    check("account_registration_persisted_once", [registered.registrationId], completed.registrations.map((row) => row.id).sort());
    check("account_registration_type", "account", completed.registrations[0]?.identityType);
    check("attendance_persisted_once", [admitted.attendanceId], completed.attendance.map((row) => row.id).sort());
    check("attendance_resolves_registration", registered.registrationId, completed.attendance[0]?.registrationId);
    check("private_capture_fingerprints_valid", true, completed.captures.length > 0 && completed.captures.every((row) => row.contentMatches && row.identityMatches && row.provider === "qualification_capture"));
    check("announcement_email_has_matching_private_capture", true, completed.messages.filter((row) => row.announcementId === announced.announcementId)
        .every((message) => completed.captures.some((row) => row.sourceKey === `email:${message.id}`)));
    check("fixture_inbox_untouched", initial.inboxCount, completed.inboxCount);
    check("pilot_schedule_and_revision_unchanged", initial.event, completed.event);
    report.observations.push({phase: "after", ...completed});
    report.completedAt = new Date().toISOString();
    return report;
  } catch (error) {
    // Preserve partial actual receipts without serializing provider messages,
    // registration manage tokens, browser tokens, or signed export URLs.
    error.pilotReport = report;
    throw error;
  }
}

// A repeated email registration deliberately reveals no prior admission to a
// new anonymous session. Follow only the newly captured controlled-email proof,
// through the real browser; never write or exchange the proof in this observer.
function createGuestProofObserver({fixture, candidateIdentity, db}) {
  const identity = validatePilot(fixture, candidateIdentity);
  const guard = createPilotObserver({fixture, candidateIdentity, db});
  const recipientEmailHash = emailHash(`${fixture.runId}-guest@example.test`);
  const millis = (value) => value?.toMillis?.() ?? (value instanceof Date ? value.getTime() : NaN);
  return async function observeGuestProof({notBefore} = {}) {
    const requestedAt = Date.parse(notBefore), now = Date.now();
    if (!Number.isFinite(requestedAt) || requestedAt > now || now - requestedAt > 20 * 60000 ||
        Number.isFinite(Date.parse(fixture.runStartsAt)) && requestedAt < Date.parse(fixture.runStartsAt)) {
      throw Error("Guest proof requires a recent browser submission timestamp.");
    }
    await guard({guardOnly: true});
    return db.runTransaction(async (tx) => {
      const [scope, binding, setup, event, captures] = await Promise.all([
        tx.get(db.doc(`QualificationScopes/${identity.runId}`)),
        tx.get(db.doc(`QualificationBindings/${bindingId("event", identity.eventId)}`)),
        tx.get(db.doc(`QualificationSetup/${identity.runId}`)), tx.get(db.doc(`Events/${identity.eventId}`)),
        tx.get(db.collection("QualificationCaptures").where("runId", "==", identity.runId).limit(1001)),
      ]);
      if (!validScope(scope.data(), identity.runId, PROJECT, now) || !scope.get("recipientEmailHashes").includes(recipientEmailHash) ||
          !scope.get("eventIds").includes(identity.eventId) || binding.get("schemaVersion") !== 1 || binding.get("state") !== "bound" ||
          binding.get("projectId") !== PROJECT || binding.get("runId") !== identity.runId || setup.get("state") !== "seeded" ||
          setup.get("sourceSha") !== identity.sourceSha || setup.get("candidateRunId") !== identity.candidateRunId ||
          event.get("customerUid") !== fixture.owner.uid || event.get("private") !== false || event.get("status") !== "active" ||
          event.get("isHidden") === true || event.get("deleted") === true || event.get("isDeleted") === true ||
          captures.size > 1000) throw Error("Guest proof capture scope is unavailable or exceeds its bound.");
      const recent = captures.docs.filter((row) => row.get("recipientEmailHash") === recipientEmailHash &&
        (row.get("eventIds") || []).includes(identity.eventId) && /^email:registration_[A-Za-z0-9_-]+$/.test(row.get("sourceKey") || "") &&
        millis(row.get("capturedAt")) >= requestedAt).sort((a, b) => millis(b.get("capturedAt")) - millis(a.get("capturedAt")));
      if (!recent.length) return null;
      const capture = recent[0], value = capture.data(), payload = value.payload;
      const messageId = value.sourceKey.slice("email:".length);
      if (value.schemaVersion !== 1 || value.runId !== identity.runId || value.provider !== "qualification_capture" ||
          value.recipientUid || millis(value.capturedAt) > now || !Number.isFinite(millis(value.expiresAt)) || millis(value.expiresAt) <= now ||
          value.fingerprint !== hash(JSON.stringify(payload)) ||
          capture.id !== hash(JSON.stringify([identity.runId, recipientEmailHash, value.sourceKey])) ||
          payload?.messageId !== messageId || payload.eventId !== identity.eventId || payload.templateId !== "guest_registration_confirmation") {
        throw Error("Guest confirmation capture identity or fingerprint differs.");
      }
      const message = await tx.get(db.doc(`OutboundMessages/${messageId}`));
      if (message.get("status") === "sending") return null; // Capture commits just before delivery acknowledgement.
      if (message.get("status") !== "accepted" || message.get("provider") !== "qualification_capture" ||
          message.get("captureId") !== capture.id || message.get("eventId") !== identity.eventId ||
          message.get("templateId") !== payload.templateId || !safeId(message.get("registrationId")) || !safeId(message.get("guestId"))) {
        throw Error("Guest capture has no matching accepted source delivery.");
      }
      let url;
      try {url = new URL(message.get("payload")?.manageUrl);} catch (_) {throw Error("Guest confirmation proof URL is invalid.");}
      if (url.origin !== "https://attendus-staging.web.app" || url.username || url.password || url.search || url.hash ||
          !/^\/manage\/[A-Za-z0-9_-]{32,128}$/.test(url.pathname) ||
          ![payload.text, payload.html].some((text) => typeof text === "string" && text.includes(url.href))) {
        throw Error("Guest confirmation proof is not present in the captured staging email.");
      }
      const [token, registration, guest] = await Promise.all([
        tx.get(db.doc(`GuestManageTokens/${hash(url.pathname.slice("/manage/".length))}`)),
        tx.get(db.doc(`RegisterAttendance/${message.get("registrationId")}`)),
        tx.get(db.doc(`GuestAttendees/${message.get("guestId")}`)),
      ]);
      if (!token.exists || !["active", "exchanged"].includes(token.get("status")) || !Number.isFinite(millis(token.get("expiresAt"))) || millis(token.get("expiresAt")) <= now ||
          token.get("registrationId") !== registration.id || token.get("guestId") !== guest.id || !registration.exists || !guest.exists ||
          registration.get("eventId") !== identity.eventId || registration.get("guestId") !== guest.id ||
          registration.get("identityType") !== "guest" || !["confirmed", "pending", "waitlisted"].includes(registration.get("status"))) {
        throw Error("Guest proof no longer resolves to the controlled guest admission.");
      }
      const owners = [...new Set([registration.get("customerUid"), guest.get("ownerUid"), guest.get("claimedByUid")].filter(Boolean))];
      if ((await Promise.all(owners.map((uid) => tx.get(db.doc(`account_deletion_jobs/${uid}`))))).some((row) => row.exists)) {
        throw Error("Guest admission is unavailable during account deletion.");
      }
      return {manageUrl: url.href, registrationId: registration.id, status: registration.get("status"),
        captureId: capture.id, fingerprint: value.fingerprint};
    }, {readOnly: true});
  };
}

module.exports = {runBrowserPilot, createPilotObserver, createGuestProofObserver, validatePilot};
