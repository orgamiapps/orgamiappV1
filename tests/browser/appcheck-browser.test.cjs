'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const {createAppCheckTestMode} = require('../../tools/web_release_producers/appcheck-test-mode');
const {createBrowserAppCheckIntegration: integrate, allowStagingRequest, createPageErrorRecorder, scrubBrowserError} =
  require('../../tools/web_release_producers/browser')._test;
const TOKEN = '01234567-89ab-4cde-8fab-0123456789ab'; // Synthetic, unregistered.
const candidate = {environment: 'staging', projectId: 'attendus-staging', sourceSha: 'a'.repeat(40),
  candidateRunId: '37240000000', webSha256: 'b'.repeat(64), webFiles: {'main.dart.js': 'c'.repeat(64)}};
const fixture = {projectId: candidate.projectId, sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId,
  runId: 'synthetic-browser-fixture', firebase: {projectId: candidate.projectId, projectNumber: '925344893088',
    appId: '1:925344893088:web:3be71e809ba516e1d021c5', apiKey: 'synthetic_public_key'}};
const baseUrl = 'https://attendus-staging.web.app';
function controller() {
  return createAppCheckTestMode({candidate, fixture, mode: 'staging-debug-functional',
    env: {STAGING_APPCHECK_DEBUG_TOKEN: TOKEN},
    registeredResource: `projects/925344893088/apps/${fixture.firebase.appId}/debugTokens/synthetic-registration`});
}
function setup(value = controller()) {
  const context = {baseUrl, projectId: candidate.projectId, fixture, ...(value ? {appCheckTestMode: value} : {})};
  return {context, mode: integrate({candidate, context})};
}
const debugUrl = `https://content-firebaseappcheck.googleapis.com/v1/projects/attendus-staging/apps/${fixture.firebase.appId}:exchangeDebugToken?key=${fixture.firebase.apiKey}`;
function request({url = debugUrl, method = 'POST', body = JSON.stringify({debug_token: TOKEN}), worker = null,
  frame = {parentFrame: () => null, url: () => baseUrl + '/app/discover'}, noFrame = false} = {}) {
  return {url: () => url, method: () => method, postData: () => body, serviceWorker: () => worker, allHeaders: async () => ({}),
    frame: () => {if (noFrame) throw Error('no frame'); return frame;}};
}
function engine() {
  const calls = [], contexts = [];
  return {calls, contexts, async newContext(options) {
    calls.push(options); const events = [];
    const ctx = {events, handlers: {}, pages: () => [], addInitScript: async (fn, arg) => {events.push({kind: 'init', fn, arg});},
      route: async (pattern, callback) => {ctx.routeHandler = callback;},
      routeWebSocket: async (pattern, callback) => {ctx.socketHandler = callback;},
      on: (event, callback) => {ctx.handlers[event] = callback;},
      newPage: async () => {events.push({kind: 'page'}); return {};}, close: async () => {events.push({kind: 'close'});}};
    contexts.push(ctx); return ctx;
  }};
}
const createContext = (mode, e, options, hooks = {}) => mode.newContext(e, options,
  {contextId: 1, blocked: [], onAppCheckToken: () => {}, ...hooks});

test('undefined controller preserves real context options and Enterprise network behavior', async () => {
  const {mode, context} = setup(null), e = engine(), options = {viewport: {width: 390, height: 844}, serviceWorkers: 'allow'};
  const c = await createContext(mode, e, options); assert.deepEqual(e.calls, [options]); assert.deepEqual(c.events, []);
  const enterprise = debugUrl.replace('exchangeDebugToken', 'exchangeRecaptchaEnterpriseToken');
  assert.equal(allowStagingRequest(enterprise, 'POST', context), true);
  assert.equal(mode.requestAllowed(request({url: enterprise}), {}), true);
  assert.equal(mode.requestAllowed(request(), {}), false);
  assert.doesNotThrow(() => mode.requireCacheSupport());
  const error = new Error('real error'); assert.equal(mode.sanitizedError(error), error);
  assert.equal(mode.snapshot().configuration.mode, 'real'); assert.equal(mode.snapshot().configuration.realProviderAttestation, 'unverified');
});
test('explicit real helper remains inert and does not inject', async () => {
  const {mode} = setup(createAppCheckTestMode({candidate, fixture, env: {}})), e = engine();
  const c = await createContext(mode, e, {serviceWorkers: 'block'});
  assert.deepEqual(c.events, []); assert.equal(e.calls[0].serviceWorkers, 'block');
});
test('diagnostic controller identity and unsupported mode fail before browser creation', () => {
  const base = controller();
  for (const patch of [{mode: 'debug'}, {projectId: 'production'}, {appId: 'other'}, {sourceSha: 'd'.repeat(40)},
    {candidateRunId: '1'}, {fixtureRunId: 'other-fixture'}]) {
    assert.throws(() => setup({...base, metadata: {...base.metadata, ...patch}}), /does not match/);
  }
  assert.throws(() => setup({...base, install: null}), /does not match/);
});
test('every engine/viewport debug context blocks service workers and installs before its first page', async () => {
  const {mode} = setup();
  for (const width of [320, 390, 1440]) for (const name of ['chromium', 'firefox', 'webkit', 'chrome', 'edge']) {
    const e = engine(), c = await createContext(mode, e, {viewport: {width, height: 900}, serviceWorkers: 'allow'});
    await c.newPage(); assert.equal(e.calls[0].serviceWorkers, 'block', name);
    assert.deepEqual(c.events.map((entry) => entry.kind), ['init', 'page']);
    assert.equal(c.events[0].arg.origin, baseUrl); assert.equal(c.events[0].arg.token, TOKEN);
  }
});
test('debug HAR/storage state options are rejected before context construction', async () => {
  const {mode} = setup(); const e = engine();
  for (const option of [{recordHar: {path: 'unsafe.har'}}, {storageState: 'unsafe.json'}]) {
    await assert.rejects(createContext(mode, e, option), /without HAR or stored state/);
  }
  assert.equal(e.calls.length, 0);
});
test('failed initializer closes the owned context and exposes no secret/raw failure', async () => {
  const base = controller(); const {mode} = setup({...base, install: async () => {throw Error(TOKEN);}}); const e = engine();
  await assert.rejects(createContext(mode, e, {}), (error) => /before page creation/.test(error.message) && !error.stack.includes(TOKEN));
  assert.deepEqual(e.contexts[0].events.map((entry) => entry.kind), ['close']);
});
test('debug AppCheck hosts exclusively accept exact debug exchange; Enterprise cannot use fallback', () => {
  const {mode, context} = setup();
  assert.equal(mode.requestAllowed(request(), {}), true);
  assert.equal(mode.requestAllowed(request({method: 'OPTIONS', body: null}), {}), true);
  for (const host of ['content-firebaseappcheck.googleapis.com', 'firebaseappcheck.googleapis.com']) {
    const enterprise = debugUrl.replace('content-firebaseappcheck.googleapis.com', host).replace('exchangeDebugToken', 'exchangeRecaptchaEnterpriseToken');
    assert.equal(allowStagingRequest(enterprise, 'POST', context), true);
    assert.equal(mode.requestAllowed(request({url: enterprise}), {}), false);
  }
  for (const r of [request({body: JSON.stringify({debug_token: 'foreign'})}), request({url: debugUrl + '&extra=1'}),
    request({url: debugUrl.replace('attendus-staging/apps', 'production/apps')}), request({url: debugUrl.replace('https:', 'http:')})]) {
    assert.equal(mode.requestAllowed(r, {}), false);
  }
  // Provider initialization still loads resources in both actual SDK versions;
  // only the AppCheck exchange endpoint changes, not the static resource policy.
  const resource = 'https://www.google.com/recaptcha/enterprise.js';
  assert.equal(mode.requestAllowed(request({url: resource, method: 'GET', body: null}), {}), allowStagingRequest(resource, 'GET', context));
});
test('AppCheck service-worker, absent-frame and child/foreign-frame requests fail closed', () => {
  const {mode} = setup();
  for (const r of [request({worker: {}}), request({noFrame: true}), request({frame: null}),
    request({frame: {parentFrame: () => ({}), url: () => baseUrl}}),
    request({frame: {parentFrame: () => null, url: () => 'https://www.google.com'}})]) {
    assert.equal(mode.requestAllowed(r, {}), false);
  }
});
test('debug errors are redacted before both message scrub and structured frame recorder', () => {
  const {mode, context} = setup(); const original = new Error(`App Check debug token: ${TOKEN}`);
  original.stack = `Error: ${TOKEN}\n    at method (${baseUrl}/main.dart.js?debug=${TOKEN}:12:3)`;
  const safe = mode.sanitizedError(original); const recorder = createPageErrorRecorder({candidate, context});
  recorder.record(safe, {errorIndex: 0, contextId: 1, pageId: 1, pageRole: 'owner', engine: 'chromium', pageUrl: baseUrl});
  const output = JSON.stringify({message: scrubBrowserError(safe, fixture), diagnostic: recorder.snapshot()});
  assert.equal(output.includes(TOKEN), false); assert.match(output, /REDACTED_APPCHECK_DEBUG_TOKEN/);
  assert.equal(recorder.snapshot().entries[0].frames[0].artifact, 'main.dart.js');
  assert.equal(original.message.includes(TOKEN), true);
});
test('exchange observations retain status/method/time/context only and never inspect response bodies', () => {
  const {mode} = setup();
  const response = {request: () => request(), status: () => 403,
    body: () => {throw Error('must not read');}, json: () => {throw Error('must not read');}};
  mode.observe(response, 1); mode.observe({...response, status: () => 200}, 2);
  mode.observe({...response, request: () => request({url: debugUrl.replace('exchangeDebugToken', 'exchangeRecaptchaEnterpriseToken')})}, 1);
  mode.observe({...response, request: () => request({worker: {}})}, 1);
  mode.observe({...response, status: () => 0}, 1);
  const report = mode.snapshot(); assert.equal(report.totalCount, 2);
  assert.deepEqual(report.observations.map((entry) => entry.contextId), [1, 2]);
  assert.deepEqual(report.observations.map((entry) => entry.httpStatus), [403, 200]);
  assert.deepEqual(Object.keys(report.observations[0]).sort(), ['at', 'contextId', 'httpStatus', 'method', 'sequence']);
  assert.equal(Number.isFinite(Date.parse(report.observations[0].at)), true);
  assert.equal(JSON.stringify(report).includes(TOKEN), false); assert.equal(JSON.stringify(report).includes('synthetic_public_key'), false);
  assert.equal(report.configuration.realProviderAttestation, 'unverified'); assert.equal(report.configuration.qualifiesCandidate, false);
  report.observations.length = 0; assert.equal(mode.snapshot().observations.length, 2);
});
test('observation cap keeps omitted count and cache remains explicitly unsupported', () => {
  const {mode} = setup(); const r = {request: () => request(), status: () => 200};
  for (let i = 0; i < 203; i++) mode.observe(r, 1);
  assert.equal(mode.snapshot().observations.length, 200); assert.equal(mode.snapshot().omittedCount, 3);
  assert.throws(() => mode.requireCacheSupport(), /cannot qualify cache upgrade/);
});
test('actual context route and response hooks enforce the debug predicate and retain safe observations', async () => {
  const {mode} = setup(), e = engine(), blocked = [], statuses = []; let forwardedToken = null;
  const c = await createContext(mode, e, {}, {contextId: 7, blocked, onAppCheckToken: (token) => {forwardedToken = token;}});
  assert.equal(c.events[0].kind, 'init');
  const invoke = async (r) => c.routeHandler({request: () => r,
    abort: async (reason) => {statuses.push(reason);}, continue: async () => {statuses.push('forwarded');}});
  await invoke(request());
  await invoke(request({url: debugUrl.replace('exchangeDebugToken', 'exchangeRecaptchaEnterpriseToken')}));
  await invoke(request({worker: {}}));
  const business = request({url: 'https://us-central1-attendus-staging.cloudfunctions.net/fixture-read'});
  business.allHeaders = async () => ({'x-firebase-appcheck': 'synthetic-issued-appcheck-token'});
  await invoke(business); assert.equal(forwardedToken, 'synthetic-issued-appcheck-token');
  assert.deepEqual(statuses, ['forwarded', 'blockedbyclient', 'blockedbyclient', 'forwarded']);
  c.handlers.response({request: () => request(), status: () => 200});
  assert.equal(mode.snapshot().observations[0].contextId, 7);
  let closed = false; c.socketHandler({url: () => 'wss://example.test/path', close: () => {closed = true;}});
  assert.equal(closed, true); assert.equal(blocked.length, 3);
  assert.equal(JSON.stringify({blocked, snapshot: mode.snapshot()}).includes(TOKEN), false);
  assert.equal(c.handlers.console, undefined); // No raw console capture hook.
});
