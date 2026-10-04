'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {artifactPath, verifyTree, verifyFirebaseApps, verifyMessagingWorker} = require('../../tools/web_release_producers/browser-cache-upgrade')._test;
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');
const {files} = require('../../tools/web_release_contract');
const {validateFixture, allowStagingRequest, scrubBrowserError, pageErrorDiagnostic, createPageErrorRecorder, projectAppCheckError, readAppCheckFailure, createAppCheckErrorRecorder, parseCsv, signedFixtureUrl, createdAnonymousUid, requirePassingBrowserJourneys, preflightBrandedBrowsers, readOwnedHistoryTitles, visibleHistoryTitle} = require('../../tools/web_release_producers/browser')._test;
const {bindingId} = require('../../functions/communications/qualification-isolation');
test('browser and Safari use the same insertion-aware computed text scaling and control-boundary probe', () => {
  assert.equal(require('../../tools/web_release_producers/browser')._test.htmlResponsiveProbe,
    require('../../tools/web_release_producers/safari').htmlResponsiveProbe);
});
function context() {
  const runId = 'qa-browser-20261004';
  const fixture = {runId, controlledRecipientDomain: 'example.test', runStartsAt: '2026-10-04T00:00:00Z',
    eventClosesAt: '2026-10-04T01:00:00Z', ownedFixtureIds: ['owner', 'attendee', 'unauthorized', 'event', 'private', 'second'],
    event: {id: 'event', title: 'Fixture', publicPath: '/event/event'}, privateEventId: 'private', secondEventId: 'second',
    firebase: {projectId: 'attendus-staging', apiKey: 'fixture-key', appId: '1:123:web:fixture', projectNumber: '123', storageBucket: 'attendus-staging.appspot.com'}};
  for (const role of ['owner', 'attendee', 'unauthorized']) fixture[role] = {uid: role, email: `${runId}-${role}@example.test`, password: 'fixture-password'};
  return {projectId: 'attendus-staging', baseUrl: 'https://attendus-staging.web.app', fixture};
}

function appCheckResponse(ctx, {status = 403, body, length, url, method = 'POST', pending = false} = {}) {
  const bytes = Buffer.from(body ?? JSON.stringify({error: {code: 403, status: 'PERMISSION_DENIED'}}));
  let bodyReads = 0;
  return {status: () => status, url: () => url ?? `https://content-firebaseappcheck.googleapis.com/v1/projects/${ctx.fixture.firebase.projectId}/apps/${ctx.fixture.firebase.appId}:exchangeRecaptchaEnterpriseToken?key=${ctx.fixture.firebase.apiKey}`,
    request: () => ({method: () => method}), headerValue: async () => length === undefined ? String(bytes.length) : length,
    body: async () => {bodyReads++; return pending ? new Promise(() => {}) : bytes;}, reads: () => bodyReads};
}

test('App Check diagnostics project only fixed Google codes and allowlisted ErrorInfo reasons', () => {
  const body = JSON.stringify({token: 'PRIVATE_RESPONSE_TOKEN', error: {code: 403, status: 'PERMISSION_DENIED',
    message: 'PRIVATE_MESSAGE?session=PRIVATE_SESSION', details: [
      {'@type': 'type.googleapis.com/google.rpc.ErrorInfo', reason: 'SERVICE_DISABLED', domain: 'googleapis.com', metadata: {consumer: 'PRIVATE_CONSUMER'}},
      {'@type': 'type.googleapis.com/google.rpc.ErrorInfo', reason: 'PRIVATE_UNKNOWN_REASON'},
      {'@type': 'other-type', reason: 'API_KEY_INVALID'},
    ]}});
  const result = projectAppCheckError(403, Buffer.from(body));
  assert.deepEqual(result, {httpStatus: 403, bodyStatus: 'projected', googleCode: 403, googleStatus: 'PERMISSION_DENIED', errorInfoReasons: ['SERVICE_DISABLED'], unrecognizedErrorInfo: true});
  assert.equal(JSON.stringify(result).includes('PRIVATE'), false);
  assert.equal(projectAppCheckError(403, Buffer.from('{bad')).bodyStatus, 'invalid-json');
  assert.equal(projectAppCheckError(403, Buffer.alloc(16385)).bodyStatus, 'too-large');
  assert.equal(projectAppCheckError(403, Buffer.from(JSON.stringify({error: {code: 'PRIVATE', status: 'PRIVATE'}}))).googleStatus, null);
});

test('App Check response reader binds exact endpoint and bounds body length and wait time', async () => {
  const ctx = context();
  for (const patch of [{method: 'GET'}, {status: 200}, {url: 'https://evil.test/anything'},
    {url: `https://firebaseappcheck.googleapis.com/v1/projects/orgami-66nxok/apps/${ctx.fixture.firebase.appId}:exchangeRecaptchaEnterpriseToken?key=${ctx.fixture.firebase.apiKey}`},
    {url: `https://firebaseappcheck.googleapis.com/v1/projects/attendus-staging/apps/${ctx.fixture.firebase.appId}:exchangeDebugToken?key=${ctx.fixture.firebase.apiKey}`}]) {
    const response = appCheckResponse(ctx, patch); assert.equal(await readAppCheckFailure(response, ctx), null); assert.equal(response.reads(), 0);
  }
  for (const [length, expected] of [[null, 'not-read-missing-length'], ['invalid', 'not-read-invalid-length'], ['16385', 'not-read-too-large']]) {
    const response = appCheckResponse(ctx, {length}); assert.equal((await readAppCheckFailure(response, ctx)).bodyStatus, expected); assert.equal(response.reads(), 0);
  }
  assert.equal((await readAppCheckFailure(appCheckResponse(ctx, {pending: true}), ctx, {timeoutMs: 5})).bodyStatus, 'read-timeout');
  const stalledHeaders = appCheckResponse(ctx);
  stalledHeaders.headerValue = () => new Promise(() => {});
  assert.equal((await readAppCheckFailure(stalledHeaders, ctx, {timeoutMs: 5})).bodyStatus, 'read-timeout');
  assert.equal(stalledHeaders.reads(), 0);
  const unavailable = appCheckResponse(ctx);
  unavailable.body = async () => {throw Error('PRIVATE_REQUEST_TOKEN');};
  assert.deepEqual(await readAppCheckFailure(unavailable, ctx), {httpStatus: 403, bodyStatus: 'read-unavailable'});
  const decodedOverflow = appCheckResponse(ctx, {length: '1', body: 'x'.repeat(16385)});
  assert.equal((await readAppCheckFailure(decodedOverflow, ctx)).bodyStatus, 'too-large');
  assert.equal((await readAppCheckFailure(appCheckResponse(ctx), ctx)).googleStatus, 'PERMISSION_DENIED');
});

test('App Check recorder drains pending responses and retains omitted counts without extra requests', async () => {
  const ctx = context(), recorder = createAppCheckErrorRecorder(ctx);
  for (let i = 0; i < 53; i++) recorder.observe(appCheckResponse(ctx));
  await recorder.drain();
  const snapshot = recorder.snapshot();
  assert.equal(snapshot.totalCount, 53); assert.equal(snapshot.omittedCount, 3); assert.equal(snapshot.records.length, 50);
  assert.ok(snapshot.records.every(row => row.httpStatus === 403 && row.googleStatus === 'PERMISSION_DENIED' && Number.isFinite(Date.parse(row.at))));
  assert.equal(JSON.stringify(snapshot).includes(ctx.fixture.firebase.apiKey), false);
  assert.equal(JSON.stringify(snapshot).includes('exchangeRecaptchaEnterpriseToken?'), false);
});

test('page errors retain exact sealed artifact frames and observation context without raw URLs or payloads', () => {
  const c = context(), artifact = 'releases/fixture/main.dart.js', digest = 'a'.repeat(64);
  const candidate = {webFiles: {[artifact]: digest}};
  const error = Object.assign(Error('Null check operator used on a null value'), {stack:
    'Error: bearer/private payload\n' +
    `    at secretFunction (https://attendus-staging.web.app/${artifact}?session=secret#token:123:45)\n` +
    `otherSecret@https://attendus-staging.web.app/${artifact}:124:7\n` +
    '    at privateAccount (https://foreign.example/secret-path?token=secret:1:2)\n' +
    '    at unsafe (https://username:password@attendus-staging.web.app/releases/fixture/main.dart.js:3:4)\n' +
    '    at notSealed (https://attendus-staging.web.app/manage/private-proof:5:6)'});
  const record = pageErrorDiagnostic(error, {candidate, context: c, errorIndex: 5, contextId: 2, pageId: 3,
    pageRole: 'owner', engine: 'webkit', observedDuringStep: {gate: 'browser-auth-guest-organizer', sequence: 6},
    pageUrl: 'https://attendus-staging.web.app/app/event/private-id?session=secret#private', now: 1791129600000});
  assert.deepEqual(record.frames, [{artifact, sha256: digest, line: 123, column: 45}, {artifact, sha256: digest, line: 124, column: 7}]);
  assert.equal(record.nullCheckMessage, true); assert.equal(record.errorIndex, 5);
  assert.equal(record.pageRole, 'owner'); assert.equal(record.contextId, 2); assert.equal(record.pageId, 3);
  assert.equal(record.engine, 'webkit'); assert.equal(record.routeFamily, '/app/event/:id');
  assert.deepEqual(record.observedDuringStep, {gate: 'browser-auth-guest-organizer', sequence: 6});
  assert.equal(record.at, new Date(1791129600000).toISOString());
  for (const privateText of ['secret', 'username', 'password', 'private-id', 'private-proof', 'foreign.example', 'secretFunction']) {
    assert.equal(JSON.stringify(record).includes(privateText), false, privateText);
  }
});

test('page errors bound stacks and reject unsealed scripts, invalid coordinates and arbitrary context strings', () => {
  const c = context(), artifact = 'main.dart.js', candidate = {webFiles: {[artifact]: 'b'.repeat(64)}};
  const error = {name: 'private-error-name', message: 'private-body', stack:
    `f@https://attendus-staging.web.app/${artifact}:0:1\n` +
    `f@https://attendus-staging.web.app/${artifact}:99999999999999999999:1\n` +
    Array.from({length: 100}, (_, i) => `f@https://attendus-staging.web.app/${artifact}:${i + 1}:2`).join('\n')};
  const options = {candidate, context: c, pageUrl: 'https://attendus-staging.web.app/manage/private-proof?token=secret',
    pageRole: 'private-role', engine: 'private-engine', observedDuringStep: {gate: 'private-step', sequence: 1}, now: 0};
  const record = pageErrorDiagnostic(error, options);
  assert.equal(record.frames.length, 12); assert.equal(record.stackTruncated, true);
  assert.equal(record.routeFamily, '/manage/:proof'); assert.equal(record.errorName, 'Error');
  assert.equal(record.pageRole, 'unassigned'); assert.equal(record.engine, 'unknown'); assert.equal(record.observedDuringStep, null);
  assert.equal(JSON.stringify(record).includes('private'), false);
  assert.equal(pageErrorDiagnostic(error, {...options, pageUrl: 'https://foreign.example/secret'}).routeFamily, 'outside-staging');
  assert.deepEqual(pageErrorDiagnostic({message: 'Null check operator used on a null value'}, options).frames, []);
  assert.equal(pageErrorDiagnostic({stack: 'x'.repeat(70000)}, options).stackTruncated, true);
});

test('page error recorder retains a sticky count past its bounded evidence capacity', () => {
  const recorder = createPageErrorRecorder({candidate: {webFiles: {}}, context: context()});
  for (let i = 0; i < 203; i++) recorder.record(Error('private payload'), {errorIndex: i, now: 0});
  const result = recorder.snapshot();
  assert.equal(result.totalCount, 203); assert.equal(result.entries.length, 200); assert.equal(result.omittedCount, 3);
  assert.equal(result.entries[199].errorIndex, 199);
  assert.equal(JSON.stringify(result).includes('private payload'), false);
});
test('staging evidence rejects real recipients, unowned records and production configuration', () => {
  assert.doesNotThrow(() => validateFixture(context()));
  for (const mutate of [c => c.fixture.owner.email = 'real@example.com', c => c.fixture.owner.uid = 'real-user',
    c => c.fixture.privateEventId = 'unowned', c => c.projectId = 'orgami-66nxok', c => c.baseUrl = 'https://attendus.app',
    c => c.fixture.firebase.storageBucket = 'orgami-66nxok.appspot.com',
    c => {c.fixture.staff = {uid: 'owner', email: 'staff@real.example', password: 'fixture-password'};}]) {
    const value = context(); mutate(value); assert.throws(() => validateFixture(value));
  }
});

test('history content expectations come only from current, candidate-bound owned event snapshots', async () => {
  function setup() {
    const c = context(); c.sourceSha = 'a'.repeat(40); c.candidateRunId = '123';
    Object.assign(c.fixture, {sourceSha: c.sourceSha, candidateRunId: c.candidateRunId});
    const runId = c.fixture.runId, rows = new Map(), reads = [];
    rows.set(`QualificationScopes/${runId}`, {schemaVersion: 1, projectId: c.projectId, status: 'active', mode: 'capture',
      createdAt: new Date(Date.now() - 60000), expiresAt: new Date(Date.now() + 60000), actorUids: ['owner'], recipientUids: ['owner'],
      eventIds: ['event', 'second'], organizationIds: [], conversationIds: [], recipientEmailHashes: []});
    rows.set(`QualificationSetup/${runId}`, {state: 'seeded', projectId: c.projectId, sourceSha: c.sourceSha, candidateRunId: c.candidateRunId});
    for (const [kind, id] of [['account', 'owner'], ['event', 'event'], ['event', 'second']]) {
      rows.set(`QualificationBindings/${bindingId(kind, id)}`, {schemaVersion: 1, state: 'bound', projectId: c.projectId, runId});
    }
    for (const [id, title] of [['event', 'Fixture'], ['second', 'Second owned title']]) rows.set(`Events/${id}`, {customerUid: 'owner', private: false, status: 'active', title});
    const db = {projectId: c.projectId, doc: (value) => value, runTransaction: async (fn, options) => {
      assert.deepEqual(options, {readOnly: true});
      return fn({get: async (key) => {reads.push(key); const value = rows.get(key);
        return {id: key.split('/').at(-1), exists: !!value, data: () => value, get: (name) => value?.[name]};}});
    }};
    return {c, db, rows, reads};
  }
  const good = setup();
  assert.deepEqual((await readOwnedHistoryTitles(good.c, good.db)).titles, {event: 'Fixture', second: 'Second owned title'});
  assert.equal(good.reads.length, 8);
  for (const mutate of [
    f => {f.db.projectId = 'orgami-66nxok';}, f => {f.c.fixture.sourceSha = 'b'.repeat(40);},
    f => {f.c.fixture.secondEventId = '../unowned'; f.c.fixture.ownedFixtureIds.push('../unowned');},
    f => {f.rows.get(`QualificationSetup/${f.c.fixture.runId}`).candidateRunId = 'other';},
    f => {f.rows.get(`QualificationScopes/${f.c.fixture.runId}`).expiresAt = new Date(0);},
    f => {f.rows.get(`QualificationBindings/${bindingId('event', 'second')}`).runId = 'other';},
    f => {f.rows.set('account_deletion_jobs/owner', {status: 'running'});},
    f => {f.rows.get('Events/second').customerUid = 'other';}, f => {f.rows.get('Events/second').title = '';},
    f => {f.rows.get('Events/second').private = true;}, f => {f.rows.get('Events/second').status = 'cancelled';},
    f => {f.rows.get('Events/event').title = 'Mismatched context';},
  ]) {const value = setup(); mutate(value); await assert.rejects(readOwnedHistoryTitles(value.c, value.db));}
});

test('correct history URL alone cannot pass a blank, wrong-title or hidden public/Flutter page', async () => {
  let visible = true, actualTitle = 'Second owned title'; const calls = [];
  const match = (expected) => ({first: () => ({waitFor: async ({state}) => {
    assert.equal(state, 'visible'); if (!visible || actualTitle !== expected) throw Error('Expected content unavailable');
  }, isVisible: async () => visible && actualTitle === expected})});
  const page = {url: () => 'https://attendus-staging.web.app/event/second',
    getByRole: (role, options) => {calls.push({role, ...options}); return match(options.name);},
    getByText: (title, options) => {calls.push({title, ...options}); return match(title);}};
  for (const flutter of [false, true]) {
    visible = true; actualTitle = 'Second owned title';
    assert.equal(await visibleHistoryTitle(page, actualTitle, flutter), true);
    actualTitle = 'Page unavailable'; await assert.rejects(visibleHistoryTitle(page, 'Second owned title', flutter));
    actualTitle = 'Second owned title'; visible = false; await assert.rejects(visibleHistoryTitle(page, actualTitle, flutter));
  }
  assert.ok(calls.every((call) => call.exact === true)); assert.equal(calls[0].role, 'heading'); assert.equal(calls[0].level, 1);
});
test('network boundary permits required App Check but blocks cross-project data and providers', () => {
  const c = context();
  for (const url of ['https://attendus-staging.web.app/app/discover',
    'https://us-central1-attendus-staging.cloudfunctions.net/getPublicProfilesV1',
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fixture-key',
    'https://firestore.googleapis.com/v1/projects/attendus-staging/databases/(default)/documents',
    'https://firestore.googleapis.com/google.firestore.v1.Firestore/Listen/channel?database=projects%2Fattendus-staging%2Fdatabases%2F(default)',
    'https://firebaseappcheck.googleapis.com/v1/projects/123/apps/1%3A123%3Aweb%3Afixture:exchangeRecaptchaEnterpriseToken?key=fixture-key',
    'https://www.google.com/recaptcha/enterprise/anchor?k=public', 'https://recaptchaenterprise.googleapis.com/v1/projects/staging/assessments']) {
    assert.equal(allowStagingRequest(url, 'POST', c), true, url);
  }
  for (const url of ['https://attendus.app/app/discover', 'https://us-central1-orgami-66nxok.cloudfunctions.net/getPublicProfilesV1',
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=production-key',
    'https://firestore.googleapis.com/v1/projects/orgami-66nxok/databases/(default)/documents',
    'https://firestore.googleapis.com/v1/projects/orgami-66nxok/databases/(default)/documents?ignored=projects/attendus-staging/databases/',
    'https://firestore.googleapis.com/google.firestore.v1.Firestore/Listen/channel?database=projects%2Forgami-66nxok%2Fdatabases%2F(default)&ignored=projects/attendus-staging/databases/',
    'https://firebaseappcheck.googleapis.com/v1/projects/999/apps/1%3A123%3Aweb%3Afixture:exchangeRecaptchaEnterpriseToken',
    'https://firebaseappcheck.googleapis.com/v1/projects/123/apps/other:exchangeRecaptchaEnterpriseToken',
    'https://graph.microsoft.com/v1.0/me/sendMail', 'https://maps.googleapis.com/maps/api/js']) {
    assert.equal(allowStagingRequest(url, 'POST', c), false, url);
  }
});
test('CSV evidence counts embedded newlines as one row and preserves escaped quotes', () => {
  assert.deepEqual(parseCsv('name,answer\r\n"One, Two","line1\nline2"\r\nThree,"He said ""hello"""\r\n'),
    [['name', 'answer'], ['One, Two', 'line1\nline2'], ['Three', 'He said "hello"']]);
  assert.throws(() => parseCsv('name\n"truncated'));
});

test('actual App Check SDK exchange is bound to the exact staging app, method and key', () => {
  const c = context();
  for (const host of ['content-firebaseappcheck.googleapis.com', 'firebaseappcheck.googleapis.com']) {
    for (const project of ['attendus-staging', '123']) {
      for (const app of [c.fixture.firebase.appId, encodeURIComponent(c.fixture.firebase.appId)]) {
        const url = `https://${host}/v1/projects/${project}/apps/${app}:exchangeRecaptchaEnterpriseToken?key=fixture-key`;
        assert.equal(allowStagingRequest(url, 'POST', c), true);
        for (const method of ['GET', 'PUT', 'DELETE', 'OPTIONS']) assert.equal(allowStagingRequest(url, method, c), false);
        for (const bad of [url.replace('fixture-key', 'foreign'), url + '&key=fixture-key', url + '&unexpected=1',
          url.replace('?key=fixture-key', ''), url.replace(app, '1:999:web:foreign'),
          url.replace(`/projects/${project}/`, '/projects/foreign/'), url.replace('EnterpriseToken', 'Token'),
          url.replace(':exchangeRecaptchaEnterpriseToken', ':exchangeDebugToken'), url.replace(':exchangeRecaptchaEnterpriseToken', ':exchangeRecaptchaEnterpriseToken/extra'),
          url + '#secret', url.replace(host, `user:secret@${host}`), url.replace(host, `${host}:444`),
          url.replace(host, `${host}.example.test`), url.replace('https:', 'http:')]) {
          assert.equal(allowStagingRequest(bad, 'POST', c), false);
        }
      }
    }
  }
});

test('legacy Auth iframe configuration GET permits only the bound key and SDK cache timestamp', () => {
  const c = context();
  const url = 'https://www.googleapis.com/identitytoolkit/v3/relyingparty/getProjectConfig?key=fixture-key';
  for (const good of [url, url + '&cb=1791100000000']) assert.equal(allowStagingRequest(good, 'GET', c), true);
  for (const method of ['POST', 'PUT', 'DELETE', 'OPTIONS']) assert.equal(allowStagingRequest(url, method, c), false);
  for (const bad of [url.replace('fixture-key', 'foreign'), url + '&key=fixture-key', url + '&cb=1&cb=2',
    url + '&cb=callback', url + '&projectNumber=999', url + '&delegatedProjectNumber=999',
    url.replace('getProjectConfig', 'getAccountInfo'), url.replace('getProjectConfig', 'getProjectConfig/extra'),
    url.replace('www.googleapis.com', 'user:secret@www.googleapis.com'), url.replace('.com/', '.com:444/'),
    url.replace('https:', 'http:'), url + '#secret', url.replace('?key=fixture-key', '')]) {
    assert.equal(allowStagingRequest(bad, 'GET', c), false);
  }
});

test('Maps SDK CSP probe permits only its exact empty GET and csp_test marker', () => {
  const c = context(); c.fixture.mapsApiKey = 'staging-maps-key';
  const url = 'https://maps.googleapis.com/maps/api/mapsjs/gen_204';
  for (const good of [url, url + '?csp_test=true']) assert.equal(allowStagingRequest(good, 'GET', c), true);
  for (const method of ['POST', 'PUT', 'DELETE', 'OPTIONS']) assert.equal(allowStagingRequest(url, method, c), false);
  for (const bad of [url + '?csp_test=false', url + '?csp_test=true&csp_test=true', url + '?unexpected=1',
    url + '?key=staging-maps-key', url + '/extra', url + '#secret', url.replace('https:', 'http:'),
    url.replace('.com/', '.com:444/'), url.replace('maps.googleapis.com', 'user:secret@maps.googleapis.com'),
    url.replace('gen_204', 'other')]) assert.equal(allowStagingRequest(bad, 'GET', c), false);
  delete c.fixture.mapsApiKey;
  assert.equal(allowStagingRequest(url, 'GET', c), false);
});

test('browser evidence redacts absolute and scheme-less URL queries, fragments and credentials', () => {
  const fixture = context().fixture;
  const secrets = ['userinfo-secret', 'query-secret', 'session-secret', 'fragment-secret', 'opaque-proof-secret-123456789', 'opaque-bearer-secret'];
  for (const prefix of ['https://', '//', '/']) {
    const input = `Request failed: ${prefix}user:userinfo-secret@firestore.googleapis.com/v1/projects/staging/databases/(default)/documents?key=query-secret&SID=session-secret#fragment-secret net::ERR_FAILED`;
    const result = scrubBrowserError(Error(input), fixture);
    assert.match(result, /Request failed:/); assert.match(result, /net::ERR_FAILED/);
    assert.match(result, /firestore\.googleapis\.com/);
    assert.ok(!result.includes('?') && !result.includes('#'));
    for (const secret of secrets) assert.ok(!result.includes(secret));
  }
  const result = scrubBrowserError(Error('/manage/opaque-proof-secret-123456789?key=query-secret#fragment-secret fixture-password Authorization: Bearer opaque-bearer-secret eyJhbGci.fixture.signature'), fixture);
  for (const secret of [...secrets, fixture.owner.password, 'eyJhbGci.fixture.signature']) assert.ok(!result.includes(secret));
  assert.equal(scrubBrowserError(Error('Null check operator used on a null value'), fixture), 'Null check operator used on a null value');
});

test('Safari Auth iframe is read-only and bound to the staging project key and default app', () => {
  const c = context();
  const frame = 'https://attendus-staging.firebaseapp.com/__/auth/iframe?apiKey=fixture-key&appName=%5BDEFAULT%5D&v=12.15.0&eid=p';
  const hint = 'm;/_/scs/abc-static/_/js/k=gapi.lb.en.signature/d=1/rs=signature/m=__features__';
  for (const url of [frame, frame + '&fw=Flutter&usegapi=1&jsh=' + encodeURIComponent(hint),
    'https://attendus-staging.firebaseapp.com/__/auth/iframe.js']) assert.equal(allowStagingRequest(url, 'GET', c), true, url);
  for (const url of [frame.replace('attendus-staging', 'orgami-66nxok'), frame.replace('attendus-staging', 'foreign'),
    frame.replace('fixture-key', 'foreign-key'), frame + '&apiKey=foreign-key', frame + '&appName=other',
    frame.replace('%5BDEFAULT%5D', 'other'), frame.replace('eid=p', 'eid=s'), frame.replace('12.15.0', 'invalid'),
    frame.replace('/iframe?', '/handler?'), frame + '&redirectUrl=https://attendus.app',
    frame + '&jsh=' + encodeURIComponent('m;/arbitrary'), frame.replace('.com/', '.com:444/'),
    'https://attendus-staging.firebaseapp.com/__/auth/iframe.js?unexpected=1',
    'https://attendus-staging.firebaseapp.com/__/auth/iframe-extra.js']) assert.equal(allowStagingRequest(url, 'GET', c), false, url);
  for (const method of ['POST', 'PUT', 'DELETE', 'OPTIONS']) {
    assert.equal(allowStagingRequest(frame, method, c), false);
    assert.equal(allowStagingRequest('https://attendus-staging.firebaseapp.com/__/auth/iframe.js', method, c), false);
  }
  c.fixture.firebase.projectId = 'orgami-66nxok';
  assert.equal(allowStagingRequest(frame, 'GET', c), false);
});

test('GIS loader permits only its exact read-only bootstrap script without Google OAuth or data access', () => {
  const c = context();
  const script = 'https://accounts.google.com/gsi/client';
  assert.equal(allowStagingRequest(script, 'GET', c), true);
  for (const method of ['HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']) {
    assert.equal(allowStagingRequest(script, method, c), false, method);
  }
  for (const url of [script + '?', script + '?client_id=foreign', script + '#fragment', script + '/',
    script.replace('https:', 'http:'), script.replace('.com/', '.com:444/'),
    script.replace('accounts.google.com', 'user:password@accounts.google.com'),
    script.replace('accounts.google.com', 'accounts.google.com.example.test'),
    'https://accounts.google.com/gsi/status', 'https://accounts.google.com/gsi/iframe/select',
    'https://accounts.google.com/o/oauth2/v2/auth', 'https://accounts.google.com/signin/oauth',
    'https://oauth2.googleapis.com/token', 'https://www.googleapis.com/oauth2/v3/userinfo']) {
    for (const method of ['GET', 'POST']) assert.equal(allowStagingRequest(url, method, c), false, `${method} ${url}`);
  }
});

test('GAPI allows only the observed read-only Auth loader and iframe library', () => {
  const c = context();
  const loader = 'https://apis.google.com/js/api.js?onload=__iframefcb240125';
  const library = 'https://apis.google.com/_/scs/abc-static/_/js/k=gapi.lb.en.gh7qIZtzO5w.O/m=gapi_iframes/rt=j/sv=1/d=1/ed=1/rs=AHpOoo84YKT1RVy0T6hcXi5rH3LooB1WCw/cb=gapi.loaded_0?le=scs';
  for (const url of [loader, library]) {
    assert.equal(allowStagingRequest(url, 'GET', c), true);
    for (const method of ['POST', 'PUT', 'DELETE', 'OPTIONS']) assert.equal(allowStagingRequest(url, method, c), false);
  }
  for (const url of [loader + '&onload=foreign', loader.replace('__iframefcb240125', 'arbitrary'),
    loader.replace('/js/api.js', '/js/client.js'), loader.replace('.com/', '.com:444/'),
    library.replace('m=gapi_iframes', 'm=client'), library.replace('m=gapi_iframes', 'm=gapi_iframes,client'),
    library.replace('abc-static', 'apps-static'), library + '&unexpected=1', library.replace('?le=scs', ''),
    'https://apis.google.com/arbitrary',
    'https://firebaseinstallations.googleapis.com/v1/projects/attendus-staging/installations']) {
    assert.equal(allowStagingRequest(url, 'GET', c), false, url);
  }
  assert.equal(allowStagingRequest('https://firebaseinstallations.googleapis.com/v1/projects/attendus-staging/installations', 'POST', c), false);
});

test('Maps requests require the bound staging key except narrow read-only static assets', () => {
  const c = context(); c.fixture.mapsApiKey = 'staging-maps-key';
  for (const url of ['https://maps.googleapis.com/maps/api/js?key=staging-maps-key&v=weekly',
    'https://maps.googleapis.com/maps-api-v3/api/js/62/1/common.js', 'https://maps.gstatic.com/mapfiles/marker.png']) {
    assert.equal(allowStagingRequest(url, 'GET', c), true);
  }
  for (const url of ['https://maps.googleapis.com/maps/api/js?key=production',
    'https://maps.googleapis.com/maps/api/js?key=staging-maps-key&key=production',
    'https://maps.googleapis.com/maps/api/geocode/json', 'https://maps.gstatic.com/arbitrary']) {
    assert.equal(allowStagingRequest(url, 'GET', c), false);
  }
  const rpc = 'https://maps.googleapis.com/$rpc/google.maps.internal.mapsjs.v1.MapsJsInternalService/GetViewportInfo';
  assert.equal(allowStagingRequest(rpc, 'POST', c, {'x-goog-api-key': 'staging-maps-key'}), true);
  assert.equal(allowStagingRequest(rpc, 'POST', c, {'x-goog-api-key': 'production'}), false);
});

test('cleanup identities include only successful anonymous signup in the bound staging project', () => {
  const fixture = context().fixture;
  const url = 'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=fixture-key';
  const response = {localId: 'generated-guest', idToken: 'must-not-escape'};
  assert.equal(createdAnonymousUid(url, 200, {returnSecureToken: true}, response, fixture), 'generated-guest');
  for (const [candidateUrl, status, request, body] of [
    [url.replace('fixture-key', 'production-key'), 200, {}, response],
    [url.replace('signUp', 'signInWithPassword'), 200, {}, response],
    [url, 400, {}, response], [url, 200, {email: 'fixture@example.test'}, response],
    [url, 200, {password: 'secret'}, response], [url, 200, {}, {localId: '../unowned'}],
  ]) assert.equal(createdAnonymousUid(candidateUrl, status, request, body, fixture), null);
});

test('disposable deletion gate refuses preceding failures, omissions and browser errors', () => {
  const names = ['browser-auth-guest-organizer', 'account-switch-privacy', 'cache-upgrade-deeplinks',
    'accessibility-responsive', 'large-roster-export-download-expiry'];
  const fixture = () => Object.fromEntries(names.map((name) => [name, {blockers: [], assertions: [{id: name, expected: [1], actual: [1]}]}]));
  assert.doesNotThrow(() => requirePassingBrowserJourneys(fixture(), []));
  assert.throws(() => requirePassingBrowserJourneys(fixture(), ['uncaught error']));
  for (const modify of [g => delete g[names[2]], g => g[names[3]].blockers.push('unavailable engine'),
    g => g[names[4]].assertions[0].actual = [2], g => g[names[1]].assertions = []]) {
    const gates = fixture(); modify(gates); assert.throws(() => requirePassingBrowserJourneys(gates, []));
  }
});
test('full journeys require actual Chrome and Edge launches; replay does not require branded browsers', async () => {
  const launched = [], closed = [];
  const launcher = {launch: async (options) => {
    launched.push(options);
    return {version: () => options.channel === 'chrome' ? '130.0.1' : '130.0.2', close: async () => closed.push(options.channel)};
  }};
  assert.deepEqual(await preflightBrandedBrowsers(true, launcher), []);
  assert.equal(launched.length, 0);
  assert.deepEqual(await preflightBrandedBrowsers(false, launcher), [
    {name: 'chrome', channel: 'chrome', version: '130.0.1'}, {name: 'edge', channel: 'msedge', version: '130.0.2'},
  ]);
  assert.deepEqual(closed, ['chrome', 'msedge']);
  assert.deepEqual(launched.map((options) => options.channel), ['chrome', 'msedge']);
  assert.ok(launched.every((options) => options.headless && options.timeout === 30000));
  for (const missing of ['chrome', 'msedge']) {
    await assert.rejects(preflightBrandedBrowsers(false, {launch: async (options) => {
      if (options.channel === missing) throw Error('Executable missing');
      return {version: () => '130.0.1', close: async () => {}};
    }}), (error) => error.unavailableBrowser === (missing === 'chrome' ? 'chrome' : 'edge'));
  }
  let invalidClosed = false;
  await assert.rejects(preflightBrandedBrowsers(false, {launch: async () => ({version: () => '', close: async () => {invalidClosed = true;}})}), /cannot launch/);
  assert.equal(invalidClosed, true);
});
test('expiry observation accepts only the exact staging bucket and export job', () => {
  const value = 'https://storage.googleapis.com/attendus-staging.appspot.com/private-event-exports/job/roster.csv?Expires=1791000000&Signature=fixture';
  assert.equal(signedFixtureUrl(value, 'attendus-staging.appspot.com', 'job').expires, 1791000000000);
  for (const invalid of [value.replace('/job/', '/other/'), value.replace('attendus-staging', 'orgami-66nxok'), value.replace('Expires', 'Ignored'), value.replace('https:', 'http:')]) {
    assert.throws(() => signedFixtureUrl(invalid, 'attendus-staging.appspot.com', 'job'));
  }
});
test('cache artifact server rejects encoded traversal and Windows path separators', () => {
  const root = path.resolve('build/fixture-artifact');
  assert.equal(artifactPath(root, '/releases/hash/main.dart.js'), path.join(root, 'releases/hash/main.dart.js'));
  for (const value of ['/%2e%2e/private', '/releases/../private', '/%5cprivate', '/%00private']) assert.throws(() => artifactPath(root, value));
});
test('cache replay refuses modified or additional artifact bytes', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'attendus-cache-guard-'));
  try {
    fs.writeFileSync(path.join(root, 'release-manifest.json'), JSON.stringify({currentRelease: 'previous'}));
    fs.writeFileSync(path.join(root, 'main.dart.js'), 'captured bytes');
    const expected = files(root);
    assert.equal(verifyTree(root, expected).currentRelease, 'previous');
    fs.writeFileSync(path.join(root, 'main.dart.js'), 'substituted bytes');
    assert.throws(() => verifyTree(root, expected), /differ/);
    fs.writeFileSync(path.join(root, 'main.dart.js'), 'captured bytes');
    fs.writeFileSync(path.join(root, 'extra.js'), 'unapproved bytes');
    assert.throws(() => verifyTree(root, expected), /differ/);
  } finally {
    for (const name of ['release-manifest.json', 'main.dart.js', 'extra.js']) {
      if (fs.existsSync(path.join(root, name))) fs.unlinkSync(path.join(root, name));
    }
    fs.rmdirSync(root);
  }
});

test('worker-enabled replay requires staging runtime options and literal messaging configuration', () => {
  const expected = context().fixture.firebase;
  const options = {...expected, authDomain: 'attendus-staging.firebaseapp.com'};
  assert.equal(verifyFirebaseApps([{name: '[DEFAULT]', options}], expected)[0].projectId, 'attendus-staging');
  for (const apps of [[], [{name: '[DEFAULT]', options: {...options, projectId: 'orgami-66nxok'}}],
    [{name: '[DEFAULT]', options: {...options, apiKey: 'other-key'}}],
    [{name: '[DEFAULT]', options: {...options, authDomain: 'production.firebaseapp.com'}}]]) {
    assert.throws(() => verifyFirebaseApps(apps, expected));
  }
  const worker = `const firebaseConfig = ${JSON.stringify(options)};\n` +
    `importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');\n` +
    `importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');\n` +
    `firebase.initializeApp(firebaseConfig);`;
  assert.equal(verifyMessagingWorker(worker, expected).projectId, 'attendus-staging');
  for (const source of [worker.replace('"attendus-staging"', '"orgami-66nxok"'),
    worker.replace('firebase.initializeApp(firebaseConfig)', 'firebase.initializeApp(loadConfig())'),
    worker.replace('www.gstatic.com', 'untrusted.example'),
    worker + '\nfirebase.initializeApp(firebaseConfig);']) {
    assert.throws(() => verifyMessagingWorker(source, expected));
  }
});
