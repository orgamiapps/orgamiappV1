"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  DELETE_CONFIRMATION,
  assertDeletionAuthorized,
} = require("../biometrics/retention");

const deletionRequest = {
  confirmation: DELETE_CONFIRMATION,
  backupReference: "gs://verified-backup/export-2026-08-02",
  notBefore: "2026-09-01",
};

test("biometric deletion requires an exact typed confirmation", () => {
  assert.throws(
      () => assertDeletionAuthorized({
        ...deletionRequest,
        confirmation: "delete",
        now: new Date("2026-09-01T00:00:00Z"),
      }),
      /requires --confirm/,
  );
});

test("biometric deletion requires a verified backup reference", () => {
  assert.throws(
      () => assertDeletionAuthorized({
        ...deletionRequest,
        backupReference: "",
        now: new Date("2026-09-01T00:00:00Z"),
      }),
      /backup-reference/,
  );
});

test("biometric deletion cannot run before the retention date", () => {
  assert.throws(
      () => assertDeletionAuthorized({
        ...deletionRequest,
        now: new Date("2026-08-31T23:59:59Z"),
      }),
      /blocked until/,
  );
});

test("biometric deletion accepts a verified request after retention", () => {
  const result = assertDeletionAuthorized({
    ...deletionRequest,
    now: new Date("2026-09-01T00:00:00Z"),
  });
  assert.equal(result.backupReference, deletionRequest.backupReference);
  assert.equal(result.notBefore, deletionRequest.notBefore);
});
