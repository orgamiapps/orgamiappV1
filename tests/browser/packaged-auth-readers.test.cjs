'use strict';
const test = require('node:test'), assert = require('node:assert/strict'), vm = require('node:vm');
const {authIdentity} = require('../../tools/web_release_producers/safari');
const {initializedAuthIdentity, readCacheAuthIdentity} = require('../../tools/web_release_producers/browser-cache-upgrade')._test;
const key = 'fixture-key', storageKey = `firebase:authUser:${key}:[DEFAULT]`;
function driverWithLocal(value, {denied = false} = {}) {
  let idbReads = 0;
  const context = {localStorage: {getItem(k) {assert.equal(k, storageKey); if (denied) throw Error('private-storage-error'); return value;}},
    indexedDB: {open() {
      idbReads++; const opening = {};
      queueMicrotask(() => {opening.result = {close() {}, objectStoreNames: {contains: () => true},
        transaction: () => ({objectStore: () => ({getAll() {const q = {}; queueMicrotask(() => {
          q.result = [{fbase_key: storageKey, value: {uid: 'stale-idb', isAnonymous: false}}]; q.onsuccess();
        }); return q;}})})}; opening.onsuccess();}); return opening;
    }}};
  return {driver: {execute: async (fn, ...args) => vm.runInNewContext(`(${fn.toString()})(...args)`, {...context, args}),
    executeAsync: async (script, args) => new Promise(resolve => vm.runInNewContext(`(function(){${script}}).apply(null,args)`, {...context, args: [...args, resolve]}))},
  idbReads: () => idbReads};
}
function local(patch = {}) {return JSON.stringify({apiKey: key, appName: '[DEFAULT]', uid: 'controlled-owner', isAnonymous: false,
  stsTokenManager: {accessToken: 'private-token', refreshToken: 'private-refresh'}, ...patch});}

test('Safari packaged observer selects exact LOCAL identity and never stale IndexedDB', async () => {
  const d = driverWithLocal(local());
  assert.deepEqual(JSON.parse(JSON.stringify(await authIdentity(d.driver, key))), {uid: 'controlled-owner', isAnonymous: false});
  assert.equal(d.idbReads(), 0);
});
test('Safari packaged missing LOCAL identity never falls back to an IDB account', async () => {
  const d = driverWithLocal(null); assert.equal(await authIdentity(d.driver, key), null); assert.equal(d.idbReads(), 0);
});
test('Safari packaged observer keeps anonymous reconciliation tokenless and rejects malformed records', async () => {
  const result = await authIdentity(driverWithLocal(local({uid: 'created-anonymous', isAnonymous: true})).driver, key);
  assert.equal(JSON.stringify(result), JSON.stringify({uid: 'created-anonymous', isAnonymous: true}));
  for (const value of ['{private', 'null', '[]', local({apiKey: 'other-key'}), local({appName: 'attendus-public-web'}),
    local({uid: '../foreign'}), local({isAnonymous: 'false'}), 'x'.repeat(65537)]) {
    const rejected = await authIdentity(driverWithLocal(value).driver, key);
    assert.equal(rejected.error, 'auth-storage-invalid'); assert.equal(JSON.stringify(rejected).includes('private'), false);
  }
  assert.equal((await authIdentity(driverWithLocal(null, {denied: true}).driver, key)).error, 'auth-storage-unavailable');
});

const firebase = {apiKey: key, projectId: 'attendus-staging', appId: '1:123:web:fixture', storageBucket: 'attendus-staging.firebasestorage.app'};
const expectedUid = 'controlled-owner';
function sdk() {
  let reads = 0;
  const app = {name: '[DEFAULT]', options: {...firebase}};
  const auth = {app, _isInitialized: true, currentUser: {uid: expectedUid, isAnonymous: false}};
  const provider = {name: 'auth', isInitialized: () => true, getImmediate(options) {assert.deepEqual(JSON.parse(JSON.stringify(options)), {optional: true}); reads++; return auth;}};
  app.container = {getProviders: () => [provider]};
  const context = {firebase_core: {getApps: () => [app]},
    get localStorage() {throw Error('runtime observer must not choose persisted records');},
    get indexedDB() {throw Error('runtime observer must not choose persisted records');}};
  context.options = {firebase, expectedUid};
  const read = () => vm.runInNewContext(`(${initializedAuthIdentity.toString()})(options)`, context);
  return {app, auth, provider, context, read, reads: () => reads};
}
test('cache predecessor reads the exact already-initialized SDK user, independent of storage backend', () => {
  const s = sdk(); assert.equal(JSON.stringify(s.read()), JSON.stringify({uid: expectedUid, isAnonymous: false})); assert.equal(s.reads(), 1);
  s.context.firebase_core.getApps = () => [{name: 'attendus-public-web', options: {projectId: 'foreign'}}, s.app];
  assert.equal(s.read().uid, expectedUid);
  s.context.firebase_core.getApps = () => [{name: '[DEFAULT]', _delegate: s.app}];
  assert.equal(s.read().uid, expectedUid);
});
test('cache observer waits for existing auth initialization/restoration without initializing a provider', () => {
  const s = sdk(); s.provider.isInitialized = () => false;
  assert.equal(s.read(), false); assert.equal(s.reads(), 0);
  s.provider.isInitialized = () => true; s.auth._isInitialized = false;
  assert.equal(s.read(), false);
  s.auth._isInitialized = true; s.auth.currentUser = null; assert.equal(s.read(), false);
  s.app.container.getProviders = () => []; assert.equal(s.read(), false);
});
test('cache observer rejects foreign, anonymous, ambiguous and unsupported active identities', () => {
  for (const change of [s => {s.app.options.apiKey = 'foreign';}, s => {s.app.options.projectId = 'orgami-66nxok';},
    s => {s.app.options.appId = 'foreign';}, s => {s.app.options.storageBucket = 'foreign';},
    s => {s.auth.currentUser.uid = 'foreign';}, s => {s.auth.currentUser.isAnonymous = true;},
    s => {s.context.firebase_core.getApps = () => [s.app, s.app];}, s => {s.app.container = {};},
    s => {s.app.container.getProviders = () => [s.provider, s.provider];},
    s => {s.auth.app = {name: 'attendus-public-web', options: firebase};}]) {
    const s = sdk(); change(s); assert.throws(s.read, /Cache/);
  }
});
test('cache page observer has bounded read-only initialization settling and releases its handle', async () => {
  const s = sdk(); let disposed = false, waits = 0;
  s.auth._isInitialized = false;
  const page = {async waitForFunction(fn, args, options) {
    waits++; assert.equal(fn, initializedAuthIdentity); assert.deepEqual(args, {firebase, expectedUid});
    assert.deepEqual(options, {timeout: 10000, polling: 100}); assert.equal(s.read(), false);
    s.auth._isInitialized = true;
    return {jsonValue: async () => JSON.parse(JSON.stringify(s.read())), dispose: async () => {disposed = true;}};
  }, evaluate() {throw Error('predecessor must not assume LOCAL');}};
  assert.deepEqual(await readCacheAuthIdentity(page, firebase, expectedUid, false), {uid: expectedUid, isAnonymous: false});
  assert.equal(disposed, true); assert.equal(waits, 1);
  await assert.rejects(readCacheAuthIdentity({waitForFunction: async () => {throw Error('secret-provider-detail');}}, firebase, expectedUid, false),
    error => !error.message.includes('secret-provider-detail') && /could not be verified/.test(error.message));
});
test('cache candidate must also pass exact LOCAL JWT binding and cannot use an older IDB identity', async () => {
  const now = Math.floor(Date.now() / 1000), claims = {aud: firebase.projectId, iss: `https://securetoken.google.com/${firebase.projectId}`,
    sub: expectedUid, user_id: expectedUid, iat: now - 1, exp: now + 3600, firebase: {sign_in_provider: 'password'}};
  const token = [{alg: 'RS256'}, claims].map(x => Buffer.from(JSON.stringify(x)).toString('base64url')).join('.') + '.c2lnbmF0dXJl';
  let value = local({stsTokenManager: {accessToken: token}}), disposed = 0;
  const page = {waitForFunction: async () => ({jsonValue: async () => ({uid: expectedUid, isAnonymous: false}), dispose: async () => {disposed++;}}),
    evaluate: async (fn, options) => vm.runInNewContext(`(${fn.toString()})(options)`, {options, Date, Uint8Array, TextDecoder, atob,
      localStorage: {getItem(k) {assert.equal(k, storageKey); return value;}}, get indexedDB() {throw Error('No fallback');}})};
  assert.equal((await readCacheAuthIdentity(page, firebase, expectedUid, true)).uid, expectedUid);
  value = local({uid: 'foreign'});
  await assert.rejects(readCacheAuthIdentity(page, firebase, expectedUid, true), /could not be verified/);
  assert.equal(disposed, 2);
});
test('actual installed Firebase Auth provider is inspected without initializing another app or obtaining a token', async () => {
  const {createRequire} = require('node:module'), path = require('node:path');
  const deps = createRequire(path.resolve(__dirname, '../../functions/package.json'));
  const {initializeApp, deleteApp} = deps('@firebase/app');
  const {initializeAuth, inMemoryPersistence} = deps('@firebase/auth');
  const app = initializeApp(firebase), previousFetch = global.fetch;
  let networkCalls = 0;
  global.fetch = () => {networkCalls++; throw Error('No network allowed');};
  try {
    const auth = initializeAuth(app, {persistence: inMemoryPersistence});
    await auth._initializationPromise;
    const run = () => vm.runInNewContext(`(${initializedAuthIdentity.toString()})(options)`, {options: {firebase, expectedUid}, firebase_core: {getApps: () => [app]}});
    assert.equal(run(), false);
    auth.currentUser = {uid: expectedUid, isAnonymous: false, getIdToken() {throw Error('Token fetch prohibited');}};
    assert.equal(run().uid, expectedUid);
    assert.equal(networkCalls, 0);
  } finally {await deleteApp(app); global.fetch = previousFetch;}
});
