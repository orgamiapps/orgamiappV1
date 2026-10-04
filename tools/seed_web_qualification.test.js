"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {validateLiveEnvironment, apply} = require("./seed_web_qualification");

test("live staging setup rejects each emulator endpoint before reading inputs or writing data", async () => {
  validateLiveEnvironment({});
  for (const name of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST", "STORAGE_EMULATOR_HOST", "FIREBASE_DATABASE_EMULATOR_HOST"]) {
    assert.throws(() => validateLiveEnvironment({[name]: "127.0.0.1:9190"}), /cannot use emulator/);
  }
  const original = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  try {
    process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9190";
    await assert.rejects(apply("missing-private-context", "missing-candidate", "missing-receipt"), /cannot use emulator/);
  } finally {
    if (original === undefined) delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
    else process.env.FIREBASE_AUTH_EMULATOR_HOST = original;
  }
});
