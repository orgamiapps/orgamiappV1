'use strict';
const test = require('node:test'), assert = require('node:assert/strict'), vm = require('node:vm');
const {createAppCheckTestMode: create} = require('../../tools/web_release_producers/appcheck-test-mode');
// Synthetic UUID4, never generated/registered/exchanged with any service.
const TOKEN = '01234567-89ab-4cde-8fab-0123456789ab';
const ENV = 'STAGING_APPCHECK_DEBUG_TOKEN';
const appId = '1:925344893088:web:3be71e809ba516e1d021c5';
const stage = 'https://attendus-staging.web.app';
const candidate = {environment: 'staging', projectId: 'attendus-staging', sourceSha: 'a'.repeat(40),
  candidateRunId: '37240000000', webSha256: 'b'.repeat(64)};
const fixture = {projectId: candidate.projectId, sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId,
  runId: 'synthetic-test-fixture', firebase: {projectId: candidate.projectId, projectNumber: '925344893088', appId, apiKey: 'synthetic_public_key'}};
const resource = `projects/925344893088/apps/${appId}/debugTokens/synthetic-resource-id`;
const capturePolicy = {rawConsole: false, trace: false, har: false, storageState: false};
const options = (patch = {}) => ({candidate: structuredClone(candidate), fixture: structuredClone(fixture), env: {}, ...patch});
const debug = (patch = {}) => create(options({mode: 'staging-debug-functional', env: {[ENV]: TOKEN}, registeredResource: resource, ...patch}));
const endpoint = (host = 'content-firebaseappcheck.googleapis.com', path = `/v1/projects/attendus-staging/apps/${appId}:exchangeDebugToken`) =>
  `https://${host}${path}?key=${fixture.firebase.apiKey}`;
const body = JSON.stringify({debug_token: TOKEN});
function context({pages = [], reject = false} = {}) {
  const scripts = [];
  return {scripts, pages: () => pages, async addInitScript(fn, arg) {scripts.push({fn, arg}); if (reject) throw Error(TOKEN);}};
}
function document(script, {origin = stage, child = false, worker = false, existing, methods = {}} = {}) {
  const messages = [], receiver = [];
  const console = {};
  for (const method of ['log', 'info', 'warn', 'error', 'debug']) console[method] = methods[method] || function(...args) {
    receiver.push(this); messages.push(args); return 'original-console-result';
  };
  const realm = {location: {origin}, console}; realm.self = realm; realm.top = child ? {} : realm;
  if (!worker) realm.document = {};
  if (existing !== undefined) realm.FIREBASE_APPCHECK_DEBUG_TOKEN = existing;
  vm.createContext(realm);
  const run = () => vm.runInContext(`(${script.fn.toString()})(${JSON.stringify(script.arg)})`, realm);
  return {realm, messages, receiver, run};
}
function proof(origin = 'http://localhost:8123') {
  return {schemaVersion: 1, verified: true, origin, sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId,
    currentWebSha256: candidate.webSha256, predecessorWebSha256: 'c'.repeat(64), proofSha256: 'd'.repeat(64),
    verifiedAt: '2026-10-04T12:00:00.000Z',
    current: {projectId: fixture.projectId, projectNumber: fixture.firebase.projectNumber, appId, runtimeVerified: true, messagingWorkerVerified: true},
    predecessor: {projectId: fixture.projectId, projectNumber: fixture.firebase.projectNumber, appId, runtimeVerified: true, messagingWorkerVerified: true}};
}

test('default real mode is inert and never claims successful attestation', async () => {
  const mode = create(options()); const c = context();
  assert.equal(await mode.install(c), mode.metadata); assert.equal(c.scripts.length, 0);
  assert.equal(mode.metadata.mode, 'real'); assert.equal(mode.metadata.realProviderAttestation, 'unverified');
  assert.equal(mode.metadata.qualifiesCandidate, false); assert.equal(mode.allowsDebugRequest(endpoint(), 'POST', body), false);
  assert.equal(mode.allowsDebugRequest(endpoint().replace('exchangeDebugToken', 'exchangeRecaptchaEnterpriseToken'), 'POST', '{}'), false);
});
test('unexpected secret in real mode, unsupported modes and stray resource fail without disclosure', () => {
  for (const opts of [{env: {[ENV]: TOKEN}}, {env: {[ENV]: ''}}, {mode: 'debug', env: {[ENV]: TOKEN}}, {registeredResource: resource}]) {
    assert.throws(() => create(options(opts)), (error) => !error.message.includes(TOKEN) && /App Check test mode:/.test(error.message));
  }
});
test('production, foreign app/project, mismatched source/run and emulator fail before secret resolution', () => {
  const cases = [
    {candidate: {...candidate, environment: 'production'}}, {candidate: {...candidate, projectId: 'orgami-66nxok'}},
    {fixture: {...fixture, projectId: 'orgami-66nxok'}}, {fixture: {...fixture, sourceSha: 'c'.repeat(40)}},
    {fixture: {...fixture, candidateRunId: '999'}}, {fixture: {...fixture, firebase: {...fixture.firebase, projectId: 'other'}}},
    {fixture: {...fixture, firebase: {...fixture.firebase, appId: '1:925344893088:web:other'}}},
    {fixture: {...fixture, firebase: {...fixture.firebase, projectNumber: '1'}}},
    {fixture: {...fixture, useEmulator: true}}, {candidate: {...candidate, webSha256: 'invalid'}},
    {candidate: {...candidate, candidateRunId: 37240000000}}, {candidate: {...candidate, sourceSha: candidate.sourceSha + '\n'}},
    {fixture: {...fixture, firebase: {...fixture.firebase, apiKey: fixture.firebase.apiKey + '\n'}}},
  ];
  for (const item of cases) {
    let reads = 0; const env = {get [ENV]() {reads++; return TOKEN;}};
    assert.throws(() => debug({...item, env})); assert.equal(reads, 0);
  }
  for (const name of ['FIREBASE_AUTH_EMULATOR_HOST', 'FIRESTORE_EMULATOR_HOST', 'FIREBASE_DATABASE_EMULATOR_HOST', 'FIREBASE_STORAGE_EMULATOR_HOST', 'FIREBASE_EMULATOR_HUB']) {
    let reads = 0;
    assert.throws(() => debug({env: {[name]: 'localhost:9000', get [ENV]() {reads++; return TOKEN;}}}), /emulator_unsupported/);
    assert.equal(reads, 0);
  }
});
test('native Safari and unsupported drivers fail before reading the secret or touching a browser', () => {
  for (const patch of [{producer: 'safari'}, {producer: 'backend'}, {producer: 'operations'}, {producer: 'anything'},
    {driver: 'safaridriver'}, {driver: 'webdriver'}]) {
    let reads = 0; assert.throws(() => debug({...patch, env: {get [ENV]() {reads++; return TOKEN;}}}), /debug_driver_unsupported/);
    assert.equal(reads, 0);
  }
});
test('debug requires a private string UUID4 and separate exact registered resource identity', () => {
  for (const token of [undefined, null, true, '', ' ', ` ${TOKEN}`, TOKEN + '\n', TOKEN.replace('-4cde-', '-3cde-'), TOKEN.replace('-8fab-', '-7fab-')]) {
    assert.throws(() => debug({env: {[ENV]: token}}), /invalid_debug_secret/);
  }
  for (const name of [undefined, '', `projects/other/apps/${appId}/debugTokens/id`, resource + '/extra', resource + '?x=1', resource + '\n',
    resource.replace('synthetic-resource-id', TOKEN), resource.replace('synthetic-resource-id', TOKEN.toUpperCase())]) {
    assert.throws(() => debug({registeredResource: name}), /invalid_registered_resource/);
  }
  assert.equal(debug({env: {[ENV]: TOKEN.toUpperCase()}}).metadata.mode, 'staging-debug-functional');
  assert.throws(() => debug({env: {get [ENV]() {throw Error(TOKEN);}}}), (error) => error.message.endsWith('secret_environment_unavailable') && !error.stack.includes(TOKEN));
  assert.throws(() => debug({registeredResource: resource.replace('synthetic-resource-id', Buffer.from(TOKEN).toString('hex'))}), /secret_in_publication/);
});
test('debug metadata contains configuration identity, never secret or API key', () => {
  const mode = debug(), serialized = JSON.stringify(mode);
  assert.equal(serialized.includes(TOKEN), false); assert.equal(serialized.includes(fixture.firebase.apiKey), false);
  assert.equal(mode.metadata.registeredResource, resource); assert.equal(mode.metadata.realProviderAttestation, 'unverified');
  assert.equal(Object.isFrozen(mode), true); assert.equal(Object.isFrozen(mode.metadata), true);
});
test('install uses awaited context init script before pages, once only, with explicit safe capture declaration', async () => {
  const mode = debug(); const c = context();
  await mode.install(c, {capturePolicy}); assert.equal(c.scripts.length, 1);
  assert.equal(c.scripts[0].arg.token, TOKEN); assert.equal(c.scripts[0].arg.origin, stage);
  await assert.rejects(mode.install(c, {capturePolicy}), /invalid_or_reused_context/);
  await assert.rejects(debug().install(context({pages: [{}]}), {capturePolicy}), /document_initializer_failed/);
  for (const field of Object.keys(capturePolicy)) {
    const c2 = context(); await assert.rejects(debug().install(c2, {capturePolicy: {...capturePolicy, [field]: true}}), /unsafe_capture_policy/);
    assert.equal(c2.scripts.length, 0);
  }
  await assert.rejects(debug().install(context()), /unsafe_capture_policy/);
});
test('init-script transport failure is sanitized and context cannot be reused', async () => {
  const mode = debug(), c = context({reject: true});
  await assert.rejects(mode.install(c, {capturePolicy}), (error) => error.message.endsWith('document_initializer_failed') && !error.stack.includes(TOKEN));
  await assert.rejects(mode.install(c, {capturePolicy}), /invalid_or_reused_context/);
});
test('serialized initializer injects string only in top-level exact staging document', async () => {
  const c = context(); await debug().install(c, {capturePolicy});
  const main = document(c.scripts[0]); main.run(); assert.equal(main.realm.FIREBASE_APPCHECK_DEBUG_TOKEN, TOKEN);
  for (const settings of [{child: true}, {origin: 'https://attendus-staging.firebaseapp.com'}, {origin: stage + '.evil.test'},
    {origin: 'https://www.google.com'}, {origin: 'https://orgami-66nxok.web.app'}, {origin: 'null'}]) {
    const other = document(c.scripts[0], settings); other.run(); assert.equal(other.realm.FIREBASE_APPCHECK_DEBUG_TOKEN, undefined);
  }
  for (const settings of [{worker: true}, {existing: true}, {existing: TOKEN}, {existing: 'foreign'}]) {
    const other = document(c.scripts[0], settings); assert.throws(other.run, /document_not_fresh/);
  }
});
test('known unconditional SDK11/12 console line is redacted before console capture, preserving other arguments and receiver', async () => {
  const c = context(); const mode = debug(); await mode.install(c, {capturePolicy});
  const page = document(c.scripts[0]); page.run(); const marker = {unrelated: true};
  // Exact string shape source-confirmed in both official CDN modules. No logger
  // setting suppresses it; this checks the known leak at the actual console sink.
  const result = page.realm.console.log(`App Check debug token: ${TOKEN}. You will need to add it to your app's App Check settings in the Firebase console for it to work.`, marker);
  assert.equal(result, 'original-console-result'); assert.equal(page.messages[0][1], marker);
  assert.equal(page.receiver[0], page.realm.console); assert.equal(JSON.stringify(page.messages).includes(TOKEN), false);
  assert.match(page.messages[0][0], /REDACTED_APPCHECK_DEBUG_TOKEN/);
  assert.equal(page.realm.console.warn('ordinary message'), 'original-console-result');
  assert.deepEqual(page.messages[1], ['ordinary message']);
  assert.equal(mode.assertPublishable(JSON.stringify(page.messages)), true);
});
test('console original throws unchanged and failed preparation never exposes the global', async () => {
  const c = context(); await debug().install(c, {capturePolicy}); const sentinel = new Error('sentinel');
  const page = document(c.scripts[0], {methods: {log() {throw sentinel;}}}); page.run();
  assert.throws(() => page.realm.console.log('ordinary'), (error) => error === sentinel);
  const absent = document(c.scripts[0]); absent.realm.console = null;
  assert.throws(absent.run, /console_unavailable/); assert.equal(absent.realm.FIREBASE_APPCHECK_DEBUG_TOKEN, undefined);
  const frozen = document(c.scripts[0]); Object.freeze(frozen.realm.console);
  assert.throws(frozen.run, /console_not_writable/); assert.equal(frozen.realm.FIREBASE_APPCHECK_DEBUG_TOKEN, undefined);
});
test('localhost requires exact already-verified current/predecessor project/app/worker provenance', async () => {
  const p = proof(); const c = context(); await debug().install(c, {origin: p.origin, cacheProof: p, capturePolicy});
  const page = document(c.scripts[0], {origin: p.origin}); page.run(); assert.equal(page.realm.FIREBASE_APPCHECK_DEBUG_TOKEN, TOKEN);
  const wrongPort = document(c.scripts[0], {origin: 'http://localhost:8124'}); wrongPort.run(); assert.equal(wrongPort.realm.FIREBASE_APPCHECK_DEBUG_TOKEN, undefined);
  for (const bad of [null, {...p, verified: false}, {...p, origin: 'http://localhost:8124'}, {...p, sourceSha: 'f'.repeat(40)},
    {...p, candidateRunId: '1'}, {...p, currentWebSha256: 'f'.repeat(64)}, {...p, proofSha256: ''}, {...p, verifiedAt: 'bad'},
    {...p, current: {...p.current, runtimeVerified: false}}, {...p, predecessor: {...p.predecessor, appId: 'foreign'}},
    {...p, predecessor: {...p.predecessor, messagingWorkerVerified: false}}]) {
    const fresh = context(); await assert.rejects(debug().install(fresh, {origin: p.origin, cacheProof: bad, capturePolicy}), /unverified_document_origin/);
    assert.equal(fresh.scripts.length, 0);
  }
  for (const origin of ['http://localhost', 'http://localhost:80', 'http://localhost:8123/path', 'http://localhost:8123?x=1',
    'http://127.0.0.1:8123', 'http://localhost.evil.test:8123', 'https://localhost:8123', 'https://other.web.app']) {
    await assert.rejects(debug().install(context(), {origin, cacheProof: proof(origin), capturePolicy}), /unverified_document_origin/);
  }
});
test('actual SDK11/12 sole debug_token POST matches both AppCheck hosts and project aliases', () => {
  const mode = debug();
  for (const host of ['content-firebaseappcheck.googleapis.com', 'firebaseappcheck.googleapis.com']) {
    for (const project of [fixture.projectId, fixture.firebase.projectNumber]) {
      for (const app of [appId, encodeURIComponent(appId)]) {
        const url = endpoint(host, `/v1/projects/${project}/apps/${app}:exchangeDebugToken`);
        assert.equal(mode.allowsDebugRequest(url, 'POST', body), true);
        assert.equal(mode.allowsDebugRequest(url, 'OPTIONS', null), true);
      }
    }
  }
  assert.equal(mode.allowsDebugRequest(endpoint(), 'POST', ` { "debug_token" : "${TOKEN}" } `), true);
});
test('debug request boundary rejects foreign identity, methods, path, query and credentials', () => {
  const mode = debug();
  const badUrls = [endpoint().replace('https:', 'http:'), endpoint().replace('.googleapis.com', '.googleapis.com.evil.test'),
    endpoint().replace('attendus-staging/apps', 'production/apps'), endpoint().replace(appId, 'different-app'),
    endpoint().replace('exchangeDebugToken', 'exchangeRecaptchaEnterpriseToken'), endpoint().replace('/v1/', '/v1beta/'),
    endpoint().replace('?key=', '?key=foreign&extra='), endpoint() + '&key=' + fixture.firebase.apiKey,
    endpoint() + '&extra=1', endpoint() + '#secret', endpoint().replace('https://', 'https://user:pass@'),
    endpoint().replace('.com/', '.com:8443/'), 'not-a-url'];
  for (const url of badUrls) assert.equal(mode.allowsDebugRequest(url, 'POST', body), false, url);
  for (const method of ['GET', 'DELETE', 'PATCH', 'post', 'HEAD']) assert.equal(mode.allowsDebugRequest(endpoint(), method, body), false);
  assert.equal(mode.allowsDebugRequest(endpoint(), 'OPTIONS', body), false);
});
test('debug request body is exact and never admits duplicate keys, other tokens or extras', () => {
  const mode = debug();
  for (const raw of [undefined, null, {}, '{}', '[]', body + ' trailing', body.replace(TOKEN, TOKEN.toUpperCase()),
    JSON.stringify({debug_token: TOKEN, extra: true}), JSON.stringify({debugToken: TOKEN}),
    `{"debug_token":"${TOKEN}","debug_token":"${TOKEN}"}`, JSON.stringify({debug_token: true}),
    JSON.stringify({debug_token: TOKEN + ' '}), ' '.repeat(300) + body]) {
    assert.equal(mode.allowsDebugRequest(endpoint(), 'POST', raw), false);
  }
});
test('publication guard and redactor cover known raw, URL, JSON and base64 token representations', () => {
  const mode = debug();
  const encode = (value) => [...value].map((c) => '%' + c.charCodeAt(0).toString(16)).join('');
  const forms = [TOKEN, TOKEN.toUpperCase(), body, `https://example.test/${TOKEN}`, TOKEN.replaceAll('-', '%2d'),
    encode(TOKEN), encode(TOKEN.toUpperCase()), encode(TOKEN).replaceAll('%', '%25'),
    [...TOKEN].map((c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0')).join(''),
    [...TOKEN.toUpperCase()].map((c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0')).join(''),
    Buffer.from(TOKEN).toString('base64'), Buffer.from(TOKEN).toString('base64url'), Buffer.from(TOKEN).toString('hex')];
  for (const form of forms) {
    for (const bytes of [form, Buffer.from(form), new Uint8Array(Buffer.from(form))]) {
      assert.throws(() => mode.assertPublishable(bytes), (error) => error.message.endsWith('secret_in_publication') && !error.stack.includes(TOKEN));
      assert.equal(mode.assertPublishable(mode.redact(bytes)), true);
    }
  }
  assert.equal(mode.assertPublishable(JSON.stringify(mode.metadata)), true);
  assert.equal(mode.redact('ordinary evidence'), 'ordinary evidence');
  assert.throws(() => mode.assertPublishable({token: TOKEN}), /publication_bytes_required/);
});
test('caller-owned identity mutations cannot broaden the bound request after creation', () => {
  const f = structuredClone(fixture); const mode = debug({fixture: f}); f.firebase.apiKey = 'foreign_public_key';
  assert.equal(mode.allowsDebugRequest(endpoint(), 'POST', body), true);
  assert.equal(mode.allowsDebugRequest(endpoint().replace(fixture.firebase.apiKey, f.firebase.apiKey), 'POST', body), false);
});
