'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {artifactPath, verifyTree, verifyFirebaseApps, verifyMessagingWorker} = require('../../tools/web_release_producers/browser-cache-upgrade')._test;
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');
const {files} = require('../../tools/web_release_contract');
const {validateFixture, allowStagingRequest, parseCsv, signedFixtureUrl, createdAnonymousUid, requirePassingBrowserJourneys, preflightBrandedBrowsers} = require('../../tools/web_release_producers/browser')._test;
function context() {
  const runId = 'qa-browser-20261004';
  const fixture = {runId, controlledRecipientDomain: 'example.test', runStartsAt: '2026-10-04T00:00:00Z',
    eventClosesAt: '2026-10-04T01:00:00Z', ownedFixtureIds: ['owner', 'attendee', 'unauthorized', 'event', 'private', 'second'],
    event: {id: 'event', title: 'Fixture', publicPath: '/event/event'}, privateEventId: 'private', secondEventId: 'second',
    firebase: {projectId: 'attendus-staging', apiKey: 'fixture-key', appId: '1:123:web:fixture', projectNumber: '123', storageBucket: 'attendus-staging.appspot.com'}};
  for (const role of ['owner', 'attendee', 'unauthorized']) fixture[role] = {uid: role, email: `${runId}-${role}@example.test`, password: 'fixture-password'};
  return {projectId: 'attendus-staging', baseUrl: 'https://attendus-staging.web.app', fixture};
}
test('staging evidence rejects real recipients, unowned records and production configuration', () => {
  assert.doesNotThrow(() => validateFixture(context()));
  for (const mutate of [c => c.fixture.owner.email = 'real@example.com', c => c.fixture.owner.uid = 'real-user',
    c => c.fixture.privateEventId = 'unowned', c => c.projectId = 'orgami-66nxok', c => c.baseUrl = 'https://attendus.app',
    c => c.fixture.firebase.storageBucket = 'orgami-66nxok.appspot.com',
    c => {c.fixture.staff = {uid: 'owner', email: 'staff@real.example', password: 'fixture-password'};}]) {
    const value = context(); mutate(value); assert.throws(() => validateFixture(value));
  }
});
test('network boundary permits required App Check but blocks cross-project data and providers', () => {
  const c = context();
  for (const url of ['https://attendus-staging.web.app/app/discover',
    'https://us-central1-attendus-staging.cloudfunctions.net/getPublicProfilesV1',
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fixture-key',
    'https://firestore.googleapis.com/v1/projects/attendus-staging/databases/(default)/documents',
    'https://firestore.googleapis.com/google.firestore.v1.Firestore/Listen/channel?database=projects%2Fattendus-staging%2Fdatabases%2F(default)',
    'https://firebaseappcheck.googleapis.com/v1/projects/123/apps/1%3A123%3Aweb%3Afixture:exchangeRecaptchaEnterpriseToken',
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
