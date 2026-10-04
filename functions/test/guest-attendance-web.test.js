"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const vm = require("node:vm");
const {acquireGuestLocation, guestPassResponse} = require("../attendance/guest-web");

function browser() {
  const listeners = new Map();
  const removed = [];
  let success, failure, timeout;
  const target = {addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: name => listeners.delete(name)};
  const document = {...target, hidden: false};
  const context = {document, window: {...target, isSecureContext: true},
    navigator: {geolocation: {watchPosition: (ok, fail) => {success = ok; failure = fail; return 17;}, clearWatch: id => removed.push(id)}},
    setTimeout: callback => {timeout = callback; return 1;}, clearTimeout: () => {timeout = null;}, Date, Number, Error};
  const pending = vm.runInNewContext(`(${acquireGuestLocation.toString()})()`, context);
  return {pending, document, listeners, removed, position: value => success(value), fail: () => failure(), expire: () => timeout()};
}
const position = (accuracy = 10, timestamp = Date.now()) => ({timestamp, coords: {accuracy, latitude: 1, longitude: 1}});

test("guest location clears the subscription after a fresh accurate sample", async () => {
  const run = browser();
  run.position(position(80));
  run.position(position(10, Date.now() - 31000));
  assert.deepEqual(run.removed, []);
  run.position(position());
  await run.pending;
  assert.deepEqual(run.removed, [17]);
  assert.equal(run.listeners.size, 0);
});

test("guest location cancels on background, page exit, timeout, and permission failure", async () => {
  for (const reason of ["background", "exit", "timeout", "permission"]) {
    const run = browser();
    if (reason === "background") {run.document.hidden = true; run.listeners.get("visibilitychange")();}
    if (reason === "exit") run.listeners.get("pagehide")();
    if (reason === "timeout") run.expire();
    if (reason === "permission") run.fail();
    await assert.rejects(run.pending);
    assert.deepEqual(run.removed, [17]);
    assert.equal(run.listeners.size, 0);
    // A late native callback must not restart work or change the settled result.
    run.position(position());
    assert.deepEqual(run.removed, [17]);
  }
});

test("locked guest pass JSON does not expose the signed credential", async () => {
  const result = await guestPassResponse({passId: "stable", qrData: "secret-signed-credential", passLockRequired: true,
    appleWalletUrl: null, googleWalletUrl: null});
  assert.equal(result.passId, "stable");
  assert.equal(result.qrImage, null);
  assert.equal(Object.hasOwn(result, "qrData"), false);
  assert.equal(JSON.stringify(result).includes("secret-signed-credential"), false);
});
