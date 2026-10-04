"use strict";

// Executable staging qualification. Only the dedicated, bound analytics canary
// is mutated. Delivery, recovery and observation checks read current API data.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const {createRequire} = require("node:module");
const fromFunctions = createRequire(path.resolve(__dirname, "../../functions/package.json"));
const {bindingId, validScope} = require("../../functions/communications/qualification-isolation");
const {schedule} = require("../../functions/events/schedule");
const {verifyRecovery} = require("../../functions/tools/complete-launch-migration");
const {googleClient} = require("../web_release_state");
const {captureRecoveryTarget} = require("../capture_recovery_target");
const {inventoryRestoredContent, compareRecoveryContent} = require("../recovery_content");
const {readAuthoritativeReadiness} = require("../authoritative_data_readiness");
const {runtimeFlags} = require("./operations");
const hash = (value) => crypto.createHash("sha256").update(value).digest("hex");
const assertion = (id, expected, actual) => ({id, expected, actual});
const safeId = (value) => typeof value === "string" && /^[A-Za-z0-9_.:-]{1,180}$/.test(value);
const iso = (value) => value?.toDate?.().toISOString() || (value instanceof Date ? value.toISOString() : null);
const terminal = new Set(["complete", "accepted", "suppressed", "failed", "dead_letter", "cancelled", "expired", "in_app_only", "captured", "sent"]);
const unknown = new Set(["delivery_unknown", "unknown", "needs_review"]);
const requiredCaptureKinds = ["email", "legacy", "message", "reminder", "announcement", "discovery", "pending", "admin"];
function summarizeCaptures(documents) {
  return documents.map((document) => {
    const value = document.data();
    const identity = hash(JSON.stringify([value.runId, value.recipientUid || value.recipientEmailHash, value.sourceKey]));
    return {id: document.id, runId: value.runId, sourceKey: value.sourceKey, recipientUid: value.recipientUid,
      recipientEmailHash: value.recipientEmailHash, eventIds: value.eventIds, provider: value.provider,
      fingerprint: value.fingerprint, capturedAt: iso(value.capturedAt), expiresAt: iso(value.expiresAt),
      contentMatches: hash(JSON.stringify(value.payload)) === value.fingerprint, identityMatches: document.id === identity};
  }).sort((a, b) => a.id.localeCompare(b.id));
}
function observationAssertions(current, previous = []) {
  const afterClose = Date.parse(current.observedAt) >= Date.parse(current.eventClosesAt) + 15 * 60000;
  const priorClosed = previous.filter((sample) => sample.eventClosesAt === current.eventClosesAt && Date.parse(sample.observedAt) >= Date.parse(current.eventClosesAt) + 15 * 60000);
  const priorJobs = new Map(priorClosed.flatMap((sample) => sample.jobs).filter((job) => terminal.has(job.status)).map((job) => [job.path, job]));
  const currentJobs = new Map(current.jobs.map((job) => [job.path, job]));
  const oldCaptures = new Map(previous.flatMap((sample) => sample.captures).map((capture) => [capture.id, capture.fingerprint]));
  return [
    assertion("no_failed_or_dead_letter_jobs", 0, current.jobs.filter((job) => ["failed", "dead_letter"].includes(job.status)).length),
    assertion("no_provider_unknown_outcomes", 0, current.jobs.filter((job) => unknown.has(job.status)).length),
    assertion("no_expired_active_job_leases", 0, current.jobs.filter((job) => job.leaseUntil && Date.parse(job.leaseUntil) < Date.parse(current.observedAt) && !terminal.has(job.status)).length),
    assertion("post_close_jobs_terminal", true, !afterClose || current.jobs.every((job) => terminal.has(job.status))),
    assertion("completed_job_replay_does_not_increment_attempts", true, [...priorJobs].every(([key, job]) => !currentJobs.has(key) || currentJobs.get(key).attempts === job.attempts && terminal.has(currentJobs.get(key).status))),
    assertion("capture_replays_preserve_content", true, current.captures.every((capture) => !oldCaptures.has(capture.id) || oldCaptures.get(capture.id) === capture.fingerprint)),
    assertion("post_close_event_revision_stable", true, priorClosed.every((sample) => sample.eventRevision === current.eventRevision)),
    assertion("post_close_roster_revision_stable", true, priorClosed.every((sample) => sample.rosterRevision === current.rosterRevision)),
    assertion("post_close_admission_counts_stable", true, priorClosed.every((sample) => JSON.stringify(sample.sourceCounts) === JSON.stringify(current.sourceCounts))),
    assertion("capture_identity_and_content_valid", true, current.captures.every((capture) => capture.identityMatches && capture.contentMatches)),
  ];
}
async function bounded(query, limit = 10000) {
  const rows = await query.limit(limit + 1).get();
  if (rows.size > limit) throw Error("Fixture evidence exceeds the explicit bounded query budget");
  return rows.docs;
}
async function waitFor(read, accepts, timeoutMs = 60000) {
  const deadline = Date.now() + timeoutMs;
  do {
    const value = await read();
    if (accepts(value)) return value;
    await new Promise((resolve) => setTimeout(resolve, 1000));
  } while (Date.now() < deadline);
  throw Error("Deployed canary did not converge within its bounded wait");
}
async function produce({candidate, context, outputDir}) {
  if (context.projectId !== "attendus-staging" || candidate.projectId !== context.projectId || process.env.FIRESTORE_EMULATOR_HOST) throw Error("Backend qualification requires deployed staging with no emulator routing");
  const fixture = context.fixture || {}, runId = fixture.runId;
  const eventId = fixture.event?.id, ownerUid = fixture.owner?.uid;
  if (!safeId(eventId) || !safeId(ownerUid) || !/^[A-Za-z0-9_-]{8,100}$/.test(runId || "")) throw Error("Explicit owned fixture identity is required");
  const {initializeApp, applicationDefault, deleteApp} = fromFunctions("firebase-admin/app");
  const {getFirestore} = fromFunctions("firebase-admin/firestore");
  const {getStorage} = fromFunctions("firebase-admin/storage");
  const app = initializeApp({projectId: context.projectId, credential: applicationDefault()}, `web-qualification-${crypto.randomUUID()}`);
  const db = getFirestore(app), client = await googleClient(), gates = {};
  const requested = context.requestedGates ? new Set(context.requestedGates) : null;
  const write = (name, data) => { const file = path.join(outputDir, name); fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n"); return name; };
  const identity = {schemaVersion: 1, projectId: context.projectId, runId, sourceSha: context.sourceSha, candidateRunId: context.candidateRunId,
    deploymentSha256: context.deploymentSha256, webSha256: context.webSha256, configSha256: context.configSha256};
  async function guardEvent(id, tx = null) {
    if (!safeId(id) || !Array.isArray(fixture.ownedFixtureIds) || !fixture.ownedFixtureIds.some((value) => value === id || value === `Events/${id}`)) throw Error("Event is outside the explicit owned fixture inventory");
    const read = (ref) => tx ? tx.get(ref) : ref.get();
    const [event, scope, binding, deleting] = await Promise.all([read(db.doc(`Events/${id}`)), read(db.doc(`QualificationScopes/${runId}`)), read(db.doc(`QualificationBindings/${bindingId("event", id)}`)), read(db.doc(`account_deletion_jobs/${ownerUid}`))]);
    if (!event.exists || event.get("customerUid") !== ownerUid || !validScope(scope.data(), runId, context.projectId, Date.now()) || !scope.get("eventIds").includes(id) || !scope.get("actorUids").includes(ownerUid) ||
        deleting.exists || binding.get("schemaVersion") !== 1 || binding.get("projectId") !== context.projectId || binding.get("runId") !== runId || binding.get("state") !== "bound") throw Error("Current fixture ownership or capture binding does not match");
    return {event, scope};
  }
  async function gate(name, work) {
    if (requested && !requested.has(name)) return;
    try { gates[name] = await work(); }
    catch (error) {
      const raw = write(`${name}/blocked.json`, {...identity, observedAt: new Date().toISOString(), error: String(error.code || "qualification_check_failed"), detail: String(error.message).slice(0, 350)});
      gates[name] = {assertions: [assertion("current_live_evidence_available", true, false)], rawPaths: [raw], blockers: ["Current qualification checks could not complete; inspect the retained failure evidence."]};
    }
  }
  try {
    const {event, scope} = await guardEvent(eventId);
    const captures = summarizeCaptures(await bounded(db.collection("QualificationCaptures").where("runId", "==", runId)));
    const jobs = [];
    for (const name of ["EventAnnouncements", "EventExportJobs", "OutboundMessages", "scheduledNotifications"]) {
      for (const document of await bounded(db.collection(name).where("eventId", "==", eventId))) {
        const data = document.data(); jobs.push({path: document.ref.path, status: data.deliveryState || data.status || null,
          attempts: data.attemptCount ?? data.attempts ?? 0, leaseUntil: iso(data.leaseUntil), provider: data.provider || null,
          sourceRevision: data.eventSnapshot?.eventRevision ?? data.payload?.eventRevision ?? null});
      }
    }
    jobs.sort((a, b) => a.path.localeCompare(b.path));
    const roster = await db.doc(`EventRosters/${eventId}`).get();
    const sourceCounts = {};
    for (const name of ["RegisterAttendance", "Tickets", "Attendance", "HistoricalAttendance"]) {
      sourceCounts[name] = (await db.collection(name).where("eventId", "==", eventId).count().get()).data().count;
    }
    const snapshotAt = new Date().toISOString();
    await gate("notification-delivery-isolation", async () => {
      const inboxes = [];
      for (const uid of scope.get("recipientUids")) {
        const [userInbox, legacyInbox] = await Promise.all([db.collection(`users/${uid}/notifications`).count().get(), db.collection("notifications").where("userId", "==", uid).count().get()]);
        inboxes.push({uid, userInbox: userInbox.data().count, legacyInbox: legacyInbox.data().count});
      }
      const kinds = [...new Set(captures.map((capture) => capture.sourceKey.split(":")[0]))].sort();
      const raw = write("notification-delivery-isolation/live.json", {...identity, observedAt: snapshotAt, captures, inboxes, jobs, requiredCaptureKinds});
      return {rawPaths: [raw], blockers: [], assertions: [
        assertion("all_active_delivery_families_captured", requiredCaptureKinds.slice().sort(), requiredCaptureKinds.filter((kind) => kinds.includes(kind)).sort()),
        assertion("fixture_inboxes_empty", 0, inboxes.reduce((sum, row) => sum + row.userInbox + row.legacyInbox, 0)),
        assertion("no_real_email_provider_handoff", 0, jobs.filter((job) => job.provider && job.provider !== "qualification_capture").length),
        assertion("no_provider_unknown_results", 0, jobs.filter((job) => unknown.has(job.status)).length),
        assertion("all_captures_bound_and_immutable", true, captures.length > 0 && captures.every((row) => row.runId === runId && row.provider === "qualification_capture" && row.contentMatches && row.identityMatches)),
      ]};
    });
    await gate("backend-trigger-canaries", async () => {
      const id = fixture.canaryEventId;
      if (id === eventId) throw Error("The analytics canary must be separate from the attendee fixture");
      await guardEvent(id);
      const configs = [];
      for (const [name, type] of [["triggerAIInsights", "google.cloud.firestore.document.v1.updated"], ["triggerAIInsightsV2", "google.cloud.firestore.document.v1.written"]]) {
        const config = (await client.request({url: `https://cloudfunctions.googleapis.com/v2/projects/${context.projectId}/locations/us-central1/functions/${name}`})).data;
        configs.push({name, state: config.state, eventType: config.eventTrigger?.eventType, expectedEventType: type, updateTime: config.updateTime,
          document: config.eventTrigger?.eventFilters?.find((filter) => filter.attribute === "document")?.value});
      }
      if (configs.some((config) => config.state !== "ACTIVE" || config.eventType !== config.expectedEventType || config.document !== "event_analytics/{docId}")) throw Error("Deployed trigger transition does not match the approved contract");
      const source = db.doc(`event_analytics/${id}`), result = db.doc(`ai_insights/${id}`);
      const mutate = (operation, data) => db.runTransaction(async (tx) => { await guardEvent(id, tx); if (operation === "delete") tx.delete(source); else tx[operation](source, data); });
      await mutate("delete"); await waitFor(() => result.get(), (value) => !value.exists);
      const input = {totalAttendees: 7, hourlySignIns: {"09:00": 7}, dropoutRate: 0, repeatAttendees: 0};
      await mutate("set", input);
      const created = await waitFor(() => result.get(), (value) => value.exists && value.get("sourceFingerprint"));
      await mutate("update", {feedbackAnalytics: {commentSummaries: ["Controlled qualification feedback"]}});
      const updated = await waitFor(() => result.get(), (value) => value.exists && value.get("sourceFingerprint") !== created.get("sourceFingerprint"));
      await mutate("update", {qualificationReplayProbe: crypto.randomUUID()});
      const sourceVersion = (await source.get()).updateTime.toDate().toISOString();
      const filter = `jsonPayload.message="Analytics insight delivery completed" AND jsonPayload.eventId=${JSON.stringify(id)} AND jsonPayload.sourceVersion=${JSON.stringify(sourceVersion)}`;
      const logs = await waitFor(async () => (await client.request({url: "https://logging.googleapis.com/v2/entries:list", method: "POST", data: {resourceNames: [`projects/${context.projectId}`], filter, pageSize: 100, orderBy: "timestamp desc"}})).data.entries || [],
          (entries) => ["triggerAIInsights", "triggerAIInsightsV2"].every((name) => entries.some((entry) => entry.jsonPayload?.triggerName === name && entry.jsonPayload?.outcome === "replayed")));
      const replay = await result.get();
      await mutate("delete"); await waitFor(() => result.get(), (value) => !value.exists);
      const observed = {createdFingerprint: created.get("sourceFingerprint"), updatedFingerprint: updated.get("sourceFingerprint"),
        replayFingerprint: replay.get("sourceFingerprint"), updatedAt: updated.updateTime.toDate().toISOString(), replayUpdatedAt: replay.updateTime?.toDate().toISOString(), deletionObservedAt: new Date().toISOString()};
      const completions = logs.map((entry) => ({timestamp: entry.timestamp, insertId: entry.insertId, triggerName: entry.jsonPayload?.triggerName, deliveryId: entry.jsonPayload?.deliveryId, sourceVersion: entry.jsonPayload?.sourceVersion, outcome: entry.jsonPayload?.outcome}));
      const raw = write("backend-trigger-canaries/live.json", {...identity, canaryEventId: id, configs, observed, completions});
      return {rawPaths: [raw], blockers: [], assertions: [assertion("created_and_feedback_updated", true, observed.createdFingerprint !== observed.updatedFingerprint),
        assertion("both_deployed_trigger_versions_completed_replay", ["triggerAIInsights", "triggerAIInsightsV2"], [...new Set(completions.filter((entry) => entry.outcome === "replayed").map((entry) => entry.triggerName))].sort()),
        assertion("overlap_replay_preserves_fingerprint", observed.updatedFingerprint, observed.replayFingerprint),
        assertion("overlap_replay_does_not_rewrite_output", observed.updatedAt, observed.replayUpdatedAt), assertion("deletion_removes_output", false, (await result.get()).exists)]};
    });
    await gate("data-migration-recovery", async () => {
      const recovery = fixture.recovery;
      const pinned = recovery?.bundle;
      if (!pinned || !/^[a-z0-9][a-z0-9._-]{2,220}$/.test(pinned.bucket || "") || typeof pinned.object !== "string" || !pinned.object || !/^\d+$/.test(String(pinned.generation || "")) || !/^[a-f0-9]{64}$/.test(pinned.sha256 || "")) throw Error("A private generation-and-hash-pinned recovery bundle is required");
      const file = getStorage(app).bucket(pinned.bucket).file(pinned.object, {generation: String(pinned.generation)});
      const [metadata] = await file.getMetadata();
      if (String(metadata.generation) !== String(pinned.generation) || Number(metadata.size) > 16 * 1024 * 1024 || Number(metadata.size) <= 0) throw Error("Private recovery bundle generation or bounded size differs");
      const [bytes] = await file.download();
      if (hash(bytes) !== pinned.sha256) throw Error("Private recovery bundle content changed");
      const bundle = JSON.parse(bytes), prior = bundle.plan;
      if (bundle.schemaVersion !== 1 || bundle.restoreProject !== "attendus-recovery-20261004") throw Error("Private bundle names an unsupported restore target");
      if (!prior.readOnly || prior.fingerprintVersion !== 2 || !["orgami-66nxok", "attendus-staging"].includes(prior.project)) throw Error("Recovery plan must be a current version-2 read-only source inventory");
      const target = await captureRecoveryTarget({outputDir: path.join(outputDir, "data-migration-recovery/target"), sourceProject: prior.project, client});
      const proof = await verifyRecovery({admin: {initializeApp, deleteApp, storage: () => getStorage(app)}, project: prior.project, prior,
        reference: bundle.reference, exportName: bundle.exportOperation, importName: bundle.importOperation,
        restoreProject: bundle.restoreProject, recoveryTargetProof: target.proofPath});
      const content = compareRecoveryContent(bundle.sourceContent, await inventoryRestoredContent(client), bundle.sourceHeartbeatFields);
      const sourceApp = initializeApp({projectId: prior.project, credential: applicationDefault()}, `web-readiness-${crypto.randomUUID()}`);
      const sourceDb = getFirestore(sourceApp);
      let readiness;
      try { readiness = await readAuthoritativeReadiness(sourceDb, prior.project); }
      finally { await sourceDb.terminate(); await deleteApp(sourceApp); }
      const raw = write("data-migration-recovery/live.json", {...identity, observedAt: new Date().toISOString(), proof,
        bundle: {generation: metadata.generation, sha256: pinned.sha256}, verifiedEventCount: proof.verifiedEventCount, content, readiness});
      return {rawPaths: [raw, ...target.rawPaths.map((name) => `data-migration-recovery/target/${name}`)], blockers: [], assertions: [assertion("dedicated_restore_target", "attendus-recovery-20261004", proof.restoreProject),
        assertion("isolated_restore_verified", true, proof.isolation.isolated), assertion("nonempty_export_metadata", true, Number(proof.size) > 0),
        assertion("restored_full_document_count", bundle.sourceContent.documents, content.restored.documents),
        assertion("restored_business_content_equal_with_only_exact_explained_heartbeat_fields", true, content.businessContentEquivalent),
        assertion("migration_plan_has_no_ambiguous_admissions", 0, prior.events.reduce((sum, event) => sum + (Array.isArray(event.issues) ? event.issues.length : 1), 0)),
        assertion("live_source_has_no_ambiguous_or_unproven_admissions", 0, readiness.liveMigrationIssueCount),
        assertion("live_authoritative_publication_counters_ready", 0, readiness.quota.effectiveCounterBlocked),
        assertion("restored_source_and_archive_fingerprints_verified", prior.events.length, proof.verifiedEventCount)]};
    });
    await gate(requested?.has("observation") ? "observation" : "event-close-replay-observation", async () => {
      const closes = schedule(event.data()).end;
      if (!closes || closes.toISOString() !== fixture.eventClosesAt) throw Error("Current event close time differs from the controlled fixture schedule");
      // Configuration is deliberately seeded after deployment and therefore
      // must be reread independently of the deployed source/metadata digest.
      const [publicSettings, attendanceSettings] = await Promise.all([
        db.doc("AppConfig/publicWeb").get(), db.doc("AppConfig/attendance").get(),
      ]);
      const flags = runtimeFlags(publicSettings.data() || {}, attendanceSettings.data() || {}, fixture);
      const sample = {...identity, observedAt: snapshotAt, eventId, eventClosesAt: closes.toISOString(), eventRevision: event.get("eventRevision") || 0,
        rosterRevision: roster.get("revision") || 0, rosterCount: roster.get("count") ?? null, sourceCounts,
        jobs, captures, flags, runtimeFlagsSha256: hash(JSON.stringify(flags)), flagsObservedAt: new Date().toISOString(),
        elapsedSinceCloseMs: Date.parse(snapshotAt) - closes.getTime()};
      const previous = [];
      for (const entry of context.priorEvidence || []) {
        if (entry.report?.producer !== "tools/web_release_producers/backend.js" || !["observation", "event-close-replay-observation"].includes(entry.report?.gate)) continue;
        const relative = "event-close-replay-observation/sample.json";
        if (!entry.report.rawFiles?.[relative]) throw Error("Verified backend observation is missing its health sample");
        const bytes = fs.readFileSync(path.join(entry.outputDir, relative));
        if (entry.report.rawFiles?.[relative] !== hash(bytes)) throw Error("Historical observation raw content changed");
        const prior = JSON.parse(bytes);
        if (Object.keys(identity).some((key) => prior[key] !== identity[key])) throw Error("Historical observation belongs to a different candidate or fixture");
        previous.push(prior);
      }
      const raw = write("event-close-replay-observation/sample.json", sample);
      const assertions = observationAssertions(sample, previous);
      assertions.push(assertion("runtime_paid_and_wallet_providers_remain_disabled", [false, false, false],
          [flags.paidTicketCheckoutEnabled, flags.appleDeliveryEnabled, flags.googleDeliveryEnabled]));
      if (!requested?.has("observation")) {
        const settled = previous.filter((prior) => prior.eventClosesAt === sample.eventClosesAt && Date.parse(prior.observedAt) >= closes.getTime() + 15 * 60000 &&
          prior.jobs.length > 0 && prior.jobs.every((job) => terminal.has(job.status) && !["failed", "dead_letter"].includes(job.status)));
        assertions.push(assertion("authenticated_post_close_replay_baseline_exists", true, settled.length > 0));
        assertions.push(assertion("post_close_replay_observation_spans_24_hours", true, settled.length > 0 && Date.parse(sample.observedAt) >= closes.getTime() + 86400000 &&
          Date.parse(sample.observedAt) > Math.min(...settled.map((prior) => Date.parse(prior.observedAt)))));
      }
      return {rawPaths: [raw], blockers: [], window: {eventClosesAt: sample.eventClosesAt, replayObservedAt: sample.observedAt},
        assertions};
    });
    return {gates};
  } finally { await db.terminate(); await deleteApp(app); }
}
module.exports = {produce, summarizeCaptures, observationAssertions, requiredCaptureKinds};
