"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {fingerprint, inspectEvent, verifyArchiveRecord, migrationUpdate, completedCheckpointMatches} = require("../events/migration");
const {evidence, evidenceFingerprint, sourceCorrectionId} = require("../account/attendance-history");
const {validateRecoveryOperations} = require("../tools/complete-launch-migration");

test("migration fingerprint tolerates field/query order but detects source revisions", () => {
  const a = inspectEvent("event", {title: "Fixture", eventRevision: 2}, [[{id: "b", status: "confirmed"}, {id: "a", status: "pending"}], [], []]);
  const b = inspectEvent("event", {eventRevision: 2, title: "Fixture"}, [[{status: "pending", id: "a"}, {status: "confirmed", id: "b"}], [], []]);
  assert.equal(a.fingerprint, b.fingerprint);
  assert.notEqual(a.fingerprint, inspectEvent("event", {title: "Changed", eventRevision: 2}, [[{id: "b", status: "confirmed"}, {id: "a", status: "pending"}], [], []]).fingerprint);
});

test("completed checkpoint reuse requires resulting state and exact verified archive proof", () => {
  const source = inspectEvent("event", {title: "Fixture"}, [[], [], []]);
  const result = inspectEvent("event", {title: "Fixture", ...migrationUpdate(source)}, [[], [], []]);
  const archives = {fingerprint: fingerprint([])};
  const checkpoint = {status: "complete", fingerprintVersion: 2, resultingFingerprint: result.fingerprint,
    archiveFingerprint: archives.fingerprint, attendanceSourceCount: 0, confirmedCount: result.confirmedCount, totals: result.totals};
  assert.equal(completedCheckpointMatches(checkpoint, result, archives), true);
  assert.equal(completedCheckpointMatches(checkpoint, source, archives), false);
  assert.equal(completedCheckpointMatches({...checkpoint, fingerprintVersion: undefined}, result, archives), false);
  assert.equal(completedCheckpointMatches(checkpoint, result, {fingerprint: "tampered"}), false);
});

test("archive proof verifies original, complete correction chain and current source match", () => {
  const source = {id: "attendance", eventId: "event", checkedIn: true};
  const stamp = {...evidence(source.id, source), admissionGroupId: "group"};
  const archive = {...stamp, evidenceFingerprint: evidenceFingerprint(stamp)};
  assert.equal(typeof verifyArchiveRecord(source, archive, []), "string");
  assert.throws(() => verifyArchiveRecord(source, {...archive, voided: true}, []), /fingerprint changed/);
  const changed = {...source, status: "checked_out"};
  assert.throws(() => verifyArchiveRecord(changed, archive, []), /does not match/);
  const corrected = {...evidence(changed.id, changed), admissionGroupId: "group"};
  const correction = {id: sourceCorrectionId(corrected), data: {source: "attendance_record_update", evidence: corrected}};
  assert.equal(typeof verifyArchiveRecord(changed, archive, [correction]), "string");
  assert.throws(() => verifyArchiveRecord(changed, archive, [{...correction, id: "tampered"}]), /chain verification/);
});

function recovery() {
  const project = "orgami-66nxok", restoreProject = "attendus-recovery-20261004", reference = "gs://backup/export/export.overall_export_metadata";
  const op = (owner, kind, uri, endTime) => ({name: `projects/${owner}/databases/(default)/operations/fixture`, done: true,
    metadata: {"@type": `type.googleapis.com/google.firestore.admin.v1.${kind}`, operationState: "SUCCESSFUL", [uri]: "gs://backup/export", endTime}});
  return {project, restoreProject, reference,
    exportOperation: op(project, "ExportDocumentsMetadata", "outputUriPrefix", "2026-09-27T10:00:00Z"),
    importOperation: op(restoreProject, "ImportDocumentsMetadata", "inputUriPrefix", "2026-09-27T11:00:00Z")};
}

test("recovery gate rejects incomplete, wrong-project, wrong-export and partial-scope evidence", () => {
  assert.equal(validateRecoveryOperations(recovery()).restoreProject, "attendus-recovery-20261004");
  for (const mutate of [
    (value) => { value.exportOperation.done = false; },
    (value) => { value.importOperation.error = {code: 13}; },
    (value) => { value.restoreProject = value.project; },
    (value) => { value.restoreProject = "attendus-staging"; },
    (value) => { value.restoreProject = "demo-attendus-admin"; },
    (value) => { value.importOperation.metadata.inputUriPrefix = "gs://unrelated/export"; },
    (value) => { value.exportOperation.metadata.collectionIds = ["Events"]; },
    (value) => { value.importOperation.metadata.endTime = "2026-09-27T09:00:00Z"; },
  ]) { const value = recovery(); mutate(value); assert.throws(() => validateRecoveryOperations(value)); }
});
