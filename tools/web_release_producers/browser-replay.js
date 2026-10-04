"use strict";

const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const {isDeepStrictEqual} = require("node:util");
const c = require("../web_release_contract");
const {pilotReceipt} = require("./operations");
const {validatePilot, createPilotObserver} = require("./browser-pilot");
const {digest: registrationDigest} = require("../../functions/public-web/accountless");
const GATE = "post-close-replay";
const RAW = "post-close-replay-receipt.json";
const safeId = (value) => typeof value === "string" && /^[A-Za-z0-9_.:-]{1,500}$/.test(value);
const hash = (value) => crypto.createHash("sha256").update(value).digest("hex");
const equal = (a, b) => isDeepStrictEqual(a, b);
const collections = ["PublicRegistrationFlows", "RegisterAttendance", "Tickets", "Attendance", "HistoricalAttendance", "AttendanceSubjects", "check_in_idempotency",
  "EventAnnouncements", "EventExportJobs", "OutboundMessages", "scheduledNotifications"];

function validateRequests(fixture, receipt) {
  const eventId = fixture.event.id, requests = receipt.replayRequests;
  if (!requests || !equal(Object.keys(requests).sort(), ["admission", "announcement", "export", "registration"])) throw Error("Original immutable replay requests are missing");
  const sessionId = requests.admission?.data?.sessionId;
  if (!safeId(sessionId) || receipt.pilot?.registrationIds?.length !== 1 || receipt.pilot?.attendanceIds?.length !== 1) throw Error("Original admission request is incomplete");
  const expected = {
    registration: {role: "attendee", name: "startPublicRegistrationV3", data: {eventId, idempotencyKey: `${fixture.runId}:account-registration`,
      fullName: "Controlled pilot attendee", email: fixture.attendee.email, answers: {access: "Controlled accessibility answer"}}},
    admission: {role: "staff", name: "submitCheckIn", data: {eventId, sessionId, idempotencyKey: `${fixture.runId}:manual-admission`,
      credential: {type: "staff_roster", attendeeId: fixture.attendee.uid, registrationId: receipt.pilot.registrationIds[0]},
      answers: ["Door access code--ans--Controlled door answer"]}},
    export: {role: "owner", name: "createEventExportV2", data: {eventId, idempotencyKey: `${fixture.runId}:pilot-export`}},
    announcement: {role: "owner", name: "sendEventAnnouncementV1", requestSha256: c.digest({eventId, previewToken: receipt.pilot.announcementId})},
  };
  for (const name of ["registration", "admission", "export"]) expected[name].requestSha256 = c.digest(expected[name].data);
  if (!equal(expected, requests)) throw Error("Original request envelope differs from its owned synthetic contract");
  const exported = receipt.pilotExport;
  if (exported?.jobId !== receipt.pilot.exportJobId || exported.status !== "complete" || !exported.generation ||
      !new RegExp(`^private-event-exports/${exported.jobId}/[A-Za-z0-9_-]+\\.csv$`).test(exported.objectPath || "") ||
      !Number.isInteger(exported.rowCount) || exported.rowCount < 1 || Date.parse(exported.expiresAt) <= Date.parse(receipt.completedAt) ||
      !Number.isFinite(Date.parse(exported.expiresAt))) throw Error("Original completed export expiry proof is missing");
  return expected;
}

function originalPilot(candidate, context) {
  const original = pilotReceipt(candidate, context);
  validatePilot(context.fixture, context);
  validateRequests(context.fixture, original.receipt);
  if (Date.parse(original.receipt.completedAt) >= Date.parse(context.fixture.eventClosesAt)) throw Error("Original authenticated pilot must precede actual event close");
  return original;
}

function createReplayObserver({fixture, candidateIdentity, db, original}) {
  const identity = validatePilot(fixture, candidateIdentity), requests = validateRequests(fixture, original.receipt);
  const guard = createPilotObserver({fixture, candidateIdentity, db});
  return async () => {
    const {event} = await guard({guardOnly: true});
    if (Date.now() <= Date.parse(event.effectiveClosesAt)) throw Error("Actual effective check-in close has not occurred");
    const result = await db.runTransaction(async (tx) => {
      const queries = collections.map((name) => db.collection(name).where("eventId", "==", identity.eventId).limit(2001));
      const snapshots = await Promise.all(queries.map((query) => tx.get(query)));
      if (snapshots.some((rows) => rows.size > 2000)) throw Error("Replay snapshot exceeds its owned fixture budget");
      const [captures, session, roster, eventDocument, doorState] = await Promise.all([
        tx.get(db.collection("QualificationCaptures").where("runId", "==", identity.runId).limit(2001)),
        tx.get(db.doc(`CheckInSessions/${requests.admission.data.sessionId}`)), tx.get(db.doc(`EventRosters/${identity.eventId}`)),
        tx.get(db.doc(`Events/${identity.eventId}`)),
        tx.get(db.doc(`check_in_event_state/${identity.eventId}`)),
      ]);
      if (captures.size > 2000 || !session.exists || session.get("eventId") !== identity.eventId) throw Error("Original session or bounded capture evidence is unavailable");
      const rows = Object.fromEntries(collections.map((name, index) => [name, snapshots[index].docs]));
      const find = (name, id) => rows[name].find((doc) => doc.id === id);
      const registration = find("RegisterAttendance", original.pilot.registrationIds[0]);
      const attendance = find("Attendance", original.pilot.attendanceIds[0]);
      const flowId = `flow_${registrationDigest("v3", identity.eventId, fixture.attendee.uid, requests.registration.data.idempotencyKey)}`;
      const flow = find("PublicRegistrationFlows", flowId);
      const fingerprint = registrationDigest(requests.registration.data.fullName, fixture.attendee.email,
          JSON.stringify(Object.entries(requests.registration.data.answers).sort(([a], [b]) => a.localeCompare(b))));
      if (!registration || registration.get("customerUid") !== fixture.attendee.uid || registration.get("status") !== "confirmed" ||
          !attendance || attendance.get("customerUid") !== fixture.attendee.uid || attendance.get("registrationId") !== registration.id ||
          attendance.get("sessionId") !== requests.admission.data.sessionId || attendance.get("status") !== "checked_in" ||
          !flow || flow.get("ownerUid") !== fixture.attendee.uid || flow.get("requestFingerprint") !== fingerprint ||
          flow.get("result")?.registrationId !== registration.id) throw Error("Original admission or registration receipt no longer matches");
      const announcement = find("EventAnnouncements", original.pilot.announcementId);
      if (!announcement || announcement.get("actorUid") !== fixture.owner.uid || announcement.get("status") !== "complete") throw Error("Original announcement is not a completed owned job");
      const announcementData = {eventId: identity.eventId, previewToken: announcement.id};
      if (c.digest(announcementData) !== requests.announcement.requestSha256) throw Error("Original announcement request digest changed");
      const exported = find("EventExportJobs", original.pilot.exportJobId), exportProof = original.receipt.pilotExport;
      const expired = Date.now() >= Date.parse(exportProof.expiresAt);
      if (exported && (exported.get("actorUid") !== fixture.owner.uid || exported.get("status") !== "complete" ||
          exported.get("generation") !== exportProof.generation || exported.get("expiresAt")?.toDate?.().toISOString() !== exportProof.expiresAt)) throw Error("Original export job differs");
      if (!exported && !expired) throw Error("An unexpired original export disappeared");
      const captureRows = captures.docs.filter((doc) => (doc.get("eventIds") || []).includes(identity.eventId));
      if (captureRows.some((doc) => doc.get("provider") !== "qualification_capture" || hash(JSON.stringify(doc.get("payload"))) !== doc.get("fingerprint"))) throw Error("Capture evidence is not isolated and intact");
      const projectRows = (docs) => docs.map((doc) => ({id: doc.id, sha256: c.digest(doc.data())})).sort((a, b) => a.id.localeCompare(b.id));
      return {state: {event, eventDocumentSha256: c.digest(eventDocument.data()), records: Object.fromEntries(collections.map((name) => [name, projectRows(rows[name])])),
        captures: projectRows(captureRows), rosterSha256: c.digest(roster.data() || null), sessionSha256: c.digest(session.data()),
        doorStateSha256: c.digest(doorState.data() || null)},
      announcementData, exportDecision: {action: expired ? "omitted-expired" : "replay", exists: !!exported, expiresAt: exportProof.expiresAt,
        originalJobId: exportProof.jobId, originalGeneration: exportProof.generation}};
    }, {readOnly: true});
    const afterGuard = await guard({guardOnly: true});
    if (!equal(event, afterGuard.event)) throw Error("Event policy or schedule changed during replay observation");
    return {...result, observedAt: new Date().toISOString()};
  };
}

// The adapter must execute fetch in the actual page. Node fetch is unaffected
// by browserContext.setOffline and cannot demonstrate browser reconnection.
async function pageCallable(page, {name, data, token, appCheckToken, actorUid}) {
  if (!token || !appCheckToken || !actorUid || !["startPublicRegistrationV3", "submitCheckIn", "createEventExportV2", "sendEventAnnouncementV1"].includes(name)) throw Error("Bound browser credentials and replay endpoint are required");
  return page.evaluate(async ({name, data, token, appCheckToken, actorUid}) => {
    const startedAt = new Date().toISOString(), online = navigator.onLine;
    try {
      const response = await fetch(`https://us-central1-attendus-staging.cloudfunctions.net/${name}`, {method: "POST",
        headers: {"content-type": "application/json", authorization: `Bearer ${token}`, "X-Firebase-AppCheck": appCheckToken},
        body: JSON.stringify({data}), signal: AbortSignal.timeout(120000)});
      const payload = await response.json();
      const value = payload.result ?? payload.data ?? {};
      return {transport: "page-fetch", actorUid, online, startedAt, finishedAt: new Date().toISOString(), httpStatus: response.status,
        status: payload.error?.status || (response.ok ? "OK" : "HTTP_ERROR"),
        result: {registrationId: value.registrationId || null, attendanceId: value.attendanceId || null,
          jobId: value.jobId || null, announcementId: value.announcementId || null, status: value.status || null, created: value.created ?? null}};
    } catch (_) {
      return {transport: "page-fetch", actorUid, online, startedAt, finishedAt: new Date().toISOString(), httpStatus: null, status: "NETWORK_ERROR", result: null};
    }
  }, {name, data, token, appCheckToken, actorUid});
}

async function runReplay({candidate, context, original, observe, connect, invoke, now = Date.now}) {
  const identity = validatePilot(context.fixture, context), requests = validateRequests(context.fixture, original.receipt);
  if (!equal(original.receipt.identity, identity) || candidate.projectId !== identity.projectId || candidate.sourceSha !== identity.sourceSha) throw Error("Original replay candidate identity differs");
  if (typeof observe !== "function" || typeof connect !== "function" || typeof invoke !== "function") throw Error("Replay requires actual browser and private observation adapters");
  const report = {schemaVersion: 1, identity, originalPilot: original.provenance, startedAt: new Date(now()).toISOString(), assertions: [], requests: [], snapshots: []};
  const check = (id, expected, actual) => {report.assertions.push({id, expected, actual}); if (!equal(expected, actual)) throw Error(`Replay assertion failed: ${id}`);};
  const validTransport = (attempt, request, offline) => attempt?.transport === "page-fetch" && attempt.actorUid === context.fixture[request.role].uid &&
    attempt.online === !offline && Number.isFinite(Date.parse(attempt.startedAt)) && Date.parse(attempt.startedAt) >= Date.parse(report.startedAt) &&
    Date.parse(attempt.finishedAt) >= Date.parse(attempt.startedAt) && Date.parse(attempt.finishedAt) <= now() + 1000 &&
    (offline ? attempt.httpStatus === null && attempt.status === "NETWORK_ERROR" : Number.isInteger(attempt.httpStatus) && attempt.httpStatus >= 200 && attempt.httpStatus < 600);
  try {
    const before = await observe();
    report.snapshots.push({phase: "before", ...before.state, observedAt: before.observedAt});
    check("real_effective_close_precedes_replay", true, now() > Date.parse(before.state.event.effectiveClosesAt) && before.state.event.closesAt === context.fixture.eventClosesAt);
    const initialEvent = original.receipt.observations.find((row) => row.phase === "after")?.event;
    check("original_event_policy_and_schedule_unchanged", initialEvent, before.state.event);
    report.effectiveClosesAt = before.state.event.effectiveClosesAt;
    report.exportDecision = before.exportDecision;
    for (const key of ["registration", "admission", "announcement", "export"]) {
      const request = requests[key], fresh = await observe();
      check(`${key}_before_state_unchanged`, before.state, fresh.state);
      if (key === "export" && fresh.exportDecision.action === "omitted-expired") {
        report.exportDecision = fresh.exportDecision;
        check("expired_export_never_recreated", true, Date.parse(report.startedAt) >= Date.parse(original.receipt.pilotExport.expiresAt));
        continue;
      }
      const data = key === "announcement" ? fresh.announcementData : request.data;
      if (key === "export" && Date.parse(fresh.exportDecision.expiresAt) - now() < 300000) throw Error("Export replay is too close to expiry for the bounded request; wait for verified expiry instead");
      check(`${key}_original_request_digest`, request.requestSha256, c.digest(data));
      const entry = {key, role: request.role, name: request.name, requestSha256: request.requestSha256}; report.requests.push(entry);
      await connect(request.role, false);
      try { entry.offline = await invoke(request.role, request.name, data); }
      finally { await connect(request.role, true); }
      check(`${key}_actual_offline_page_request_failed`, true, validTransport(entry.offline, request, true));
      const immediate = await observe();
      check(`${key}_offline_has_no_effects`, before.state, immediate.state);
      if (key === "export" && immediate.exportDecision.action !== "replay") throw Error("Export expired during disconnected probe; no replay was issued");
      if (key === "export" && Date.parse(immediate.exportDecision.expiresAt) - now() < 300000) throw Error("Export expiry is inside the replay safety margin; no replay was issued");
      entry.online = await invoke(request.role, request.name, data);
      check(`${key}_actual_reconnected_page_response`, true, validTransport(entry.online, request, false));
      check(`${key}_server_outcome`, key === "admission" ? "FAILED_PRECONDITION" : "OK", entry.online.status);
      if (key === "registration") check("registration_receipt_unchanged", original.pilot.registrationIds[0], entry.online.result.registrationId);
      if (key === "announcement") check("announcement_receipt_unchanged", original.pilot.announcementId, entry.online.result.announcementId);
      if (key === "export") check("export_receipt_unchanged", original.pilot.exportJobId, entry.online.result.jobId);
      const after = await observe();
      check(`${key}_no_new_admission_job_attempt_or_capture`, before.state, after.state);
    }
    const final = await observe();
    report.snapshots.push({phase: "after", ...final.state, observedAt: final.observedAt});
    report.completedAt = new Date(now()).toISOString();
    return report;
  } catch (error) {error.replayReport = report; throw error;}
}

function verifiedReplay(candidate, context) {
  for (const {report, outputDir} of context.priorEvidence || []) {
    if (report.gate !== GATE || report.producer !== "tools/web_release_producers/browser.js") continue;
    c.validateEvidence(report, candidate, outputDir);
    if (report.observedStateSha256 !== context.deployment.stateSha256 || !report.rawFiles[RAW]) throw Error("Replay deployment or raw receipt differs");
    const raw = JSON.parse(fs.readFileSync(path.join(outputDir, RAW), "utf8"));
    const original = originalPilot(candidate, {...context, priorEvidence: context.priorEvidence.filter((entry) =>
      entry.report.gate !== "browser-auth-guest-organizer" || c.digest(entry.report) === raw.originalPilot?.reportSha256)});
    if (!equal(raw.identity, original.receipt.identity) || !equal(raw.originalPilot, original.provenance) ||
        !Number.isFinite(Date.parse(raw.effectiveClosesAt)) || Date.parse(raw.effectiveClosesAt) < Date.parse(context.fixture.eventClosesAt) ||
        Date.parse(raw.startedAt) <= Date.parse(raw.effectiveClosesAt) || Date.parse(raw.startedAt) < Date.parse(report.startedAt) ||
        !Number.isFinite(Date.parse(raw.completedAt)) || Date.parse(raw.completedAt) > Date.parse(report.finishedAt) ||
        Date.parse(raw.completedAt) < Date.parse(raw.startedAt)) throw Error("Replay is not bound to the actual post-close pilot");
    c.validateAssertions({assertions: raw.assertions, rawFiles: report.rawFiles, blockers: []});
    const required = ["registration", "admission", "announcement", ...(raw.exportDecision?.action === "replay" ? ["export"] : [])];
    if (!["replay", "omitted-expired"].includes(raw.exportDecision?.action) ||
        raw.exportDecision.originalJobId !== original.pilot.exportJobId || raw.exportDecision.originalGeneration !== original.receipt.pilotExport.generation ||
        raw.exportDecision.expiresAt !== original.receipt.pilotExport.expiresAt ||
        (raw.exportDecision.action === "omitted-expired" && Date.parse(raw.startedAt) < Date.parse(raw.exportDecision.expiresAt))) throw Error("Export omission lacks original expiry proof");
    if (!equal(raw.requests?.map((row) => row.key).sort(), required.sort()) || raw.snapshots?.length !== 2 ||
        c.digest({...raw.snapshots[0], phase: null, observedAt: null}) !== c.digest({...raw.snapshots[1], phase: null, observedAt: null})) throw Error("Replay requests or before/after state proof is incomplete");
    for (const row of raw.requests) {
      const request = original.receipt.replayRequests[row.key];
      if (row.requestSha256 !== request.requestSha256 || row.name !== request.name || row.role !== request.role ||
          [row.offline, row.online].some((attempt) => attempt?.transport !== "page-fetch" || attempt.actorUid !== context.fixture[row.role].uid ||
            !Number.isFinite(Date.parse(attempt.startedAt)) || !Number.isFinite(Date.parse(attempt.finishedAt)) ||
            Date.parse(attempt.finishedAt) < Date.parse(attempt.startedAt) || Date.parse(attempt.startedAt) < Date.parse(raw.startedAt) || Date.parse(attempt.finishedAt) > Date.parse(raw.completedAt)) ||
          row.offline.online !== false || row.offline.status !== "NETWORK_ERROR" || row.offline.httpStatus !== null ||
          row.online.online !== true || !Number.isInteger(row.online.httpStatus) || row.online.httpStatus < 200 || row.online.httpStatus >= 600 ||
          Date.parse(row.online.startedAt) < Date.parse(row.offline.finishedAt) ||
          row.online.status !== (row.key === "admission" ? "FAILED_PRECONDITION" : "OK")) throw Error("Actual authenticated browser reconnect receipts are missing");
      if (row.key === "registration" && row.online.result?.registrationId !== original.pilot.registrationIds[0] ||
          row.key === "announcement" && row.online.result?.announcementId !== original.pilot.announcementId ||
          row.key === "export" && row.online.result?.jobId !== original.pilot.exportJobId) throw Error("Post-close replay returned a different original receipt");
    }
    return {receipt: raw, provenance: {workflowRunId: report.workflowRunId, reportSha256: c.digest(report), receiptSha256: report.rawFiles[RAW], originalPilot: original.provenance}};
  }
  throw Error("A successful immutable authenticated post-close browser replay is required; passive observations are insufficient");
}

module.exports = {GATE, RAW, validateRequests, originalPilot, createReplayObserver, pageCallable, runReplay, verifiedReplay};
