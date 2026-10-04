'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {allowedBrowserRequest: allow} = require('./network-policy.cjs');
test('only loopback application services and read-only SDK assets are allowed', () => {
  assert.equal(allow('http://127.0.0.1:5101/demo-attendus-admin/us-central1/example', 'POST'), true);
  assert.equal(allow('https://www.gstatic.com/firebasejs/12.0.0/firebase-app.js'), true);
  assert.equal(allow('https://www.gstatic.com/flutter-canvaskit/hash/canvaskit.wasm'), true);
  for (const url of ['https://attendus.app', 'https://attendus-staging.web.app',
    'https://identitytoolkit.googleapis.com', 'https://firestore.googleapis.com',
    'https://maps.googleapis.com', 'https://fcmregistrations.googleapis.com',
    'https://storage.googleapis.com/private/export.csv', 'https://www.gstatic.com/unexpected',
    'https://127.0.0.1.evil.test', 'file:///private.txt']) assert.equal(allow(url), false, url);
  assert.equal(allow('https://www.gstatic.com/firebasejs/example', 'POST'), false);
});
