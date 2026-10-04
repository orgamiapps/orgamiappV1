'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {EventEmitter} = require('node:events');
const {safeLocation, assetLocation, exceptionMetadata, createBoundedWriter, observeStartup} = require('./startup-diagnostics.cjs');

test('location strips query credentials fragment and credential path segments', () => {
  assert.deepEqual(safeLocation('https://name:password@example.test/manage/bearer-proof?token=secret#secret'), {origin: 'https://example.test', path: '/manage/[redacted]'});
  assert.equal(safeLocation('data:text/plain,private'), null);
  assert.equal(safeLocation('not a URL'), null);
});

test('assets cover SDK and engine startup without collecting emulator data or flooding on DDC modules', () => {
  for (const url of ['https://www.gstatic.com/firebasejs/12.15.0/firebase-auth.js?secret=a', 'http://localhost:3456/main.dart.bootstrap.js', 'http://localhost:3456/canvaskit/chromium/canvaskit.wasm']) assert.ok(assetLocation(url, 'GET'));
  for (const url of ['http://localhost:5101/demo-attendus-admin/us-central1/privateCall', 'http://localhost:8080/v1/projects/demo/databases/(default)/documents/Customers/private', 'http://localhost:3456/packages/attendus/customer.dart.lib.js']) assert.equal(assetLocation(url, 'GET'), null);
  assert.equal(assetLocation('https://www.gstatic.com/firebasejs/12.15.0/firebase-auth.js', 'POST'), null);
});

test('page errors retain useful static classification but no arbitrary messages or URL secrets', () => {
  const result = exceptionMetadata({name: 'TypeError', message: 'Failed to fetch dynamically imported module: https://user:pass@www.gstatic.com/firebasejs/12.15.0/firebase-auth.js?token=supersecret#private AUTH eyJsecret hello@example.test'});
  assert.equal(result.category, 'module-import');
  assert.deepEqual(result.sources, [{origin: 'https://www.gstatic.com', path: '/firebasejs/12.15.0/firebase-auth.js'}]);
  assert.doesNotMatch(JSON.stringify(result), /supersecret|private|pass|AUTH|eyJsecret|hello/);
  assert.deepEqual(exceptionMetadata(new Error('Private response body')), {name: 'Error', category: 'unclassified', sources: []});
  assert.deepEqual(exceptionMetadata(new Error('Failed fetch https://example.test/download/opaque-proof')), {
    name: 'Error', category: 'network', sources: [{origin: 'https://example.test', path: '[redacted]'}],
  });
});

test('writer enforces both record and byte limits with one cap marker', () => {
  for (const options of [{maxRecords: 3, maxBytes: 4096}, {maxRecords: 400, maxBytes: 100}]) {
    const lines = []; const write = createBoundedWriter(line => lines.push(line), options);
    for (let i = 0; i < 100; i++) write({event: 'asset-start', id: i});
    assert.ok(lines.length <= options.maxRecords);
    assert.ok(Buffer.byteLength(lines.join('')) <= options.maxBytes);
    assert.equal(lines.filter(line => line.includes('diagnostics-capped')).length, 1);
  }
});

test('observer records allowed failed import, pending assets, and SDK phases without payloads', () => {
  const page = new EventEmitter(), context = new EventEmitter();
  context.pages = () => [page];
  let clock = 100; const entries = [];
  const stop = observeStartup(context, value => entries.push(value), {now: () => clock, allowed: () => true});
  const req = {url: () => 'https://www.gstatic.com/firebasejs/12.15.0/firebase-auth.js?apiKey=secret', method: () => 'GET', failure: () => ({errorText: 'net::ERR_CONNECTION_RESET private-body'})};
  context.emit('request', req); clock += 20;
  context.emit('response', {request: () => req, status: () => 200});
  context.emit('requestfailed', req);
  context.emit('request', {...req, url: () => 'https://www.gstatic.com/firebasejs/12.15.0/firebase-storage.js'});
  page.emit('console', {text: () => 'Initializing Firebase firebase_auth'});
  page.emit('console', {text: () => 'User token secret'});
  page.emit('pageerror', new TypeError('Failed to fetch dynamically imported module: https://www.gstatic.com/firebasejs/12.15.0/firebase-auth.js?secret=private'));
  stop(); stop();
  assert.equal(entries.filter(entry => entry.event === 'asset-failed')[0].errorCode, 'net::ERR_CONNECTION_RESET');
  assert.equal(entries.at(-1).pendingCount, 1);
  assert.equal(entries.at(-1).assetCount, 2);
  assert.equal(entries.filter(entry => entry.event === 'firebase-module-initializing').length, 1);
  assert.doesNotMatch(JSON.stringify(entries), /private|secret|apiKey|User token/);
  assert.equal(context.listenerCount('request'), 0);
  assert.equal(page.listenerCount('pageerror'), 0);
});
