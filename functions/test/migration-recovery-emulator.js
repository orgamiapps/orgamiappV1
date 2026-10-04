"use strict";

// Synthetic emulator backup/restore rehearsal, never cloud migration evidence.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {spawnSync} = require("node:child_process");
assert.equal(process.env.GCLOUD_PROJECT, "demo-attendus-admin");
assert.match(process.env.FIRESTORE_EMULATOR_HOST || "", /^127\.0\.0\.1:\d+$/);
const directory = path.resolve(process.env.ATTENDUS_RECOVERY_DIRECTORY || "");
const build = path.resolve(__dirname, "../../build") + path.sep;
assert.ok(directory.startsWith(build) && path.basename(directory).startsWith("migration-recovery-"));
process.env.FUNCTIONS_EMULATOR = "true";
process.env.GUEST_CONTACT_KMS_KEY_NAME = "emulator";
process.env.GUEST_CONTACT_HMAC_KEY = "recovery-fixture-only";
const db = require("../firebase-admin-compat").firestore();
const {sourceDocuments, applyEvent} = require("../tools/complete-launch-migration");
const {inspectEvent} = require("../events/migration");
const id = "recovery-isolated-fixture";

(async () => {
  const ref = db.collection("Events").doc(id);
  const phase = process.argv[2];
  if (phase === "seed") {
    fs.mkdirSync(directory, {recursive: true});
    await ref.set({title: "Synthetic recovery fixture", eventTimeZone: "UTC", eventDurationMinutes: 60,
      selectedDateTime: new Date("2026-10-03T12:00:00Z")});
    await db.collection("Attendance").doc(id).set({eventId: id, customerUid: "recovery-fixture-user", checkedIn: true});
    const event = await ref.get();
    const sources = await sourceDocuments(db, id);
    const approved = inspectEvent(id, event.data(), sources);
    fs.writeFileSync(path.join(directory, "expected.json"), JSON.stringify({fingerprint: approved.fingerprint}));
    const exportResult = spawnSync(process.execPath, [require.resolve("firebase-tools/lib/bin/firebase"),
      "emulators:export", "--project", "demo-attendus-admin", path.join(directory, "export")],
    {stdio: "inherit", windowsHide: true});
    assert.equal(exportResult.status, 0, "The real local emulator export must succeed");
    assert.equal(await applyEvent({db, event, sources, approved, inspected: approved, backup: {fixtureOnly: true}}), "complete_sources_preserved");
    await ref.update({title: "Injected post-migration source drift"});
    assert.equal(await applyEvent({db, event, sources, approved, inspected: approved, backup: {fixtureOnly: true}}), "blocked_completed_checkpoint_changed");
  } else {
    assert.equal(phase, "restore");
    const event = await ref.get();
    assert.ok(event.exists, "Restored fixture is required");
    const sources = await sourceDocuments(db, id);
    const approved = inspectEvent(id, event.data(), sources);
    assert.equal(approved.fingerprint, JSON.parse(fs.readFileSync(path.join(directory, "expected.json"))).fingerprint);
    assert.equal(event.get("confirmedRegistrationCount"), undefined);
    assert.equal((await db.collection("LaunchMigrationCheckpoints").get()).size, 0);
    assert.equal((await db.collection("HistoricalAttendance").get()).size, 0);
    assert.equal(sources[2].length, 1);
    assert.equal(await applyEvent({db, event, sources, approved, inspected: approved, backup: {fixtureOnly: true}}), "complete_sources_preserved");
    fs.writeFileSync(path.join(directory, "result.json"), JSON.stringify({project: "demo-attendus-admin",
      status: "local-export-restore-and-reapply-verified", productionRecoveryQualified: false,
      restoredFingerprint: approved.fingerprint, verifiedAt: new Date().toISOString()}, null, 2));
  }
  console.log(`Synthetic migration recovery ${phase} passed: ${directory}`);
})().catch((error) => { console.error(error); process.exitCode = 1; }).finally(() => db.terminate());
