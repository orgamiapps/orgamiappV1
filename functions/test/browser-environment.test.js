"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {browserEnvironment} = require("../public-web/browser-environment");

test("staging public pages authenticate against staging, never production", () => {
  const value = browserEnvironment({GCLOUD_PROJECT: "attendus-staging"});
  assert.equal(value.firebase.projectId, "attendus-staging");
  assert.equal(value.firebase.authDomain, "attendus-staging.firebaseapp.com");
  assert.match(value.firebase.appId, /^1:925344893088:web:/);
  assert.deepEqual(value.connectSources, ["https://us-central1-attendus-staging.cloudfunctions.net"]);
  assert.equal(value.emulators, undefined);
});
test("production remains production even with an emulator environment flag", () => {
  const value = browserEnvironment({GCLOUD_PROJECT: "orgami-66nxok", FUNCTIONS_EMULATOR: "true"});
  assert.equal(value.firebase.authDomain, "attendus.app");
  assert.equal(value.emulators, undefined);
});
test("emulator bypass requires both demo project and emulator process", () => {
  assert.throws(() => browserEnvironment({GCLOUD_PROJECT: "demo-attendus-admin"}));
  assert.throws(() => browserEnvironment({}));
  assert.throws(() => browserEnvironment({GCLOUD_PROJECT: "unknown"}));
  const value = browserEnvironment({GCLOUD_PROJECT: "demo-attendus-admin", FUNCTIONS_EMULATOR: "true"});
  assert.equal(value.emulators.host, "127.0.0.1");
  assert.equal(value.firebase.projectId, "demo-attendus-admin");
});

test("public CSP permits its callable API and reCAPTCHA without broad origin bypass", () => {
  const previous = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = "attendus-staging";
  try {
    const headers = {};
    require("../public-web/renderer").pageHeaders({set: (name, value) => { headers[name] = value; }}, "fixture-nonce");
    assert.match(headers["Content-Security-Policy"], /https:\/\/us-central1-attendus-staging\.cloudfunctions\.net/);
    assert.match(headers["Content-Security-Policy"], /script-src[^;]+https:\/\/www\.google\.com\/recaptcha\//);
    assert.doesNotMatch(headers["Content-Security-Policy"], /http:\/\/127\.0\.0\.1/);
    assert.match(headers["Content-Security-Policy"], /frame-ancestors 'none'/);
  } finally {
    if (previous === undefined) delete process.env.GCLOUD_PROJECT;
    else process.env.GCLOUD_PROJECT = previous;
  }
});
