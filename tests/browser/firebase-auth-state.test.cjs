'use strict';
const test = require('node:test'), assert = require('node:assert/strict'), vm = require('node:vm');
const fs = require('node:fs');
const {readFirebaseAuthStateInBrowser: read, readFirebaseAuthStatePage: readPage} = require('../../tools/web_release_producers/firebase-auth-state');
const now = 1791132000;
const options = {projectId: 'attendus-staging', apiKey: 'synthetic_fixture_api_key', appName: '[DEFAULT]', expectedUid: 'controlled-owner'};
const key = `firebase:authUser:${options.apiKey}:${options.appName}`;
const token = (patch = {}) => [
  {alg: 'RS256', typ: 'JWT'},
  {aud: options.projectId, iss: `https://securetoken.google.com/${options.projectId}`, sub: options.expectedUid,
    user_id: options.expectedUid, iat: now - 60, exp: now + 3500, auth_time: now - 120, firebase: {sign_in_provider: 'password'}, ...patch},
].map(value => Buffer.from(JSON.stringify(value)).toString('base64url')).join('.') + '.c3ludGhldGljX3NpZ25hdHVyZQ';
const record = (patch = {}) => ({uid: options.expectedUid, email: 'controlled@example.test', emailVerified: true,
  isAnonymous: false, providerData: [{providerId: 'password', uid: 'controlled@example.test'}],
  stsTokenManager: {accessToken: token(), refreshToken: 'MUST_NOT_BE_RETURNED', expirationTime: (now + 3500) * 1000},
  createdAt: '1791120000000', lastLoginAt: String(now * 1000), apiKey: options.apiKey, appName: options.appName, ...patch});
function browser(rows = new Map(), settings = {}) {
  const reads = [];
  const context = vm.createContext({Uint8Array, TextDecoder, atob, Date: class extends Date {static now() {return now * 1000;}},
    localStorage: {getItem(name) {reads.push(name); if (settings.denied) throw Error('private-storage-message'); return rows.get(name) ?? null;}},
    get indexedDB() {throw Error('IndexedDB must never be used');},
  });
  const run = (input = options) => JSON.parse(JSON.stringify(vm.runInContext(`(${read.toString()})(${JSON.stringify(input)})`, context)));
  return {run, reads};
}
function rejectRecord(value, expectedCode) {
  const result = browser(new Map([[key, typeof value === 'string' ? value : JSON.stringify(value)]])).run();
  assert.deepEqual(result, {state: 'rejected', code: expectedCode});
  assert.equal(JSON.stringify(result).includes('MUST_NOT_BE_RETURNED'), false);
}
test('serialized browser reader accepts exact LOCAL User.toJSON record without using IndexedDB', () => {
  const b = browser(new Map([[key, JSON.stringify(record())]]));
  assert.deepEqual(b.run(), {state: 'ready', uid: options.expectedUid, isAnonymous: false, token: token()});
  assert.deepEqual(b.reads, [key]);
});
test('foreign API key and public HTML app namespace are never selected', () => {
  const b = browser(new Map([['firebase:authUser:other:[DEFAULT]', JSON.stringify(record())],
    [`firebase:authUser:${options.apiKey}:attendus-public-web`, JSON.stringify(record())]]));
  assert.deepEqual(b.run(), {state: 'missing'}); assert.deepEqual(b.reads, [key]);
});
test('stale IndexedDB cannot override missing or foreign LOCAL state', () => {
  assert.deepEqual(browser().run(), {state: 'missing'});
  rejectRecord(record({uid: 'different-owner'}), 'actor_identity_mismatch');
});
test('privacy/storage denial fails closed with no raw exception or fallback', () => {
  assert.deepEqual(browser(new Map(), {denied: true}).run(), {state: 'rejected', code: 'local_storage_unavailable'});
});
test('malformed bounded LOCAL records reject', () => {
  for (const value of ['{bad secret', 'null', '[]', '1', 'x'.repeat(65537)]) rejectRecord(value, 'malformed_local_record');
});
test('record app/key/anonymous identity mismatch rejects', () => {
  rejectRecord(record({apiKey: 'foreign'}), 'app_identity_mismatch');
  rejectRecord(record({appName: 'attendus-public-web'}), 'app_identity_mismatch');
  rejectRecord(record({isAnonymous: true}), 'actor_identity_mismatch');
});
test('token must bind project issuer and both actor claims', () => {
  for (const [patch, code] of [[{aud: 'orgami-66nxok'}, 'token_project_mismatch'], [{iss: 'https://evil.test'}, 'token_project_mismatch'],
    [{sub: 'foreign'}, 'token_actor_mismatch'], [{user_id: 'foreign'}, 'token_actor_mismatch'],
    [{firebase: {sign_in_provider: 'anonymous'}}, 'token_actor_mismatch']]) rejectRecord(record({stsTokenManager: {accessToken: token(patch)}}), code);
});
test('expired/future/noninteger token times fail closed', () => {
  for (const patch of [{exp: now}, {iat: now + 31}, {iat: 0}, {iat: 'not-time'}, {exp: now - 100}, {auth_time: now + 100}]) {
    rejectRecord(record({stsTokenManager: {accessToken: token(patch)}}), 'token_time_invalid');
  }
});
test('malformed token/header payload is not echoed', () => {
  for (const value of ['secret', 'a.b.c', 'a'.repeat(16385), token().replace(/^.*?\./, Buffer.from('{"alg":"none"}').toString('base64url') + '.')]) {
    rejectRecord(record({stsTokenManager: {accessToken: value}}), 'malformed_identity_token');
  }
});
test('expected binding is required before storage is accessed', () => {
  for (const patch of [{expectedUid: ''}, {projectId: 'orgami-66nxok'}, {appName: 'attendus-public-web'}, {apiKey: 'bad:key'}]) {
    const b = browser(); assert.equal(b.run({...options, ...patch}).code, 'invalid_expected_identity'); assert.deepEqual(b.reads, []);
  }
});
test('bounded page adapter allows asynchronous initial LOCAL settle, never authentication retry', async () => {
  let calls = 0;
  const page = {async evaluate(fn, input) {
    assert.equal(fn, read); assert.deepEqual(input, options);
    calls++; return calls === 1 ? {state: 'missing'} : {state: 'ready', uid: options.expectedUid, isAnonymous: false, token: token()};
  }};
  assert.deepEqual(await readPage(page, {...options, timeoutMs: 1000}), {uid: options.expectedUid, isAnonymous: false, token: token()});
  assert.equal(calls, 2);
});
test('foreign LOCAL record fails immediately instead of waiting for a different account', async () => {
  let calls = 0;
  await assert.rejects(readPage({async evaluate() {calls++; return {state: 'rejected', code: 'actor_identity_mismatch'};}}, options), {code: 'actor_identity_mismatch'});
  assert.equal(calls, 1);
});
test('pending page evaluation cannot exceed phase budget and raw browser errors stay sanitized', async () => {
  await assert.rejects(readPage({evaluate() {return new Promise(() => {});}}, {...options, timeoutMs: 10}), {code: 'local_state_timeout'});
  await assert.rejects(readPage({evaluate() {throw Error('token-private');}}, options), error => error.code === 'browser_read_failed' && !error.message.includes('token-private'));
});
test('missing state stops within budget; invalid timeout starts no read', async () => {
  let calls = 0;
  await assert.rejects(readPage({async evaluate() {calls++; return {state: 'missing'};}}, {...options, timeoutMs: 10}), {code: 'local_state_timeout'});
  const after = calls; await new Promise(resolve => setTimeout(resolve, 25)); assert.equal(calls, after);
  for (const timeoutMs of [0, -1, 30001, Infinity]) await assert.rejects(readPage({evaluate() {throw Error('should not run');}}, {...options, timeoutMs}), {code: 'invalid_expected_identity'});
  await assert.rejects(readPage({evaluate() {throw Error('should not run');}}), {code: 'invalid_expected_identity'});
});

test('an early timeout timer cancels the polling loop before any post-return read', async () => {
  let monotonicNow = 0, nextTimer = 0, calls = 0;
  const timers = new Map();
  const module = {exports: {}};
  vm.runInNewContext(fs.readFileSync(require.resolve('../../tools/web_release_producers/firebase-auth-state'), 'utf8'), {
    module, performance: {now: () => monotonicNow},
    setTimeout(callback, delay) {const id = ++nextTimer; timers.set(id, {callback, delay}); return id;},
    clearTimeout(id) {timers.delete(id);},
  });
  const pending = module.exports.readFirebaseAuthStatePage({async evaluate() {calls++; return {state: 'missing'};}}, {...options, timeoutMs: 10});
  const rejected = assert.rejects(pending, {code: 'local_state_timeout'});
  // Drain cross-realm Promise adoption without depending on wall-clock timing.
  for (let tick = 0; tick < 12; tick++) await Promise.resolve();
  assert.equal(calls, 1);
  assert.equal(timers.size, 2, 'One deadline and one pending poll timer');
  const [deadlineId, deadlineTimer] = timers.entries().next().value;
  assert.equal(deadlineTimer.delay, 10);
  // Real timers can fire before the fractional performance.now deadline.
  monotonicNow = 9.5;
  timers.delete(deadlineId);
  deadlineTimer.callback();
  await rejected;
  const callsWhenReturned = calls;
  try {
    // Wake any previously scheduled poll while the monotonic deadline is still
    // in the future. Cancellation, not the clock comparison, must stop it.
    monotonicNow = 9.75;
    for (const [id, timer] of [...timers]) {timers.delete(id); timer.callback();}
    for (let tick = 0; tick < 12; tick++) await Promise.resolve();
    assert.equal(calls, callsWhenReturned, 'No evaluation starts after timeout returns');
    assert.equal(timers.size, 0, 'Cancelled polling leaves no scheduled work');
  } finally {
    monotonicNow = 11;
    for (const [id, timer] of [...timers]) {timers.delete(id); timer.callback();}
    await Promise.resolve();
  }
});

test('an in-flight evaluation settling after timeout cannot schedule further polling', async () => {
  let monotonicNow = 0, nextTimer = 0, calls = 0, finishRead;
  const timers = new Map(), module = {exports: {}};
  vm.runInNewContext(fs.readFileSync(require.resolve('../../tools/web_release_producers/firebase-auth-state'), 'utf8'), {
    module, performance: {now: () => monotonicNow},
    setTimeout(callback, delay) {const id = ++nextTimer; timers.set(id, {callback, delay}); return id;},
    clearTimeout(id) {timers.delete(id);},
  });
  const pending = module.exports.readFirebaseAuthStatePage({evaluate() {
    calls++;
    return new Promise(resolve => {finishRead = resolve;});
  }}, {...options, timeoutMs: 10});
  const rejected = assert.rejects(pending, {code: 'local_state_timeout'});
  assert.equal(calls, 1);
  assert.equal(timers.size, 1, 'Only the deadline is scheduled while evaluation is pending');
  const [id, timer] = timers.entries().next().value;
  monotonicNow = 9.5;
  timers.delete(id); timer.callback();
  await rejected;
  try {
    finishRead({state: 'missing'});
    for (let tick = 0; tick < 12; tick++) await Promise.resolve();
    assert.equal(calls, 1, 'Only the already-started evaluation may complete');
    assert.equal(timers.size, 0, 'Late completion cannot schedule post-return work');
  } finally {
    monotonicNow = 11;
    for (const [id, timer] of [...timers]) {timers.delete(id); timer.callback();}
    for (let tick = 0; tick < 12; tick++) await Promise.resolve();
  }
});
