"use strict";

// Deployed evidence only. The one mutation is an expiring staging preview
// channel used to rehearse rollback; neither live Hosting channel is changed.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const {createRequire} = require("node:module");
const fromFunctions = createRequire(path.resolve(__dirname, "../../functions/package.json"));
const {captureState, verifyState, googleClient} = require("../web_release_state");
const {sha256, digest, relativeFile, validateEvidence} = require("../web_release_contract");
const {verifyRehearsal} = require("../rehearse_web_backend");
const {bindingId, validScope} = require("../../functions/communications/qualification-isolation");
const {schedule} = require("../../functions/events/schedule");
const assertion = (id, expected, actual) => ({id, expected, actual});
const iso = (value) => value?.toDate?.().toISOString() || (value instanceof Date ? value.toISOString() : null);
const terminal = new Set(["complete", "accepted", "suppressed", "cancelled", "expired", "in_app_only", "captured", "sent"]);
function validateContext(candidate, context, environment = process.env) {
  const emulatorVariables = ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST", "STORAGE_EMULATOR_HOST", "FIREBASE_DATABASE_EMULATOR_HOST"];
  if (candidate.environment !== "staging" || candidate.projectId !== "attendus-staging" || context.projectId !== candidate.projectId ||
      context.baseUrl !== "https://attendus-staging.web.app" || emulatorVariables.some((name) => environment[name])) throw Error("Operations qualification requires the deployed isolated staging candidate");
  const fixture = context.fixture;
  if (!fixture || !/^[A-Za-z0-9_-]{8,100}$/.test(fixture.runId || "") || !fixture.owner?.uid || !fixture.event?.id ||
      !Array.isArray(fixture.ownedFixtureIds) || !Number.isFinite(Date.parse(fixture.eventClosesAt))) throw Error("Bound fixture owner, event and close time are required");
  return fixture;
}
async function readBytes(origin, name) {
  relativeFile(name);
  const response = await fetch(`${origin}/${name}`, {signal: AbortSignal.timeout(60000), cache: "no-store", redirect: "error"});
  if (response.status !== 200) throw Error(`Hosted artifact request failed (${response.status}) for ${name}`);
  return Buffer.from(await response.arrayBuffer());
}
async function previewRelease(client, candidate, channelId, version) {
  if (!/^qa-rollback-[a-f0-9]{16}$/.test(channelId) || !version.startsWith("sites/attendus-staging/versions/") || !/^sites\/attendus-staging\/versions\/[A-Za-z0-9_-]+$/.test(version)) throw Error("Rollback rehearsal target must be a dedicated staging preview");
  const base = "https://firebasehosting.googleapis.com/v1beta1/projects/attendus-staging/sites/attendus-staging/channels";
  let channel;
  try { channel = (await client.request({url: `${base}/${channelId}`})).data; }
  catch (error) {
    if (error.response?.status !== 404) throw error;
    channel = (await client.request({method: "POST", url: base, params: {channelId}, data: {ttl: "172800s"}})).data;
  }
  if (!Number.isFinite(Date.parse(channel.expireTime)) || Date.parse(channel.expireTime) < Date.now() + 3600000 || Date.parse(channel.expireTime) > Date.now() + 172860000) {
    channel = (await client.request({method: "PATCH", url: `${base}/${channelId}`, params: {updateMask: "ttl"}, data: {ttl: "172800s"}})).data;
  }
  if (!Number.isFinite(Date.parse(channel.expireTime)) || Date.parse(channel.expireTime) <= Date.now() || Date.parse(channel.expireTime) > Date.now() + 172860000) throw Error("Rollback preview expiry was not confirmed");
  const url = new URL(channel.url);
  if (url.protocol !== "https:" || !url.hostname.startsWith(`attendus-staging--${channelId}-`) || !url.hostname.endsWith(".web.app")) throw Error("Unexpected rollback preview origin");
  const release = (await client.request({method: "POST", url: `${base}/${channelId}/releases`, params: {versionName: version}, data: {message: `Owned web qualification ${candidate.sourceSha}`}})).data;
  const verified = (await client.request({url: `${base}/${channelId}`})).data;
  if (verified.release?.version?.name !== version || release.version?.name !== version) throw Error("Rollback preview did not select the expected immutable version");
  return {channelId, origin: url.origin, release: release.name, version, expiresAt: channel.expireTime, verifiedAt: new Date().toISOString()};
}
function inspectJobs(rows, observedAt, eventClosesAt) {
  const now = Date.parse(observedAt), closed = now >= Date.parse(eventClosesAt) + 15 * 60000;
  return [
    assertion("no_failed_or_unknown_jobs", [], rows.filter((row) => ["failed", "dead_letter", "delivery_unknown", "unknown", "needs_review"].includes(row.status)).map((row) => row.id)),
    assertion("no_expired_live_leases", [], rows.filter((row) => row.leaseUntil && Date.parse(row.leaseUntil) < now && !terminal.has(row.status)).map((row) => row.id)),
    assertion("closed_event_has_no_pending_jobs", [], closed ? rows.filter((row) => !terminal.has(row.status)).map((row) => row.id) : []),
  ];
}
function runtimeFlags(publicWeb, attendance, fixture) {
  const flags = {publicPagesEnabled: publicWeb.publicPagesEnabled, inlineRegistrationEnabled: publicWeb.inlineRegistrationEnabled,
    accountlessRegistrationEnabled: publicWeb.accountlessRegistrationEnabled, paidTicketCheckoutEnabled: publicWeb.paidTicketCheckoutEnabled,
    appCheckSiteKeyMatches: publicWeb.appCheckSiteKey === fixture.firebase.appCheckSiteKey,
    appleDeliveryEnabled: attendance.appleDelivery?.enabled, googleDeliveryEnabled: attendance.googleDelivery?.enabled,
    corePassesEnabled: attendance.corePasses?.enabled, smartArrivalEnabled: attendance.smartArrival?.enabled};
  const expected = {publicPagesEnabled: true, inlineRegistrationEnabled: true, accountlessRegistrationEnabled: true,
    paidTicketCheckoutEnabled: false, appCheckSiteKeyMatches: true, appleDeliveryEnabled: false, googleDeliveryEnabled: false,
    corePassesEnabled: true, smartArrivalEnabled: true};
  if (digest(flags) !== digest(expected)) throw Error("Staging public or disabled-provider flags changed");
  for (const feature of ["corePasses", "smartArrival"]) {
    const value = attendance[feature];
    if (value.allEvents === true || !Array.isArray(value.eventIds) || !value.eventIds.includes(fixture.event.id) ||
        value.eventIds.some((id) => !fixture.ownedFixtureIds.includes(id)) || !Array.isArray(value.userIds) || !value.userIds.length ||
        value.userIds.some((id) => !fixture.ownedFixtureIds.includes(id))) throw Error("Attendance rollout extends outside owned fixtures");
  }
  return {...flags, attendanceScopeSha256: digest({corePasses: attendance.corePasses, smartArrival: attendance.smartArrival})};
}
function pilotReceipt(candidate, context) {
  const fixture = context.fixture;
  const reports = (context.priorEvidence || []).filter(({report}) => report.producer === "tools/web_release_producers/browser.js" &&
    report.gate === "browser-auth-guest-organizer").sort((a, b) => Date.parse(b.report.finishedAt) - Date.parse(a.report.finishedAt));
  for (const {report, outputDir} of reports) {
    validateEvidence(report, candidate, outputDir);
    if (report.observedStateSha256 !== context.deployment.stateSha256) throw Error("Browser pilot deployment differs");
    const receiptPaths = Object.keys(report.rawFiles).filter((name) => /(^|\/)pilot-receipts\.json$/.test(name));
    if (receiptPaths.length !== 1) throw Error("Browser report must contain one actual pilot receipt");
    const receipt = JSON.parse(fs.readFileSync(path.join(outputDir, relativeFile(receiptPaths[0])), "utf8"));
    const identity = {schemaVersion: 1, projectId: candidate.projectId, sourceSha: candidate.sourceSha,
      candidateRunId: candidate.candidateRunId, runId: fixture.runId, eventId: fixture.event.id};
    if (receipt.schemaVersion !== 1 || digest(receipt.identity) !== digest(identity) ||
        !Number.isFinite(Date.parse(receipt.completedAt)) || Date.parse(receipt.completedAt) < Date.parse(receipt.startedAt) ||
        Date.parse(receipt.startedAt) < Date.parse(report.startedAt) || Date.parse(receipt.completedAt) > Date.parse(report.finishedAt) ||
        !Array.isArray(receipt.assertions) || !receipt.assertions.length || receipt.assertions.some((item) => digest(item.expected) !== digest(item.actual))) throw Error("Browser pilot receipt identity, time or assertions differ");
    const pilot = receipt.pilot, safeId = (id) => typeof id === "string" && /^[A-Za-z0-9_.:-]{1,500}$/.test(id);
    if (!pilot || ![pilot.registrationIds, pilot.attendanceIds].every((ids) => Array.isArray(ids) && ids.length > 0 && ids.every(safeId) && new Set(ids).size === ids.length) ||
        !safeId(pilot.exportJobId) || !safeId(pilot.announcementId)) throw Error("Actual authenticated pilot receipt IDs are incomplete");
    return {pilot, receipt, provenance: {workflowRunId: report.workflowRunId, reportSha256: digest(report),
      receiptPath: receiptPaths[0], receiptSha256: report.rawFiles[receiptPaths[0]]}};
  }
  throw Error("A successful immutable browser evidence run containing actual pilot receipts is required");
}
async function inspectPilotExport({pilot, receipt, fixture, current, readMetadata, now = Date.now()}) {
  const original = receipt.pilotExport;
  const expires = Date.parse(original?.expiresAt);
  const completed = Date.parse(receipt.completedAt);
  if (!original || original.jobId !== pilot.exportJobId || original.status !== "complete" ||
      !Number.isInteger(original.rowCount) || original.rowCount < pilot.registrationIds.length ||
      typeof original.generation !== "string" || !original.generation ||
      !/^[a-f0-9]{64}$/.test(original.jobId) ||
      typeof original.objectPath !== "string" || !original.objectPath.startsWith(`private-event-exports/${original.jobId}/`) ||
      !/^private-event-exports\/[a-f0-9]{64}\/[A-Za-z0-9_-]+\.csv$/.test(original.objectPath) ||
      !Number.isFinite(expires) || !Number.isFinite(completed) || completed >= expires || !Number.isFinite(now)) {
    throw Error("An immutable pre-expiry completed export receipt is required");
  }
  if (current && (current.id !== original.jobId || current.eventId !== fixture.event.id || current.actorUid !== fixture.owner.uid ||
      current.status !== "complete" || current.generation !== original.generation || current.rowCount !== original.rowCount ||
      current.expiresAt !== original.expiresAt || current.objectPath !== original.objectPath)) throw Error("Original pilot export was changed or recreated");
  if (now < expires && !current) throw Error("Original pilot export disappeared before expiry");
  let metadata = null;
  try { metadata = await readMetadata(original.objectPath); }
  catch (error) { if (Number(error.code || error.response?.status) !== 404) throw error; }
  if (now < expires) {
    if (!metadata || metadata.name !== original.objectPath || !/^\d+$/.test(String(metadata.generation || "")) || !(Number(metadata.size) > 0)) {
      throw Error("Completed pilot export object is unavailable before expiry");
    }
  } else if (metadata) throw Error("Expired pilot export object has not been removed");
  return {original, observedAt: new Date(now).toISOString(), jobPresent: !!current, objectPresent: !!metadata,
    objectGeneration: metadata?.generation || null, disposition: now < expires ? "complete_unexpired" : "completed_then_expired_object_removed"};
}
async function produce({candidate, context, outputDir}) {
  const fixture = validateContext(candidate, context), client = await googleClient();
  const {initializeApp, applicationDefault, deleteApp} = fromFunctions("firebase-admin/app");
  const {getFirestore} = fromFunctions("firebase-admin/firestore");
  const {getStorage} = fromFunctions("firebase-admin/storage");
  const app = initializeApp({projectId: context.projectId, credential: applicationDefault()}, `web-operations-${crypto.randomUUID()}`);
  const db = getFirestore(app), gates = {};
  const identity = {sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId, projectId: candidate.projectId, runId: fixture.runId};
  const write = (name, data) => { fs.mkdirSync(path.dirname(path.join(outputDir, name)), {recursive: true}); fs.writeFileSync(path.join(outputDir, name), JSON.stringify(data, null, 2) + "\n"); return name; };
  async function gate(name, work) {
    if (context.requestedGates && !context.requestedGates.includes(name)) return;
    try { gates[name] = await work(); }
    catch (error) { gates[name] = {assertions: [assertion("live_check_completed", true, false)], blockers: [String(error.message).replace(/https?:\/\/\S+/g, "[URL]").slice(0, 300)],
      rawPaths: [write(`${name}/failure.json`, {...identity, observedAt: new Date().toISOString(), code: String(error.code || "qualification_failed")})]}; }
  }
  async function docs(collection, eventId) {
    const rows = await db.collection(collection).where("eventId", "==", eventId).limit(5001).get();
    if (rows.size > 5000) throw Error("Owned pilot query exceeded explicit fixture budget");
    return rows.docs;
  }
  try {
    const [scope, binding, event] = await Promise.all([db.doc(`QualificationScopes/${fixture.runId}`).get(),
      db.doc(`QualificationBindings/${bindingId("event", fixture.event.id)}`).get(), db.doc(`Events/${fixture.event.id}`).get()]);
    if (!validScope(scope.data(), fixture.runId, context.projectId, Date.now()) || binding.get("state") !== "bound" ||
        binding.get("runId") !== fixture.runId || binding.get("projectId") !== context.projectId || !scope.get("eventIds").includes(fixture.event.id) ||
        event.get("customerUid") !== fixture.owner.uid || !fixture.ownedFixtureIds.some((id) => [fixture.event.id, `Events/${fixture.event.id}`].includes(id))) throw Error("Live pilot ownership or isolation binding differs");
    const close = schedule(event.data()).end;
    if (!close || close.toISOString() !== fixture.eventClosesAt) throw Error("Live pilot event close differs from the approved fixture");
    const [publicSettings, attendanceSettings] = await Promise.all([db.doc("AppConfig/publicWeb").get(), db.doc("AppConfig/attendance").get()]);
    const flags = runtimeFlags(publicSettings.data() || {}, attendanceSettings.data() || {}, fixture);
    const capture = verifyState(candidate, await captureState(candidate.projectId, client), JSON.parse(fs.readFileSync(path.resolve(__dirname, "../../firestore.indexes.json"))));
    await gate("rules-storage-indexes-TTL", async () => ({assertions: [assertion("deployed_state_matches_frozen_receipt", context.deployment.stateSha256, capture.stateSha256),
      assertion("firestore_and_storage_rule_releases_present", true, capture.state.rules.some((rule) => rule.release.endsWith("/cloud.firestore")) && capture.state.rules.some((rule) => rule.release.includes("/firebase.storage/")))],
    blockers: [], rawPaths: [write("rules-storage-indexes-TTL/state.json", {...identity, flags, ...capture})]}));
    const [registrations, attendance, exports, announcements] = await Promise.all(["RegisterAttendance", "Attendance", "EventExportJobs", "EventAnnouncements"].map((name) => docs(name, fixture.event.id)));
    const jobs = [...exports, ...announcements, ...await docs("OutboundMessages", fixture.event.id), ...await docs("scheduledNotifications", fixture.event.id)]
        .map((row) => ({id: row.ref.path, status: row.get("deliveryState") || row.get("status") || null, attempts: row.get("attemptCount") ?? row.get("attempts") ?? 0, leaseUntil: iso(row.get("leaseUntil"))}));
    await gate("owned-staging-pilot", async () => {
      const {pilot, receipt, provenance} = pilotReceipt(candidate, context);
      if (fixture.firebase?.storageBucket !== "attendus-staging.firebasestorage.app") throw Error("Pilot export bucket is not isolated staging");
      const exportRows = exports.map((row) => ({id: row.id, status: row.get("status"), eventId: row.get("eventId"), actorUid: row.get("actorUid"),
        rowCount: row.get("rowCount"), generation: row.get("generation") || null, expiresAt: iso(row.get("expiresAt")), objectPath: row.get("path") || null}));
      const exportLifecycle = await inspectPilotExport({pilot, receipt, fixture, current: exportRows.find((row) => row.id === pilot.exportJobId),
        readMetadata: async (objectPath) => (await getStorage(app).bucket(fixture.firebase.storageBucket).file(objectPath).getMetadata())[0]});
      const evidence = {...identity, provenance, eventId: fixture.event.id, eventRevision: event.get("eventRevision"), closesAt: close.toISOString(),
        registrations: registrations.map((row) => ({id: row.id, status: row.get("status"), uid: row.get("customerUid") || null})),
        attendance: attendance.map((row) => ({id: row.id, registrationId: row.get("registrationId") || null, checkedInAt: iso(row.get("checkInTime") || row.get("checkedInAt") || row.get("createdAt"))})),
        exports: exportRows, exportLifecycle,
        announcements: announcements.map((row) => ({id: row.id, status: row.get("status"), count: row.get("count") || 0}))};
      return {blockers: [], rawPaths: [write("owned-staging-pilot/live.json", evidence)], assertions: [
        assertion("registered_admissions_exist", pilot.registrationIds.slice().sort(), registrations.filter((row) => pilot.registrationIds.includes(row.id)).map((row) => row.id).sort()),
        assertion("actual_attendance_exists", pilot.attendanceIds.slice().sort(), attendance.filter((row) => pilot.attendanceIds.includes(row.id)).map((row) => row.id).sort()),
        assertion("roster_export_completion_and_retention_verified", true, ["complete_unexpired", "completed_then_expired_object_removed"].includes(exportLifecycle.disposition)),
        assertion("announcement_completed", true, evidence.announcements.some((row) => row.id === pilot.announcementId && row.status === "complete" && row.count > 0)),
        assertion("attendance_links_resolve", true, evidence.attendance.filter((row) => pilot.attendanceIds.includes(row.id)).every((row) => pilot.registrationIds.includes(row.registrationId))),
      ]};
    });
    await gate("observation", async () => {
      const observedAt = new Date().toISOString(); const files = {};
      for (const name of ["index.html", "flutter_bootstrap.js", "firebase-messaging-sw.js", "release-manifest.json"]) {
        if (candidate.webFiles[name]) files[name] = sha256(await readBytes(context.baseUrl, name));
      }
      const captures = await db.collection("QualificationCaptures").where("runId", "==", fixture.runId).count().get();
      const sample = {...identity, observedAt, eventClosesAt: fixture.eventClosesAt, sourceSha: candidate.sourceSha, stateSha256: capture.stateSha256,
        eventId: fixture.event.id, eventRevision: event.get("eventRevision") || 0, registrations: registrations.length, attendance: attendance.length,
        files, jobs, flags, captures: captures.data().count};
      return {blockers: [], assertions: [assertion("release_health_hashes", Object.fromEntries(Object.keys(files).map((name) => [name, candidate.webFiles[name]])), files),
        assertion("deployment_did_not_drift", context.deployment.stateSha256, capture.stateSha256), ...inspectJobs(jobs, observedAt, fixture.eventClosesAt)],
      rawPaths: [write("observation/live.json", sample)], window: {eventClosesAt: fixture.eventClosesAt, observedAt}};
    });
    await gate("rollback-rehearsal", async () => {
      const backend = await verifyRehearsal({candidate, receipt: context.backendRehearsal,
        manifest: JSON.parse(fs.readFileSync(path.resolve(__dirname, "../../config/web_backend_predecessor_archives.json"), "utf8")), client});
      const prior = candidate.predecessor.staging.hostingVersion, current = context.deployment.state.hostingVersion;
      if (prior === current) throw Error("Rollback requires distinct prior and candidate Hosting versions");
      const channelId = `qa-rollback-${digest({runId: fixture.runId, candidate: candidate.sourceSha}).slice(0, 16)}`;
      const previous = await previewRelease(client, candidate, channelId, prior);
      const previousIndex = sha256(await readBytes(previous.origin, "index.html"));
      const priorHashes = context.artifacts?.previousStagingFiles;
      if (!priorHashes?.["index.html"] || context.artifacts.previousStagingHostingVersion !== prior) throw Error("Captured predecessor artifact hashes are required");
      const forward = await previewRelease(client, candidate, channelId, current);
      const currentIndex = sha256(await readBytes(forward.origin, "index.html"));
      const currentMain = `releases/${candidate.releaseId}/main.dart.js`;
      const mainHash = sha256(await readBytes(forward.origin, currentMain));
      const unchanged = await captureState(candidate.projectId, client);
      return {blockers: [], rawPaths: [write("rollback-rehearsal/backend-operations.json", {...identity, ...backend}),
        write("rollback-rehearsal/preview.json", {...identity, scope: "Hosting preview rollback and four representative backend source restorations", previous, previousIndex, forward, currentIndex, currentMain, mainHash, liveStateSha256: unchanged.stateSha256})],
        assertions: [assertion("prior_artifact_restored", priorHashes["index.html"], previousIndex), assertion("candidate_index_restored", candidate.webFiles["index.html"], currentIndex),
          assertion("candidate_runtime_restored", candidate.webFiles[currentMain], mainHash), assertion("live_channel_unchanged", capture.stateSha256, unchanged.stateSha256)]};
    });
    return {gates};
  } finally { await db.terminate(); await deleteApp(app); }
}
module.exports = {produce, validateContext, inspectJobs, previewRelease, pilotReceipt, runtimeFlags, inspectPilotExport};
