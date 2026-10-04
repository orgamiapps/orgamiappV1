"use strict";
// Read-only by default. Apply requires a current versioned plan and a live-verified isolated restore.
const fs = require("node:fs");
const {RECOVERY_PROJECT, readRecoveryTargetProof} = require("./recovery-target");
const {inspectEvent, fingerprint, readArchiveState, migrationUpdate, completedCheckpointMatches} = require("../events/migration");
const {allDocuments, key} = require("../events/roster");
const NAMES = ["RegisterAttendance", "Tickets", "Attendance"];
const option = (name) => process.argv.find((arg) => arg.startsWith(`${name}=`))?.slice(name.length + 1);

function validateRecoveryOperations({project, restoreProject, reference, exportOperation, importOperation}) {
  const prefix = reference.slice(0, reference.lastIndexOf("/"));
  if (restoreProject === project || restoreProject !== RECOVERY_PROJECT) throw Error("Recovery must use the dedicated isolated recovery project");
  for (const [operation, expectedProject, kind, uriField] of [[exportOperation, project, "ExportDocumentsMetadata", "outputUriPrefix"],
    [importOperation, restoreProject, "ImportDocumentsMetadata", "inputUriPrefix"]]) {
    if (!operation?.name?.startsWith(`projects/${expectedProject}/databases/(default)/operations/`) || operation.done !== true || operation.error ||
        !String(operation.metadata?.["@type"] || "").endsWith(kind) || operation.metadata.operationState !== "SUCCESSFUL" ||
        operation.metadata[uriField]?.replace(/\/$/, "") !== prefix || !Number.isFinite(Date.parse(operation.metadata.endTime))) {
      throw Error("Completed export/import operation evidence does not match the recovery scope");
    }
    if (operation.metadata.collectionIds?.length || operation.metadata.namespaceIds?.some((value) => value !== "")) {
      throw Error("Recovery requires the complete default-namespace Firestore export");
    }
  }
  if (Date.parse(importOperation.metadata.endTime) < Date.parse(exportOperation.metadata.endTime)) throw Error("Restore predates export completion");
  return {exportOperation: exportOperation.name, importOperation: importOperation.name, restoreProject};
}

async function sourceDocuments(db, eventId, tx = null) {
  const documents = await Promise.all(NAMES.map((name) => tx ? tx.get(db.collection(name).where("eventId", "==", eventId)) :
    allDocuments(db.collection(name).where("eventId", "==", eventId))));
  return documents.map((list) => (list.docs || list).map((doc) => ({...doc.data(), id: doc.id})));
}

async function verifyRecovery({admin, project, prior, reference, exportName, importName, restoreProject, recoveryTargetProof}) {
  if (!recoveryTargetProof) throw Error("A fresh isolated recovery-target proof is required");
  const isolation = readRecoveryTargetProof(recoveryTargetProof, {sourceProject: project});
  if (restoreProject !== isolation.projectId) throw Error("Restore project differs from verified isolation proof");
  if (!/^gs:\/\/[^/]+\/.+\.overall_export_metadata$/.test(reference || "")) throw Error("A completed Firestore export metadata object is required");
  for (const name of [exportName, importName]) if (!/^projects\/[a-z0-9-]+\/databases\/\(default\)\/operations\/[A-Za-z0-9_-]+$/.test(name || "")) throw Error("Explicit completed export and restore operation names are required");
  const client = await new (require("google-auth-library").GoogleAuth)({scopes: ["https://www.googleapis.com/auth/datastore"]}).getClient();
  const operations = await Promise.all([exportName, importName].map(async (name) => (await client.request({url: `https://firestore.googleapis.com/v1/${name}`})).data));
  const recovery = validateRecoveryOperations({project, restoreProject, reference, exportOperation: operations[0], importOperation: operations[1]});
  const match = /^gs:\/\/([^/]+)\/(.+)$/.exec(reference);
  const [metadata] = await admin.storage().bucket(match[1]).file(match[2]).getMetadata();
  if (!metadata.generation || Number(metadata.size) <= 0) throw Error("Export metadata object is unavailable");
  const restoreApp = admin.initializeApp({projectId: restoreProject}, `migration-recovery-${Date.now()}`);
  const restoreDb = require("firebase-admin/firestore").getFirestore(restoreApp);
  let verifiedEventCount = 0;
  try {
    const restoredEvents = await allDocuments(restoreDb.collection("Events"));
    if (fingerprint(restoredEvents.map((event) => event.id).sort()) !== fingerprint(prior.events.map((event) => event.eventId).sort())) throw Error("Restored event scope differs from the approved dry run");
    for (const approved of prior.events) {
      const event = await restoreDb.collection("Events").doc(approved.eventId).get();
      const sources = await sourceDocuments(restoreDb, approved.eventId);
      const archives = await readArchiveState(restoreDb, sources[2]);
      if (!event.exists || inspectEvent(approved.eventId, event.data(), sources).fingerprint !== approved.fingerprint ||
          archives.fingerprint !== approved.archiveStateFingerprint) throw Error("Live restored source/archive state does not match the approved dry run");
      verifiedEventCount++;
    }
  } finally { await restoreDb.terminate(); await admin.deleteApp(restoreApp); }
  return {...recovery, isolation, reference, generation: metadata.generation, size: metadata.size, verifiedEventCount,
    verifiedAt: new Date().toISOString(), scope: "Firestore event sources and affected archive/identity/group state", planFingerprint: fingerprint(prior)};
}

async function applyEvent({db, event, approved, inspected, sources, backup}) {
  const checkpoint = db.collection("LaunchMigrationCheckpoints").doc(key(`${event.id}:${approved.fingerprint}`));
  const prior = await checkpoint.get();
  if (prior.get("status") === "complete") {
    return db.runTransaction(async (tx) => {
      const [fresh, completed] = await Promise.all([tx.get(event.ref), tx.get(checkpoint)]);
      const currentSources = await sourceDocuments(db, event.id, tx);
      const current = inspectEvent(event.id, fresh.data(), currentSources);
      const archives = await readArchiveState(db, currentSources[2], tx, {verify: true});
      return completedCheckpointMatches(completed.data(), current, archives) ? "already_complete_verified" : "blocked_completed_checkpoint_changed";
    });
  }
  if (approved.fingerprint !== inspected.fingerprint || inspected.issues.length) return "blocked_source_changed_or_ambiguous";
  for (const source of sources[2]) {
    const item = checkpoint.collection("attendance").doc(key(source.id));
    const previousItem = await item.get();
    // Always verify a resumed item against live source and archive evidence.
    let reusable = false;
    if (previousItem.exists) {
      const proof = await readArchiveState(db, [source], null, {verify: true});
      reusable = previousItem.get("sourceFingerprint") === fingerprint(source) && previousItem.get("archiveFingerprint") === proof.entries[0].archiveFingerprint;
    }
    if (!reusable) await require("../account/attendance-history").archiveAttendance(db, source.id, source);
    await db.runTransaction(async (tx) => {
      const [current, state] = await Promise.all([tx.get(db.collection("Attendance").doc(source.id)), tx.get(checkpoint)]);
      if (!current.exists || fingerprint({...current.data(), id: current.id}) !== fingerprint(source)) throw Error("Attendance source changed during archival");
      const proof = await readArchiveState(db, [source], tx, {verify: true});
      tx.set(item, {status: "verified", ...proof.entries[0], verifiedAt: new Date()});
      if (state.get("status") !== "complete") tx.set(checkpoint, {status: "archiving", eventId: event.id, sourceFingerprint: inspected.fingerprint, fingerprintVersion: 2, lastVerifiedAttendanceId: source.id}, {merge: true});
    });
  }
  const applied = await db.runTransaction(async (tx) => {
    const [fresh, state] = await Promise.all([tx.get(event.ref), tx.get(checkpoint)]);
    const currentSources = await sourceDocuments(db, event.id, tx);
    const current = inspectEvent(event.id, fresh.data(), currentSources);
    const archives = await readArchiveState(db, currentSources[2], tx, {verify: true});
    if (state.get("status") === "complete") {
      if (!completedCheckpointMatches(state.data(), current, archives)) throw Error("Completed migration source or archive state changed");
      return false;
    }
    if (current.fingerprint !== inspected.fingerprint) throw Error("Source changed during migration; retry with a new dry run");
    for (const proof of archives.entries) {
      const item = await tx.get(checkpoint.collection("attendance").doc(key(proof.sourceId)));
      if (item.get("status") !== "verified" || item.get("sourceFingerprint") !== proof.sourceFingerprint || item.get("archiveFingerprint") !== proof.archiveFingerprint) throw Error("Archival item checkpoint changed before completion");
    }
    const update = migrationUpdate(inspected);
    const resulting = inspectEvent(event.id, {...fresh.data(), ...update}, currentSources);
    tx.update(event.ref, update);
    tx.set(checkpoint, {status: "complete", eventId: event.id, fingerprintVersion: 2, sourceFingerprint: inspected.fingerprint,
      resultingFingerprint: resulting.fingerprint, archiveFingerprint: archives.fingerprint, totals: inspected.totals,
      backup, attendanceSourceCount: inspected.attendanceSourceCount, confirmedCount: inspected.confirmedCount, completedAt: new Date()});
    return true;
  });
  return applied ? "complete_sources_preserved" : "already_complete_verified";
}

async function main() {
  const project = option("--project");
  if (!["orgami-66nxok", "attendus-staging", "demo-attendus-admin"].includes(project)) throw Error("An explicit supported --project is required.");
  if (project !== "demo-attendus-admin" && process.env.FIRESTORE_EMULATOR_HOST) throw Error("Unset emulator routing before targeting a real project");
  process.env.GCLOUD_PROJECT = project;
  const admin = require("../firebase-admin-compat"); const db = admin.firestore();
  const reportPath = option("--apply-report");
  const prior = reportPath ? JSON.parse(fs.readFileSync(reportPath, "utf8")) : null;
  let backup = null;
  try {
    if (prior) {
      if (prior.project !== project || !prior.readOnly || prior.fingerprintVersion !== 2 || !Array.isArray(prior.events) ||
          prior.events.some((event) => !event.archiveStateFingerprint)) throw Error("A fresh version-2 dry run with archive state is required");
      backup = await verifyRecovery({admin, project, prior, reference: option("--backup-object"), exportName: option("--export-operation"),
        importName: option("--restore-operation"), restoreProject: option("--restore-project"), recoveryTargetProof: option("--recovery-target-proof")});
    }
    const report = {project, fingerprintVersion: 2, readOnly: !prior, generatedAt: new Date().toISOString(), backup, events: []};
    for (const event of await allDocuments(db.collection("Events"))) {
      const sources = await sourceDocuments(db, event.id);
      const inspected = inspectEvent(event.id, event.data(), sources);
      if (prior) {
        const approved = prior.events.find((item) => item.eventId === event.id);
        if (!approved) { report.events.push({...inspected, result: "blocked_not_in_approved_scope"}); continue; }
        try { report.events.push({...inspected, result: await applyEvent({db, event, approved, inspected, sources, backup})}); }
        catch (error) { report.events.push({...inspected, result: "blocked_verification_failed", reason: error.message}); }
      } else {
        const archives = await readArchiveState(db, sources[2]);
        report.events.push({...inspected, archiveStateFingerprint: archives.fingerprint});
      }
    }
    if (prior) for (const approved of prior.events) if (!report.events.some((event) => event.eventId === approved.eventId)) report.events.push({eventId: approved.eventId, result: "blocked_approved_event_missing"});
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    if (report.events.some((event) => event.result?.startsWith("blocked"))) process.exitCode = 2;
  } finally { await db.terminate(); }
}
if (require.main === module) main().catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
module.exports = {validateRecoveryOperations, sourceDocuments, verifyRecovery, applyEvent};
