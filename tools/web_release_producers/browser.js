'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {isDeepStrictEqual} = require('node:util');
const {createRequire} = require('node:module');
const dependencies = createRequire(path.resolve(__dirname, '../../tests/browser/package.json'));
const serverDependencies = createRequire(path.resolve(__dirname, '../../functions/package.json'));
const {gitSourceFiles} = require('../web_release_contract');
const {collectRosterPages} = require('./roster-read');
const {activateFlutterSemanticsPage} = require('./flutter-semantics');
const {readFirebaseAuthStatePage} = require('./firebase-auth-state');
const {htmlResponsiveProbe} = require('./safari');
const {validScope, bindingId} = require('../../functions/communications/qualification-isolation');
const {chromium, firefox, webkit} = dependencies('@playwright/test');
const GATES = ['browser-auth-guest-organizer', 'account-switch-privacy', 'cache-upgrade-deeplinks',
  'accessibility-responsive', 'large-roster-export-download-expiry'];
const sha = (value) => crypto.createHash('sha256').update(value).digest('hex');
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function openCheckInConsole(page) {
  for (const label of ['Manage event', 'Check-in']) {
    const control = page.getByText(label, {exact: true}).last();
    await control.scrollIntoViewIfNeeded(); await control.click();
  }
  await page.getByText('Check-in Console', {exact: true}).waitFor();
  await page.getByText('Event roster', {exact: true}).waitFor();
}

function validateFixture(context) {
  if (context.projectId !== 'attendus-staging' || context.baseUrl !== 'https://attendus-staging.web.app') throw Error('Browser qualification requires the exact staging project/origin.');
  const fixture = context.fixture;
  if (!fixture || !/^[a-z0-9-]{8,80}$/.test(fixture.runId || '') || fixture.controlledRecipientDomain !== 'example.test' ||
      !Array.isArray(fixture.ownedFixtureIds) || !Number.isFinite(Date.parse(fixture.runStartsAt)) ||
      !Number.isFinite(Date.parse(fixture.eventClosesAt))) throw Error('Missing controlled, owned staging fixture manifest.');
  for (const role of ['owner', 'attendee', 'unauthorized', ...['staff', 'administrator', 'deletion'].filter((name) => fixture[name])]) {
    const account = fixture[role];
    if (!account || !fixture.ownedFixtureIds.includes(account.uid) || !account.email?.startsWith(fixture.runId + '-') ||
        !account.email.endsWith('@example.test') || typeof account.password !== 'string' || account.password.length < 10) throw Error(`Unsafe or missing ${role} account fixture.`);
  }
  for (const id of [fixture.event?.id, fixture.privateEventId, fixture.secondEventId]) {
    if (!id || !fixture.ownedFixtureIds.includes(id)) throw Error('Event is outside the owned fixture manifest.');
  }
  if (fixture.event.publicPath !== `/event/${encodeURIComponent(fixture.event.id)}` ||
      fixture.firebase?.projectId !== 'attendus-staging' || !fixture.firebase.apiKey ||
      !/^attendus-staging\.(appspot\.com|firebasestorage\.app)$/.test(fixture.firebase.storageBucket || '')) throw Error('Fixture Firebase configuration or public path does not match staging.');
  return fixture;
}

function allowStagingRequest(value, method, context, headers = {}) {
  let url;
  try {url = new URL(value);} catch {return false;}
  const fixture = context.fixture;
  if (['data:', 'blob:', 'about:'].includes(url.protocol)) return true;
  if (url.origin === context.baseUrl) return true;
  if (url.protocol !== 'https:') return false;
  // google_sign_in_web loads this static SDK during plugin registration even
  // for email/guest sessions. This grants no Google OAuth or account API access.
  if (url.origin === 'https://accounts.google.com') {
    return method === 'GET' && url.href === 'https://accounts.google.com/gsi/client';
  }
  // FlutterFire installs the popup resolver even for email/guest auth. Firebase
  // JS proactively loads this read-only iframe on Safari/mobile before auth is
  // ready; its project key and default app must stay bound to this fixture.
  if (url.origin === 'https://attendus-staging.firebaseapp.com') {
    if (method !== 'GET' || url.username || url.password || fixture.firebase.projectId !== 'attendus-staging') return false;
    if (url.pathname === '/__/auth/iframe.js') return !url.search;
    if (url.pathname !== '/__/auth/iframe') return false;
    const params = url.searchParams;
    const allowed = new Set(['apiKey', 'appName', 'v', 'eid', 'fw', 'usegapi', 'jsh']);
    if ([...params.keys()].some((key) => !allowed.has(key) || params.getAll(key).length !== 1)) return false;
    return params.get('apiKey') === fixture.firebase.apiKey && params.get('appName') === '[DEFAULT]' &&
      /^\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(params.get('v') || '') && params.get('eid') === 'p' &&
      (!params.has('fw') || /^[A-Za-z0-9_,.-]{1,120}$/.test(params.get('fw'))) &&
      (!params.has('usegapi') || params.get('usegapi') === '1') &&
      (!params.has('jsh') || /^m;\/_\/scs\/abc-static\/_\/js\/k=gapi\.lb\.[A-Za-z0-9_.-]+\/d=1\/rs=[A-Za-z0-9_-]+\/m=__features__$/.test(params.get('jsh')));
  }
  if (url.origin === 'https://apis.google.com') {
    if (method !== 'GET' || url.username || url.password) return false;
    if (url.pathname === '/js/api.js') return [...url.searchParams.keys()].length === 1 &&
      /^__iframefcb\d{1,6}$/.test(url.searchParams.get('onload') || '');
    // Only the observed GAPI iframe module, not arbitrary APIs/modules. The
    // version and resource signatures change independently of our app build.
    return /^\/_\/scs\/abc-static\/_\/js\/k=gapi\.lb\.[A-Za-z0-9_.-]+\/m=gapi_iframes\/rt=j\/sv=1\/d=1\/ed=1\/rs=[A-Za-z0-9_-]+\/cb=gapi\.loaded_\d+$/.test(url.pathname) &&
      [...url.searchParams.keys()].length === 1 && url.searchParams.get('le') === 'scs';
  }
  if (url.hostname === 'us-central1-attendus-staging.cloudfunctions.net') return true;
  // The Firebase-hosted Auth iframe still uses this legacy read-only endpoint.
  // Its optional cb is Date.now(), not a JSONP callback or a delegated project.
  if (url.origin === 'https://www.googleapis.com') {
    const params = url.searchParams;
    return method === 'GET' && !url.username && !url.password && !url.hash &&
      fixture.firebase.projectId === 'attendus-staging' &&
      url.pathname === '/identitytoolkit/v3/relyingparty/getProjectConfig' &&
      [...params.keys()].every((key) => ['key', 'cb'].includes(key) && params.getAll(key).length === 1) &&
      params.get('key') === fixture.firebase.apiKey &&
      (!params.has('cb') || /^\d{1,16}$/.test(params.get('cb')));
  }
  if (['identitytoolkit.googleapis.com', 'securetoken.googleapis.com'].includes(url.hostname)) return url.searchParams.getAll('key').length === 1 && url.searchParams.get('key') === fixture.firebase.apiKey;
  if (url.hostname === 'firestore.googleapis.com') {
    const target = 'projects/attendus-staging/databases/(default)';
    if (decodeURIComponent(url.pathname).startsWith(`/v1/${target}/`)) return true;
    return /^\/google\.firestore\.v1\.Firestore\/(Listen|Write)\/channel$/.test(url.pathname) &&
      url.searchParams.getAll('database').length === 1 && url.searchParams.get('database') === target;
  }
  if (url.hostname === 'firebasestorage.googleapis.com') return url.pathname.startsWith(`/v0/b/${fixture.firebase.storageBucket}/`);
  if (method === 'GET' && url.hostname === 'fonts.gstatic.com') return /^\/s\//.test(url.pathname);
  if (method === 'GET' && url.hostname === 'www.gstatic.com') return /^\/(firebasejs|flutter-canvaskit|recaptcha)\//.test(url.pathname);
  if (url.hostname === 'www.google.com') return /^\/recaptcha\//.test(url.pathname);
  if (url.hostname === 'recaptchaenterprise.googleapis.com') return true;
  if (method === 'GET' && url.hostname === 'maps.gstatic.com') return /^\/(maps|mapfiles)\//.test(url.pathname);
  if (url.hostname === 'maps.googleapis.com') {
    if (url.pathname === '/maps/api/mapsjs/gen_204') {
      // The Maps SDK's CSP reachability probe has no API key or user payload.
      return url.origin === 'https://maps.googleapis.com' && method === 'GET' &&
        !url.username && !url.password && !url.hash && !!fixture.mapsApiKey &&
        fixture.firebase.projectId === 'attendus-staging' &&
        (!url.search || (url.searchParams.size === 1 && url.searchParams.get('csp_test') === 'true'));
    }
    if (method === 'GET' && /^\/maps-api-v3\/api\/js\//.test(url.pathname)) return true;
    const key = fixture.mapsApiKey;
    if (!key) return false;
    const keyed = url.searchParams.getAll('key').length === 1 && url.searchParams.get('key') === key;
    if (method === 'GET' && /^\/maps\/api\//.test(url.pathname)) return keyed;
    return method === 'POST' && /^\/\$rpc\/google\.maps\./.test(url.pathname) &&
      (keyed || headers['x-goog-api-key'] === key);
  }
  if (['https://content-firebaseappcheck.googleapis.com', 'https://firebaseappcheck.googleapis.com'].includes(url.origin)) {
    // Firebase's installed SDK emits raw colons in appId; the REST method is
    // the final suffix. Neither other apps nor debug/V3 exchanges are allowed.
    const project = url.pathname.match(/^\/v1\/projects\/([^/]+)\/apps\/([^/]+):exchangeRecaptchaEnterpriseToken$/);
    let appId;
    try {appId = project && decodeURIComponent(project[2]);} catch {return false;}
    return method === 'POST' && !url.username && !url.password && !url.hash &&
      fixture.firebase.projectId === 'attendus-staging' && !!project &&
      [fixture.firebase.projectId, fixture.firebase.projectNumber].filter(Boolean).includes(project[1]) &&
      typeof fixture.firebase.appId === 'string' && appId === fixture.firebase.appId &&
      url.searchParams.size === 1 && url.searchParams.get('key') === fixture.firebase.apiKey;
  }
  if (method === 'GET' && url.hostname === 'storage.googleapis.com') return url.pathname.startsWith(`/${fixture.firebase.storageBucket}/private-event-exports/`);
  return false;
}

function projectAppCheckError(httpStatus, bytes) {
  const base = {httpStatus, bodyStatus: 'projected', googleCode: null, googleStatus: null,
    errorInfoReasons: [], unrecognizedErrorInfo: false};
  if (!Buffer.isBuffer(bytes) || bytes.length > 16384) return {...base, bodyStatus: 'too-large'};
  let payload;
  try {payload = JSON.parse(bytes.toString('utf8'));} catch {return {...base, bodyStatus: 'invalid-json'};}
  const error = payload?.error;
  if (!error || typeof error !== 'object' || Array.isArray(error)) return {...base, bodyStatus: 'not-google-error'};
  const statuses = new Set(['CANCELLED', 'UNKNOWN', 'INVALID_ARGUMENT', 'DEADLINE_EXCEEDED', 'NOT_FOUND',
    'ALREADY_EXISTS', 'PERMISSION_DENIED', 'UNAUTHENTICATED', 'RESOURCE_EXHAUSTED', 'FAILED_PRECONDITION',
    'ABORTED', 'OUT_OF_RANGE', 'UNIMPLEMENTED', 'INTERNAL', 'UNAVAILABLE', 'DATA_LOSS']);
  const reasons = new Set(['SERVICE_DISABLED', 'BILLING_DISABLED', 'CONSUMER_INVALID', 'API_KEY_INVALID',
    'API_KEY_EXPIRED', 'API_KEY_NOT_FOUND', 'API_KEY_SERVICE_BLOCKED', 'API_KEY_HTTP_REFERRER_BLOCKED',
    'API_KEY_IP_ADDRESS_BLOCKED', 'API_KEY_ANDROID_APP_BLOCKED', 'API_KEY_IOS_APP_BLOCKED',
    'ACCESS_TOKEN_SCOPE_INSUFFICIENT', 'ACCESS_TOKEN_EXPIRED', 'CREDENTIALS_MISSING',
    'IAM_PERMISSION_DENIED', 'SECURITY_POLICY_VIOLATED', 'RATE_LIMIT_EXCEEDED',
    'RESOURCE_QUOTA_EXCEEDED', 'USER_PROJECT_DENIED']);
  if (Number.isInteger(error.code) && error.code >= 100 && error.code <= 599) base.googleCode = error.code;
  if (statuses.has(error.status)) base.googleStatus = error.status;
  for (const detail of (Array.isArray(error.details) ? error.details : []).slice(0, 20)) {
    if (detail?.['@type'] !== 'type.googleapis.com/google.rpc.ErrorInfo') continue;
    if (reasons.has(detail.reason)) {
      if (!base.errorInfoReasons.includes(detail.reason)) base.errorInfoReasons.push(detail.reason);
    } else base.unrecognizedErrorInfo = true;
  }
  // Never retain message, metadata, domain, token, raw body or unknown codes.
  return base;
}

function isBoundAppCheckFailure(response, context) {
  try {
    const status = response.status(), url = new URL(response.url());
    return Number.isInteger(status) && status >= 300 && status <= 599 &&
      ['https://content-firebaseappcheck.googleapis.com', 'https://firebaseappcheck.googleapis.com'].includes(url.origin) &&
      allowStagingRequest(response.url(), response.request().method(), context);
  } catch {return false;}
}

async function readAppCheckFailure(response, context, {timeoutMs = 3000} = {}) {
  if (!isBoundAppCheckFailure(response, context)) return null;
  const httpStatus = response.status();
  let timer;
  try {
    return await Promise.race([
      (async () => {
        const length = await response.headerValue('content-length');
        if (length === null) return {httpStatus, bodyStatus: 'not-read-missing-length'};
        if (!/^\d{1,6}$/.test(length || '')) return {httpStatus, bodyStatus: 'not-read-invalid-length'};
        if (Number(length) > 16384) return {httpStatus, bodyStatus: 'not-read-too-large'};
        // Playwright buffers the response: gate the declared length first,
        // then cap decoded bytes before parsing. Missing length is not a pass.
        return projectAppCheckError(httpStatus, await response.body());
      })().catch(() => ({httpStatus, bodyStatus: 'read-unavailable'})),
      new Promise((resolve) => {timer = setTimeout(() => resolve({httpStatus, bodyStatus: 'read-timeout'}), Math.min(3000, Math.max(1, timeoutMs)));}),
    ]);
  } finally {clearTimeout(timer);}
}

function createAppCheckErrorRecorder(context) {
  const records = [], pending = new Set();
  let totalCount = 0;
  return {
    observe(response) {
      if (!isBoundAppCheckFailure(response, context)) return;
      const sequence = ++totalCount;
      if (sequence > 50) return;
      const at = new Date().toISOString();
      const observation = readAppCheckFailure(response, context).then((result) => {
        if (result) records.push({sequence, at, ...result});
      });
      pending.add(observation);
      void observation.finally(() => pending.delete(observation));
    },
    async drain() {await Promise.allSettled([...pending]);},
    snapshot() {return {totalCount, omittedCount: Math.max(0, totalCount - 50), records: structuredClone(records)};},
  };
}

function scrubBrowserError(error, fixture) {
  let result = String(error?.message || error).replace(/\bBearer\s+[^\s'"<>]+/gi, 'Bearer [redacted]');
  // Chromium can emit /host/path?session=... without a scheme. Include that
  // form, protocol-relative URLs and relative proof paths, preserving reasons.
  result = result.replace(/https?:\/\/[^\s'"<>]+|\/{0,2}(?:[^\s/@]+@)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?\/[^\s'"<>]*|\/[^\s'"<>]+/gi, (value) => {
    try {
      const absolute = /^https?:\/\//i.test(value);
      const hosted = !absolute && /^\/{0,2}(?:[^\s/@]+@)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?\//i.test(value);
      const parsed = new URL(absolute ? value : hosted ? 'https://' + value.replace(/^\/+/, '') : value, 'https://attendus-staging.web.app');
      const pathname = /^\/manage\//.test(parsed.pathname) ? '/manage/[redacted]' : parsed.pathname;
      return (absolute || hosted ? parsed.origin : '') + pathname;
    } catch {return '[url]';}
  });
  for (const account of Object.values(fixture)) {
    if (typeof account?.password === 'string' && account.password) result = result.split(account.password).join('[redacted]');
  }
  return result.replace(/eyJ[A-Za-z0-9_.-]+/g, '[token]');
}

function pageErrorDiagnostic(error, {candidate, context, pageUrl, errorIndex, contextId, pageId,
  pageRole, engine, observedDuringStep, now = Date.now()}) {
  const positive = (value) => Number.isSafeInteger(value) && value > 0 && value <= 100000000;
  const origin = new URL(context.baseUrl).origin;
  let routeFamily = 'outside-staging';
  try {
    const url = new URL(pageUrl);
    if (url.origin === origin && !url.username && !url.password) {
      routeFamily = 'other-staging';
      for (const [pattern, family] of [
        [/^\/$/, '/'], [/^\/app\/discover\/?$/, '/app/discover'],
        [/^\/app\/event\/[^/]+\/?$/, '/app/event/:id'], [/^\/event\/[^/]+\/?$/, '/event/:id'],
        [/^\/community\/[^/]+\/?$/, '/community/:id'], [/^\/manage\/?$/, '/manage'],
        [/^\/manage\/[^/]+\/?$/, '/manage/:proof'], [/^\/app(?:\/|$)/, '/app/other'],
      ]) if (pattern.test(url.pathname)) {routeFamily = family; break;}
    }
  } catch {/* Blank/closed/external pages retain only the fixed family. */}
  const stack = typeof error?.stack === 'string' ? error.stack : '';
  const lines = stack.slice(0, 65536).split(/\r?\n/), frames = [];
  let stackTruncated = stack.length > 65536 || lines.length > 80;
  for (const line of lines.slice(0, 80)) {
    // Recognize Chromium and Firefox/WebKit frame shapes. Never persist raw
    // stack text, function names, arbitrary message payloads or foreign URLs.
    if (!/^\s*at\s+/.test(line) && !/^[^@\r\n]{0,300}@https:\/\//.test(line) && !/^https:\/\//.test(line)) continue;
    const match = /(https:\/\/[^\s()]+):(\d+):(\d+)\)?$/.exec(line.trim());
    if (!match || !positive(Number(match[2])) || !positive(Number(match[3]))) continue;
    try {
      const url = new URL(match[1]), artifact = url.pathname.slice(1);
      const digest = Object.hasOwn(candidate.webFiles || {}, artifact) ? candidate.webFiles[artifact] : null;
      if (url.origin !== origin || url.username || url.password || !/^[a-f0-9]{64}$/.test(digest || '')) continue;
      if (frames.length === 12) {stackTruncated = true; continue;}
      frames.push({artifact, sha256: digest, line: Number(match[2]), column: Number(match[3])});
    } catch {/* Invalid frame locations are omitted, never echoed. */}
  }
  const roles = ['public', 'owner', 'attendee', 'staff', 'unauthorized', 'administrator', 'deletion',
    'responsive', 'export', 'engine-public'];
  return {schemaVersion: 1, at: new Date(now).toISOString(),
    errorIndex: Number.isSafeInteger(errorIndex) && errorIndex >= 0 ? errorIndex : null,
    contextId: positive(contextId) ? contextId : null, pageId: positive(pageId) ? pageId : null,
    pageRole: roles.includes(pageRole) ? pageRole : 'unassigned',
    engine: ['chromium', 'firefox', 'webkit', 'edge', 'chrome'].includes(engine) ? engine : 'unknown',
    // This is observation context, not a claim about which step caused an
    // asynchronous exception from an earlier operation.
    observedDuringStep: [...GATES, 'post-close-replay'].includes(observedDuringStep?.gate) && positive(observedDuringStep?.sequence) ?
      {gate: observedDuringStep.gate, sequence: observedDuringStep.sequence} : null,
    routeFamily, errorName: ['Error', 'TypeError', 'RangeError', 'StateError', 'AssertionError', 'FirebaseError'].includes(error?.name) ? error.name : 'Error',
    nullCheckMessage: error?.message === 'Null check operator used on a null value',
    frames, stackPresent: Boolean(stack), stackTruncated};
}

function createPageErrorRecorder({candidate, context}) {
  const entries = []; let totalCount = 0;
  return {
    record(error, options) {
      totalCount++;
      if (entries.length < 200) entries.push(pageErrorDiagnostic(error, {...options, candidate, context}));
    },
    snapshot() {return {entries: [...entries], totalCount, omittedCount: totalCount - entries.length};},
  };
}

function parseCsv(input) {
  const rows = [], row = []; let field = '', quoted = false;
  for (let i = 0; i < input.length; i++) {
    const ch = input[i];
    if (quoted) {
      if (ch === '"' && input[i + 1] === '"') {field += '"'; i++;}
      else if (ch === '"') quoted = false;
      else field += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ',') {row.push(field); field = '';}
    else if (ch === '\n') {row.push(field.replace(/\r$/, '')); rows.push([...row]); row.length = 0; field = '';}
    else field += ch;
  }
  if (quoted) throw Error('Incomplete CSV quoted field.');
  if (field.length || row.length) {row.push(field.replace(/\r$/, '')); rows.push([...row]);}
  return rows;
}

function signedFixtureUrl(value, bucket, jobId) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.hostname !== 'storage.googleapis.com' ||
      !url.pathname.startsWith(`/${bucket}/private-event-exports/${jobId}/`)) throw Error('Export URL is not bound to the owned job/staging bucket.');
  const expires = Number(url.searchParams.get('Expires')) * 1000;
  if (!Number.isFinite(expires) || expires <= 0) throw Error('An observable signed URL expiry is required.');
  return {url, expires};
}

function createdAnonymousUid(url, status, request, response, fixture) {
  const parsed = new URL(url);
  if (parsed.origin !== 'https://identitytoolkit.googleapis.com' ||
      parsed.pathname !== '/v1/accounts:signUp' || parsed.searchParams.get('key') !== fixture.firebase.apiKey ||
      status !== 200 || !request || typeof request !== 'object' || request.email || request.password ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(response?.localId || '')) return null;
  return response.localId;
}

function requirePassingBrowserJourneys(gates, browserErrors) {
  if (browserErrors.length || GATES.some((id) => !gates[id] || gates[id].blockers.length ||
      !gates[id].assertions.length || gates[id].assertions.some((entry) => !isDeepStrictEqual(entry.expected, entry.actual)))) {
    throw Error('Destructive disposable-account qualification requires every preceding browser journey to pass.');
  }
}

async function preflightBrandedBrowsers(replayOnly, launcher = chromium) {
  if (replayOnly) return [];
  const results = [];
  for (const [name, channel] of [['chrome', 'chrome'], ['edge', 'msedge']]) {
    let engine;
    try {
      engine = await launcher.launch({headless: true, channel, timeout: 30000});
      const version = engine.version();
      if (typeof version !== 'string' || !version.trim()) throw Error('Browser did not return its version.');
      results.push({name, channel, version});
    } catch (cause) {
      const error = Error(`Required ${name} browser cannot launch; full journeys cannot begin.`, {cause});
      error.browserEngines = results;
      error.unavailableBrowser = name;
      throw error;
    } finally {if (engine) await engine.close();}
  }
  return results;
}

async function readOwnedHistoryTitles(context, db) {
  const fixture = validateFixture(context), ids = [fixture.event.id, fixture.secondEventId];
  if (db.projectId !== 'attendus-staging' || process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST ||
      !/^[a-f0-9]{40}$/.test(context.sourceSha || '') || !context.candidateRunId ||
      fixture.sourceSha !== context.sourceSha || fixture.candidateRunId !== context.candidateRunId ||
      new Set(ids).size !== 2 || ids.some((id) => !/^[A-Za-z0-9_-]{1,128}$/.test(id)) ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(fixture.owner.uid)) throw Error('History titles require the exact owned staging candidate.');
  return db.runTransaction(async (tx) => {
    const refs = [db.doc(`QualificationScopes/${fixture.runId}`), db.doc(`QualificationSetup/${fixture.runId}`),
      db.doc(`QualificationBindings/${bindingId('account', fixture.owner.uid)}`), db.doc(`account_deletion_jobs/${fixture.owner.uid}`),
      ...ids.flatMap((id) => [db.doc(`Events/${id}`), db.doc(`QualificationBindings/${bindingId('event', id)}`)])];
    const [scope, setup, owner, deleting, first, firstBinding, second, secondBinding] = await Promise.all(refs.map((ref) => tx.get(ref)));
    const bound = (row) => row.get('schemaVersion') === 1 && row.get('state') === 'bound' && row.get('projectId') === context.projectId && row.get('runId') === fixture.runId;
    if (!validScope(scope.data(), fixture.runId, context.projectId, Date.now()) || !scope.get('actorUids').includes(fixture.owner.uid) ||
        setup.get('state') !== 'seeded' || setup.get('projectId') !== context.projectId || setup.get('sourceSha') !== context.sourceSha ||
        setup.get('candidateRunId') !== context.candidateRunId || ![owner, firstBinding, secondBinding].every(bound) || deleting.exists) {
      throw Error('History fixture ownership, scope or candidate changed.');
    }
    const titles = {};
    for (const event of [first, second]) {
      const title = event.get('title');
      if (!event.exists || !scope.get('eventIds').includes(event.id) || event.get('customerUid') !== fixture.owner.uid ||
          event.get('private') !== false || event.get('deleted') === true || event.get('isHidden') === true ||
          !['active', 'scheduled'].includes(event.get('status')) || typeof title !== 'string' || !title.trim() || title.length > 500) {
        throw Error('History event is unavailable, unowned or has no valid title.');
      }
      titles[event.id] = title;
    }
    if (titles[fixture.event.id] !== fixture.event.title) throw Error('History fixture title differs from the live event.');
    return {projectId: context.projectId, runId: fixture.runId, sourceSha: context.sourceSha,
      candidateRunId: context.candidateRunId, checkedAt: new Date().toISOString(), titles};
  }, {readOnly: true});
}

async function visibleHistoryTitle(page, title, flutter = false) {
  if (typeof title !== 'string' || !title.trim() || title.length > 500) throw Error('Expected history content is missing.');
  const element = (flutter ? page.getByText(title, {exact: true}) : page.getByRole('heading', {level: 1, name: title, exact: true})).first();
  await element.waitFor({state: 'visible'});
  if (!await element.isVisible()) throw Error('Expected history event content is not visible.');
  return true;
}

async function readOwnedMapEvents(context, db, now = Date.now()) {
  const fixture = validateFixture(context), ids = [fixture.secondEventId, fixture.canaryEventId];
  if (db.projectId !== 'attendus-staging' || process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST ||
      !/^[a-f0-9]{40}$/.test(context.sourceSha || '') || !context.candidateRunId || !Number.isFinite(now) ||
      fixture.sourceSha !== context.sourceSha || fixture.candidateRunId !== context.candidateRunId ||
      new Set(ids).size !== 2 || ids.some((id) => !/^[A-Za-z0-9_-]{1,128}$/.test(id || '') || !fixture.ownedFixtureIds.includes(id)) ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(fixture.owner.uid)) throw Error('Maps requires two exact owned staging event fixtures.');
  return db.runTransaction(async (tx) => {
    const refs = [db.doc(`QualificationScopes/${fixture.runId}`), db.doc(`QualificationSetup/${fixture.runId}`),
      db.doc(`QualificationBindings/${bindingId('account', fixture.owner.uid)}`), db.doc(`account_deletion_jobs/${fixture.owner.uid}`),
      ...ids.flatMap((id) => [db.doc(`Events/${id}`), db.doc(`QualificationBindings/${bindingId('event', id)}`)])];
    const [scope, setup, owner, deleting, first, firstBinding, second, secondBinding] = await Promise.all(refs.map((ref) => tx.get(ref)));
    const bound = (row) => row.get('schemaVersion') === 1 && row.get('state') === 'bound' && row.get('projectId') === context.projectId && row.get('runId') === fixture.runId;
    if (!validScope(scope.data(), fixture.runId, context.projectId, now) || !scope.get('actorUids').includes(fixture.owner.uid) ||
        setup.get('state') !== 'seeded' || setup.get('projectId') !== context.projectId || setup.get('sourceSha') !== context.sourceSha ||
        setup.get('candidateRunId') !== context.candidateRunId || ![owner, firstBinding, secondBinding].every(bound) || deleting.exists) {
      throw Error('Maps fixture ownership, scope or candidate changed.');
    }
    const events = [first, second].map((event, index) => {
      const title = event.get('title'), latitude = event.get('latitude'), longitude = event.get('longitude');
      const locationName = event.get('locationName'), location = event.get('location');
      const start = event.get('selectedDateTime')?.toMillis?.(), duration = event.get('eventDurationMinutes');
      const expected = index === 0 ? [40.7829, -73.9654, 'Synthetic qualification venue A'] : [40.7851, -73.9683, 'Synthetic qualification venue B'];
      if (!event.exists || !scope.get('eventIds').includes(event.id) || event.get('customerUid') !== fixture.owner.uid ||
          event.get('private') !== false || event.get('deleted') === true || event.get('isHidden') === true ||
          !['active', 'scheduled'].includes(event.get('status')) || event.get('locationType') !== 'in_person' ||
          typeof title !== 'string' || !title.trim() || title.length > 500 ||
          latitude !== expected[0] || longitude !== expected[1] || locationName !== expected[2] ||
          typeof location !== 'string' || !location.includes('synthetic test location') || location.length > 1000 ||
          !Number.isFinite(start) || !Number.isInteger(duration) || duration <= 0 || now >= start + (duration + 120) * 60000) {
        throw Error('Maps event is unowned, ineligible or missing the seeded synthetic geometry.');
      }
      return {id: event.id, title, latitude, longitude, locationName, location};
    });
    if (events[0].title === events[1].title) throw Error('Maps fixture marker titles must be distinct.');
    return {projectId: context.projectId, runId: fixture.runId, sourceSha: context.sourceSha,
      candidateRunId: context.candidateRunId, checkedAt: new Date(now).toISOString(), events};
  }, {readOnly: true});
}

async function openOwnedMapMarker(page, events, {screenshot = async () => {}} = {}) {
  if (!Array.isArray(events) || events.length !== 2 || new Set(events.map((event) => event.id)).size !== 2 ||
      new Set(events.map((event) => event.title)).size !== 2 || events.some((event) =>
        typeof event.title !== 'string' || !event.title.trim() || typeof event.locationName !== 'string' ||
        !event.locationName || typeof event.location !== 'string' || !event.location)) throw Error('Missing verified Maps fixture landmarks.');
  await page.getByRole('button', {name: 'View events map', exact: true}).click();
  const map = page.locator('.gm-style').first();
  await map.waitFor({state: 'visible', timeout: 30000});
  try {
    if (await page.getByText('Map unavailable', {exact: true}).count()) throw Error('The Maps screen reports unavailable.');
    // The pinned Flutter web plugin passes InfoWindow.title to the real Maps
    // marker title and installs a click listener. Require the SDK's named
    // control; never invoke its callback, inject a button, or select a search
    // result as a substitute. Optimized SDK markers may lack this control;
    // that is an explicit accessibility/acceptance failure, not a pass.
    for (const event of events) await map.getByRole('button', {name: event.title, exact: true}).waitFor({state: 'visible', timeout: 30000});
    await screenshot('discover-maps-markers.png');
    const selected = events[0];
    await map.getByRole('button', {name: selected.title, exact: true}).click();
    const details = page.getByRole('button', {name: 'View event details', exact: true});
    await details.waitFor({state: 'visible'});
    await page.getByText(selected.title, {exact: true}).last().waitFor({state: 'visible'});
    await page.getByText(`${selected.locationName}\n${selected.location}`, {exact: true}).waitFor({state: 'visible'});
    await screenshot('discover-maps-selected-event.png');
    await details.click();
    await details.waitFor({state: 'hidden'});
    await page.getByText(selected.title, {exact: true}).last().waitFor({state: 'visible'});
    await page.getByText('Manage event', {exact: true}).waitFor({state: 'visible'});
    await screenshot('discover-maps-event-details.png');
    // This product path pushes an unnamed Flutter Navigator route. Its actual
    // details screen/content, not an invented browser URL, proves navigation.
    return {mapVisible: true, mapUnavailable: false, markerEventIds: events.map((event) => event.id), markerTitles: events.map((event) => event.title),
      selectedEventId: selected.id, selectedTitle: selected.title, selectedLocation: `${selected.locationName}\n${selected.location}`,
      detailsTitle: selected.title, detailsManagementVisible: true};
  } catch (error) {
    await screenshot('discover-maps-failure.png');
    throw error;
  }
}

function createBrowserAppCheckIntegration({candidate, context}) {
  const controller = context.appCheckTestMode;
  if (controller && (!['real', 'staging-debug-functional'].includes(controller.metadata?.mode) ||
      controller.metadata.projectId !== context.projectId || controller.metadata.appId !== context.fixture.firebase.appId ||
      controller.metadata.sourceSha !== candidate.sourceSha || controller.metadata.candidateRunId !== candidate.candidateRunId ||
      controller.metadata.fixtureRunId !== context.fixture.runId ||
      ['install', 'allowsDebugRequest', 'redact', 'assertPublishable'].some((key) => typeof controller[key] !== 'function'))) {
    throw Error('App Check diagnostic controller does not match the browser fixture.');
  }
  const debug = controller?.metadata.mode === 'staging-debug-functional';
  const observations = []; let totalCount = 0;
  const redact = (value) => debug ? controller.redact(value) : value;
  function requestAllowed(request, headers) {
    if (!debug) return allowStagingRequest(request.url(), request.method(), context, headers);
    let url;
    try {url = new URL(request.url());} catch {return false;}
    if (!['content-firebaseappcheck.googleapis.com', 'firebaseappcheck.googleapis.com'].includes(url.hostname)) {
      return allowStagingRequest(request.url(), request.method(), context, headers);
    }
    // No Enterprise fallback in debug mode. Init scripts do not cover workers
    // or child frames: reject unattributable, SW and non-top-level exchanges.
    // Dedicated-worker attribution is limited by Playwright; workers remain
    // unqualified and all service workers are blocked at context creation.
    try {
      if (request.serviceWorker?.()) return false;
      const frame = request.frame();
      if (!frame || frame.parentFrame() || new URL(frame.url()).origin !== context.baseUrl) return false;
      return controller.allowsDebugRequest(request.url(), request.method(), request.postData());
    } catch {return false;}
  }
  return {
    debug, redact, requestAllowed,
    async newContext(engine, options, {contextId, blocked, onAppCheckToken}) {
      if (debug && (options.recordHar !== undefined || options.storageState !== undefined)) {
        throw Error('App Check diagnostic requires a fresh context without HAR or stored state.');
      }
      const browserContext = await engine.newContext({...options, ...(debug ? {serviceWorkers: 'block'} : {})});
      if (debug) {
        try {await controller.install(browserContext, {origin: context.baseUrl,
          capturePolicy: {rawConsole: false, trace: false, har: false, storageState: false}});}
        catch {
          try {await browserContext.close();} catch {/* Preserve a fixed secret-free setup error. */}
          throw Error('App Check diagnostic initializer failed before page creation.');
        }
      }
      await browserContext.route('**/*', async (route) => {
        const request = route.request(), url = new URL(request.url());
        const headers = await request.allHeaders();
        if (!requestAllowed(request, headers)) {
          blocked.push({method: request.method(), origin: redact(url.origin), path: redact(url.pathname)});
          return route.abort('blockedbyclient');
        }
        if (headers['x-firebase-appcheck']) onAppCheckToken(headers['x-firebase-appcheck']);
        return route.continue();
      });
      await browserContext.routeWebSocket('**/*', (socket) => {
        blocked.push({method: 'WEBSOCKET', origin: redact(new URL(socket.url()).origin)}); socket.close();
      });
      browserContext.on('response', (response) => this.observe(response, contextId));
      return browserContext;
    },
    sanitizedError(error) {
      if (!debug) return error;
      return {name: redact(String(error?.name || 'Error')), message: redact(String(error?.message || error)),
        stack: typeof error?.stack === 'string' ? redact(error.stack) : ''};
    },
    observe(response, contextId) {
      if (!debug || !Number.isSafeInteger(contextId) || contextId < 1) return;
      try {
        const request = response.request();
        if (!controller.allowsDebugRequest(request.url(), request.method(), request.postData()) || !requestAllowed(request, {})) return;
        const status = response.status();
        if (!Number.isInteger(status) || status < 100 || status > 599) return;
        totalCount++;
        if (observations.length < 200) observations.push({sequence: totalCount, contextId,
          method: request.method(), at: new Date().toISOString(), httpStatus: status});
      } catch {/* Do not retain response errors, URLs, request bodies or tokens. */}
    },
    requireCacheSupport() {
      if (debug) throw Error('App Check debug diagnostic cannot qualify cache upgrade: independent predecessor bootstrap and worker initialization are unsupported.');
    },
    snapshot() {
      return {configuration: controller?.metadata || {mode: 'real', configurationOnly: true,
        realProviderAttestation: 'unverified', qualifiesCandidate: false},
      observations: structuredClone(observations), totalCount, omittedCount: totalCount - observations.length,
      observationMeaning: 'HTTP status only; not token validation or real-provider attestation',
      workerCoverage: debug ? 'unsupported-service-workers-blocked' : 'existing-real-mode'};
    },
  };
}

async function produce({candidate, context, outputDir}) {
  const fixture = validateFixture(context);
  const appCheckMode = createBrowserAppCheckIntegration({candidate, context});
  const replayOnly = context.requestedGates?.length === 1 && context.requestedGates[0] === 'post-close-replay';
  if (context.requestedGates && !replayOnly) throw Error('Browser evidence supports only full journeys or post-close-replay.');
  const activeGates = replayOnly ? ['post-close-replay'] : GATES;
  fs.mkdirSync(outputDir, {recursive: true});
  const gates = Object.fromEntries(activeGates.map((id) => [id, {assertions: [], rawPaths: [], blockers: []}]));
  const blocked = [], browserErrors = [], identityObservations = new Set(), anonymousUids = new Set();
  const pageErrors = createPageErrorRecorder({candidate, context}), appCheckErrors = createAppCheckErrorRecorder(context), contextMetadata = new WeakMap();
  let contextSequence = 0, pageSequence = 0, stepSequence = 0, observedDuringStep = null;
  let appCheckToken;
  const write = (gate, name, value) => { fs.writeFileSync(path.join(outputDir, name), JSON.stringify(value, null, 2)); gates[gate].rawPaths.push(name); };
  const record = (gate, id, expected, actual) => gates[gate].assertions.push({id, expected, actual});
  const scrub = (error) => scrubBrowserError(appCheckMode.sanitizedError(error), fixture);
  const browser = await chromium.launch({headless: true});
  async function newContext(viewport = {width: 1440, height: 1000}, engine = browser, engineName = 'chromium') {
    const contextId = ++contextSequence;
    const browserContext = await appCheckMode.newContext(engine, {viewport, serviceWorkers: replayOnly ? 'block' : 'allow'},
      {contextId, blocked, onAppCheckToken: (token) => {appCheckToken = token;}});
    contextMetadata.set(browserContext, {contextId, engine: engineName});
    return browserContext;
  }
  async function pageFor(browserContext, pageRole) {
    const page = await browserContext.newPage();
    const metadata = {...contextMetadata.get(browserContext), pageId: ++pageSequence, pageRole};
    page.setDefaultTimeout(30000);
    page.on('pageerror', (error) => {
      const safeError = appCheckMode.sanitizedError(error);
      const errorIndex = browserErrors.push(scrub(safeError)) - 1;
      pageErrors.record(safeError, {...metadata, errorIndex, pageUrl: page.url(), observedDuringStep});
    });
    page.on('response', (response) => {if (!appCheckMode.debug) appCheckErrors.observe(response);});
    observeCreatedIdentities(page);
    return page;
  }
  function observeCreatedIdentities(page) {
    page.on('response', (response) => {
      const url = new URL(response.url());
      if (url.origin !== 'https://identitytoolkit.googleapis.com' || url.pathname !== '/v1/accounts:signUp') return;
      const observation = (async () => {
        const uid = createdAnonymousUid(response.url(), response.status(), response.request().postDataJSON(), await response.json(), fixture);
        if (uid) anonymousUids.add(uid);
      })().catch(() => {browserErrors.push('Could not reconcile an observed fixture Auth signup.');});
      identityObservations.add(observation);
      void observation.finally(() => identityObservations.delete(observation));
    });
  }
  async function semantics(page) {
    await activateFlutterSemanticsPage(page);
  }
  async function app(page, pathname = '/app/discover') {
    await page.goto(context.baseUrl + pathname, {waitUntil: 'domcontentloaded'});
    await semantics(page);
  }
  async function textClick(page, name) {
    const target = page.getByText(name, {exact: true}).last();
    await target.scrollIntoViewIfNeeded(); await target.click();
  }
  async function login(page, account) {
    await app(page);
    await textClick(page, 'Log in');
    if (!await page.getByText('Welcome back', {exact: true}).isVisible()) await textClick(page, 'Log in');
    await page.getByRole('textbox', {name: 'Email address', exact: true}).fill(account.email);
    await page.getByRole('textbox', {name: 'Password', exact: true}).fill(account.password);
    await page.getByRole('textbox', {name: 'Password', exact: true}).press('Enter');
    await page.getByText('Welcome back', {exact: true}).waitFor({state: 'hidden', timeout: 90000});
    await page.getByText('Discover', {exact: true}).first().waitFor();
  }
  async function screenshot(gate, page, name) {
    await page.screenshot({path: path.join(outputDir, name), fullPage: true});
    gates[gate].rawPaths.push(name);
  }
  async function step(gate, operation) {
    observedDuringStep = {gate, sequence: ++stepSequence};
    try {await operation();} catch (error) {gates[gate].blockers.push(scrub(error));}
    finally {observedDuringStep = null;}
  }
  async function browserToken(page, account) {
    // Read only the currently authenticated browser identity in memory. The
    // token never enters evidence, traces, screenshots, or error messages.
    const user = await readFirebaseAuthStatePage(page, {
      apiKey: fixture.firebase.apiKey, projectId: fixture.firebase.projectId,
      appName: '[DEFAULT]', expectedUid: account.uid, timeoutMs: 10000,
    });
    return user.token;
  }
  async function callable(name, data, token) {
    const response = await fetch(`https://us-central1-attendus-staging.cloudfunctions.net/${name}`, {method: 'POST',
      headers: {'content-type': 'application/json', authorization: `Bearer ${token}`, ...(appCheckToken ? {'X-Firebase-AppCheck': appCheckToken} : {})},
      body: JSON.stringify({data}), signal: AbortSignal.timeout(120000)});
    const payload = await response.json();
    if (!response.ok || payload.error) {const error = Error(`${name}: ${payload.error?.status || response.status}`); error.status = payload.error?.status; throw error;}
    return payload.result ?? payload.data;
  }
  const actors = new Map();
  async function actorPage(role) {
    if (!['owner', 'attendee', 'staff', 'unauthorized', 'administrator', 'deletion'].includes(role) || !fixture[role] ||
        !fixture.ownedFixtureIds.includes(fixture[role].uid)) throw Error('Pilot actor is outside the owned fixture manifest.');
    if (!actors.has(role)) {
      const actorContext = await newContext(), page = await pageFor(actorContext, role);
      await login(page, fixture[role]); actors.set(role, page);
    }
    if (!appCheckToken) throw Error('The packaged browser has not obtained an App Check token.');
    return actors.get(role);
  }
  async function callAs(role, name, data) {
    const page = await actorPage(role);
    return callable(name, data, await browserToken(page, fixture[role]));
  }
  async function capturedGuestProof(notBefore) {
    const committed = gitSourceFiles(path.resolve(__dirname, '../..'), 'tools/web_release_producers/');
    const name = 'tools/web_release_producers/browser-pilot.js';
    if (!committed[name] || candidate.sourceFiles?.[name] !== sha(committed[name])) throw Error('Guest proof observer differs from the frozen candidate.');
    if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) throw Error('Guest proof observation requires staging.');
    const {initializeApp, applicationDefault, deleteApp} = serverDependencies('firebase-admin/app');
    const {getFirestore} = serverDependencies('firebase-admin/firestore');
    const observerApp = initializeApp({projectId: 'attendus-staging', credential: applicationDefault()}, `browser-guest-${fixture.runId}`);
    try {
      const {createGuestProofObserver} = require('./browser-pilot');
      const observe = createGuestProofObserver({fixture, candidateIdentity: context, db: getFirestore(observerApp)});
      const deadline = Date.now() + 180000;
      do {
        const result = await observe({notBefore});
        if (result) {
          const url = new URL(result.manageUrl);
          if (url.origin !== context.baseUrl || !/^\/manage\/[A-Za-z0-9_-]{20,}$/.test(url.pathname) || url.search || url.hash) throw Error('Guest proof URL differs from the owned staging origin.');
          return result;
        }
        await delay(2000);
      } while (Date.now() < deadline);
      throw Error('Controlled guest confirmation capture did not become available.');
    } finally {await deleteApp(observerApp);}
  }
  try {
    const manifestResponse = await fetch(context.baseUrl + '/release-manifest.json', {signal: AbortSignal.timeout(30000)});
    const manifestBytes = Buffer.from(await manifestResponse.arrayBuffer());
    const expectedManifest = candidate.webFiles?.['release-manifest.json'];
    if (!manifestResponse.ok || sha(manifestBytes) !== expectedManifest) throw Error('Live release manifest bytes do not match the frozen candidate.');
    const identity = {candidateRunId: context.candidateRunId, sourceSha: context.sourceSha, releaseId: context.releaseId,
      projectId: context.projectId, webSha256: context.webSha256, manifestSha256: sha(manifestBytes)};
    if (replayOnly) {
      const gate = 'post-close-replay';
      await step(gate, async () => {
        const committed = gitSourceFiles(path.resolve(__dirname, '../..'), 'tools/web_release_producers/');
        for (const name of ['browser-replay.js', 'browser-pilot.js']) {
          const key = `tools/web_release_producers/${name}`;
          if (!committed[key] || candidate.sourceFiles?.[key] !== sha(committed[key])) throw Error('Replay helper differs from the frozen candidate.');
        }
        if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) throw Error('Post-close replay requires deployed staging.');
        const {originalPilot, createReplayObserver, pageCallable, runReplay, RAW} = require('./browser-replay');
        const original = originalPilot(candidate, context);
        const {initializeApp, applicationDefault, deleteApp} = serverDependencies('firebase-admin/app');
        const {getFirestore} = serverDependencies('firebase-admin/firestore');
        const observerApp = initializeApp({projectId: 'attendus-staging', credential: applicationDefault()}, `browser-replay-${fixture.runId}`);
        try {
          const observe = createReplayObserver({fixture, candidateIdentity: context, db: getFirestore(observerApp), original});
          const connect = async (role, online) => {
            const page = await actorPage(role);
            await browserToken(page, fixture[role]);
            await page.context().setOffline(!online);
            await page.waitForFunction((expected) => navigator.onLine === expected, online);
          };
          const invoke = async (role, name, data) => {
            const page = await actorPage(role);
            return pageCallable(page, {name, data, token: await browserToken(page, fixture[role]), appCheckToken, actorUid: fixture[role].uid});
          };
          try {
            const receipt = await runReplay({candidate, context, original, observe, connect, invoke});
            write(gate, RAW, receipt); gates[gate].assertions.push(...receipt.assertions);
            gates[gate].window = {eventClosesAt: fixture.eventClosesAt, effectiveClosesAt: receipt.effectiveClosesAt, replayExecutedAt: receipt.completedAt};
          } catch (error) {
            if (error.replayReport) {write(gate, RAW, error.replayReport); gates[gate].assertions.push(...error.replayReport.assertions);}
            throw error;
          }
        } finally {await getFirestore(observerApp).terminate(); await deleteApp(observerApp);}
      });
      await Promise.allSettled([...identityObservations]);
      record(gate, 'uncaught-browser-errors', [], browserErrors);
      record(gate, 'unexpected-blocked-network-requests', [], blocked);
      write(gate, 'fixture-created-identities.json', {runId: fixture.runId, projectId: context.projectId, anonymousUids: [...anonymousUids].sort()});
      write(gate, 'browser-replay-network.json', {identity, blocked, browserErrors, pageErrors: pageErrors.snapshot()});
      return {gates, observedDeploymentIdentity: identity};
    }
    // Observe the original source timers before long UI journeys can cross an
    // hourly claim boundary. This records pending/absent/claimed state only;
    // provider capture and source-specific timer verification remain later gates.
    let earlyTimerSource;
    await step(GATES[0], async () => {
      const helperName = 'tools/web_release_producers/timer-source-read.js';
      const helperBytes = gitSourceFiles(path.resolve(__dirname, '../..'), 'tools/web_release_producers/')[helperName];
      if (!helperBytes || candidate.sourceFiles?.[helperName] !== sha(helperBytes)) throw Error('Original timer source reader differs from the frozen candidate.');
      const {readOriginalTimerSource} = require('./timer-source-read');
      const {initializeApp, applicationDefault, deleteApp} = serverDependencies('firebase-admin/app');
      const {getFirestore} = serverDependencies('firebase-admin/firestore');
      const observer = initializeApp({projectId: 'attendus-staging', credential: applicationDefault()}, `browser-original-timers-${fixture.runId}`);
      const db = getFirestore(observer);
      let snapshot;
      try {
        snapshot = await readOriginalTimerSource({db, candidate, fixture});
        write(GATES[0], 'original-timer-source-early.json', snapshot);
      } finally {await db.terminate(); await deleteApp(observer);}
      earlyTimerSource = snapshot;
    });
    if (!earlyTimerSource) {
      for (const gate of GATES) gates[gate].blockers.push('Original timer source preflight failed; no browser fixture mutations started.');
      return {gates, observedDeploymentIdentity: identity};
    }
    let brandedBrowsers;
    try {brandedBrowsers = await preflightBrandedBrowsers(false);}
    catch (error) {
      write(GATES[0], 'browser-engine-scope.json', {identity, preflight: error.browserEngines,
        unavailableBrowser: error.unavailableBrowser, blocker: scrub(error)});
      for (const gate of GATES) {
        gates[gate].blockers.push(scrub(error));
        record(gate, 'required-branded-browsers-can-launch', ['chrome', 'edge'], (error.browserEngines ?? []).map((entry) => entry.name));
      }
      return {gates, observedDeploymentIdentity: identity};
    }
    let history, mapEvents;
    await step(GATES[2], async () => {
      const {initializeApp, applicationDefault, deleteApp} = serverDependencies('firebase-admin/app');
      const {getFirestore} = serverDependencies('firebase-admin/firestore');
      const observer = initializeApp({projectId: 'attendus-staging', credential: applicationDefault()}, `browser-history-${fixture.runId}`);
      const db = getFirestore(observer);
      try {history = await readOwnedHistoryTitles(context, db); write(GATES[2], 'history-owned-events.json', history);}
      finally {await db.terminate(); await deleteApp(observer);}
    });
    if (!history) {
      for (const gate of GATES) gates[gate].blockers.push('Owned history event preflight failed; no browser fixture mutations started.');
      return {gates, observedDeploymentIdentity: identity};
    }
    await step(GATES[0], async () => {
      const {initializeApp, applicationDefault, deleteApp} = serverDependencies('firebase-admin/app');
      const {getFirestore} = serverDependencies('firebase-admin/firestore');
      const observer = initializeApp({projectId: 'attendus-staging', credential: applicationDefault()}, `browser-maps-${fixture.runId}`);
      const db = getFirestore(observer);
      try {mapEvents = await readOwnedMapEvents(context, db); write(GATES[0], 'maps-owned-events.json', mapEvents);}
      finally {await db.terminate(); await deleteApp(observer);}
    });
    if (!mapEvents) {
      for (const gate of GATES) gates[gate].blockers.push('Owned Maps event preflight failed; no browser fixture mutations started.');
      return {gates, observedDeploymentIdentity: identity};
    }
    const publicContext = await newContext(), publicPage = await pageFor(publicContext, 'public');
    const ownerContext = await newContext(), ownerPage = await pageFor(ownerContext, 'owner');
    await step(GATES[0], async () => {
      const response = await publicPage.goto(context.baseUrl + fixture.event.publicPath);
      record(GATES[0], 'public-event-http', 200, response.status());
      record(GATES[0], 'public-title', fixture.event.title, await publicPage.getByRole('heading', {level: 1}).innerText());
      await publicPage.locator('[data-public-action]:visible').first().click();
      const dialog = publicPage.getByRole('dialog');
      await dialog.getByLabel('Full name', {exact: true}).fill('Controlled Web Guest');
      await dialog.getByLabel('Email address', {exact: true}).fill(`${fixture.runId}-guest@example.test`);
      const questions = dialog.locator('.registration-questions input[required],.registration-questions textarea[required]');
      for (const input of await questions.all()) {
        if (await input.getAttribute('type') === 'checkbox') await input.check(); else await input.fill('Controlled fixture answer');
      }
      const notBefore = new Date().toISOString();
      await dialog.locator('button[type=submit]').click();
      await dialog.locator('.dialog-status').filter({hasText: /^(Confirmation complete\.|Request submitted\.)$/}).waitFor({timeout: 120000});
      const proof = await capturedGuestProof(notBefore);
      record(GATES[0], 'guest-registration-confirmed', 'confirmed', proof.status);
      // The signed proof stays only in memory and is exchanged by the real
      // browser for the HttpOnly management cookie. Never retain its URL.
      await publicPage.goto(proof.manageUrl);
      await publicPage.waitForURL(context.baseUrl + '/manage');
      await publicPage.locator('.manage-page').waitFor();
      record(GATES[0], 'guest-proof-opens-owned-event', fixture.event.title, await publicPage.getByRole('heading', {level: 1}).innerText());
      record(GATES[0], 'guest-proof-displays-confirmed', 'Confirmed', await publicPage.locator('dl.details > div').filter({has: publicPage.locator('dt', {hasText: /^Status$/})}).locator('dd').innerText());
      write(GATES[0], 'guest-proof-receipt.json', {runId: fixture.runId, eventId: fixture.event.id,
        registrationId: proof.registrationId, captureId: proof.captureId, fingerprint: proof.fingerprint, status: proof.status});
      await screenshot(GATES[0], publicPage, 'guest-confirmation.png');
      await login(ownerPage, fixture.owner);
      await browserToken(ownerPage, fixture.owner);
      if (!fixture.mapsApiKey) throw Error('A verified staging Maps browser key is required for Discover/Maps acceptance.');
      await ownerPage.waitForFunction(() => typeof globalThis.google?.maps?.Map === 'function', undefined, {timeout: 30000});
      const mapsLoader = await ownerPage.locator('script[data-attendus-google-maps]').getAttribute('src');
      record(GATES[0], 'discover-maps-loader-bound-to-staging-key', fixture.mapsApiKey, new URL(mapsLoader).searchParams.get('key'));
      const mapJourney = await openOwnedMapMarker(ownerPage, mapEvents.events, {
        screenshot: (name) => screenshot(GATES[0], ownerPage, name),
      });
      write(GATES[0], 'maps-ui-journey.json', {...mapJourney, projectId: context.projectId, runId: fixture.runId,
        sourceSha: context.sourceSha, candidateRunId: context.candidateRunId});
      record(GATES[0], 'discover-renders-two-owned-marker-controls', mapEvents.events.map((event) => event.id), mapJourney.markerEventIds);
      record(GATES[0], 'discover-marker-opens-exact-venue', `${mapEvents.events[0].locationName}\n${mapEvents.events[0].location}`, mapJourney.selectedLocation);
      record(GATES[0], 'discover-marker-details-navigation', {title: mapEvents.events[0].title, management: true},
        {title: mapJourney.detailsTitle, management: mapJourney.detailsManagementVisible});
      record(GATES[0], 'discover-renders-live-map', true, mapJourney.mapVisible);
      record(GATES[0], 'discover-map-not-unavailable', false, mapJourney.mapUnavailable);
      record(GATES[0], 'discover-maps-requests-not-blocked', [], blocked.filter((entry) => /^https:\/\/maps\./.test(entry.origin)));
      await app(ownerPage, `/app/event/${encodeURIComponent(fixture.event.id)}`);
      await ownerPage.getByText('Manage event', {exact: true}).waitFor();
      record(GATES[0], 'owner-management-visible', true, await ownerPage.getByText('Manage event', {exact: true}).isVisible());
      await screenshot(GATES[0], ownerPage, 'owner-event-management.png');
    });
    await step(GATES[0], async () => {
      const helperName = 'tools/web_release_producers/browser-inbox.js';
      const helperBytes = gitSourceFiles(path.resolve(__dirname, '../..'), 'tools/web_release_producers/')[helperName];
      if (!helperBytes || candidate.sourceFiles?.[helperName] !== sha(helperBytes)) throw Error('Synthetic inbox helper differs from the frozen candidate.');
      if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) throw Error('Synthetic inbox UI qualification requires staging.');
      const {initializeApp, applicationDefault, deleteApp} = serverDependencies('firebase-admin/app');
      const {getFirestore} = serverDependencies('firebase-admin/firestore');
      const observer = initializeApp({projectId: 'attendus-staging', credential: applicationDefault()}, `browser-inbox-${fixture.runId}`);
      const db = getFirestore(observer);
      try {
        const {runBrowserInbox} = require('./browser-inbox');
        // A separate real UI login leaves the account-switch journey's session
        // intact. These bounded Admin create/delete records are synthetic UI
        // fixtures; delivery capture and provider isolation are tested later.
        const page = await actorPage('owner');
        const report = await runBrowserInbox({fixture, candidateIdentity: context, db, page,
          openApp: (pathname) => app(page, pathname),
          currentUid: async () => {await browserToken(page, fixture.owner); return fixture.owner.uid;},
          screenshot: (name) => screenshot(GATES[0], page, name)});
        write(GATES[0], 'synthetic-inbox-ui.json', report);
        gates[GATES[0]].assertions.push(...report.assertions);
      } catch (error) {
        if (error.inboxReport) {
          write(GATES[0], 'synthetic-inbox-ui.json', error.inboxReport);
          gates[GATES[0]].assertions.push(...error.inboxReport.assertions);
        }
        throw error;
      } finally {await db.terminate(); await deleteApp(observer);}
    });
    await step(GATES[1], async () => {
      await app(ownerPage);
      await textClick(ownerPage, 'Profile'); await textClick(ownerPage, 'Settings'); await textClick(ownerPage, 'Sign out');
      await ownerPage.getByText('Log in', {exact: true}).first().waitFor({timeout: 60000});
      await login(ownerPage, fixture.unauthorized);
      await app(ownerPage, `/app/event/${encodeURIComponent(fixture.privateEventId)}`);
      await ownerPage.getByText(/event (not found|unavailable)|access (denied|required)|private event/i).first().waitFor({timeout: 60000});
      record(GATES[1], 'private-owner-management-not-restored', 0, await ownerPage.getByText('Manage event', {exact: true}).count());
      const token = await browserToken(ownerPage, fixture.unauthorized);
      let denial;
      try {await callable('listEventRosterV2', {eventId: fixture.event.id}, token);} catch (error) {denial = error.status;}
      record(GATES[1], 'other-account-roster-denied', 'PERMISSION_DENIED', denial ?? 'unexpected-success');
      const profiles = await callable('getPublicProfilesV1', {userIds: [fixture.owner.uid]}, token);
      const card = profiles.profiles?.[0] || {};
      record(GATES[1], 'public-profile-retains-uid', fixture.owner.uid, card.uid);
      record(GATES[1], 'public-profile-private-fields', [], Object.keys(card).filter((key) => !['uid', 'name', 'username', 'profilePictureUrl', 'bannerUrl', 'bio', 'isDiscoverable'].includes(key)).sort());
      const raw = await fetch(`https://firestore.googleapis.com/v1/projects/attendus-staging/databases/(default)/documents/Customers/${encodeURIComponent(fixture.owner.uid)}`,
        {headers: {authorization: `Bearer ${token}`}, signal: AbortSignal.timeout(30000)});
      record(GATES[1], 'raw-cross-account-profile-denied', 403, raw.status);
      await screenshot(GATES[1], ownerPage, 'account-switch-private-event.png');
    });
    await step(GATES[2], async () => {
      await publicPage.goto(context.baseUrl + fixture.event.publicPath);
      await visibleHistoryTitle(publicPage, history.titles[fixture.event.id]);
      await publicPage.goto(context.baseUrl + `/event/${encodeURIComponent(fixture.secondEventId)}`);
      await visibleHistoryTitle(publicPage, history.titles[fixture.secondEventId]);
      await publicPage.goBack();
      record(GATES[2], 'back-restores-event-route', context.baseUrl + fixture.event.publicPath, publicPage.url());
      record(GATES[2], 'back-restores-visible-event-content', true, await visibleHistoryTitle(publicPage, history.titles[fixture.event.id]));
      await publicPage.goForward();
      record(GATES[2], 'forward-restores-visible-second-content', true, await visibleHistoryTitle(publicPage, history.titles[fixture.secondEventId]));
      await publicPage.reload();
      record(GATES[2], 'forward-reload-preserves-second-route', context.baseUrl + `/event/${encodeURIComponent(fixture.secondEventId)}`, publicPage.url());
      record(GATES[2], 'reload-preserves-visible-second-content', true, await visibleHistoryTitle(publicPage, history.titles[fixture.secondEventId]));
      const firstAppPath = `/app/event/${encodeURIComponent(fixture.event.id)}`;
      const secondAppPath = `/app/event/${encodeURIComponent(fixture.secondEventId)}`;
      await app(ownerPage, firstAppPath);
      await ownerPage.getByText(fixture.event.title, {exact: true}).first().waitFor();
      await app(ownerPage, secondAppPath);
      await visibleHistoryTitle(ownerPage, history.titles[fixture.secondEventId], true);
      await ownerPage.goBack(); await semantics(ownerPage);
      await ownerPage.getByText(fixture.event.title, {exact: true}).first().waitFor();
      record(GATES[2], 'flutter-back-restores-event-deep-link', context.baseUrl + firstAppPath, ownerPage.url());
      await ownerPage.goForward(); await semantics(ownerPage);
      record(GATES[2], 'flutter-forward-visible-second-content', true, await visibleHistoryTitle(ownerPage, history.titles[fixture.secondEventId], true));
      await ownerPage.reload(); await semantics(ownerPage);
      record(GATES[2], 'flutter-forward-reload-preserves-deep-link', context.baseUrl + secondAppPath, ownerPage.url());
      record(GATES[2], 'flutter-reload-visible-second-content', true, await visibleHistoryTitle(ownerPage, history.titles[fixture.secondEventId], true));
      record(GATES[2], 'flutter-history-retains-switched-actor', fixture.unauthorized.uid,
        (await browserToken(ownerPage, fixture.unauthorized)) ? fixture.unauthorized.uid : null);
      appCheckMode.requireCacheSupport();
      const helperPath = path.join(__dirname, 'browser-cache-upgrade.js');
      if (!fs.existsSync(helperPath)) throw Error('Prior-artifact cache upgrade producer is unavailable.');
      const helper = require(helperPath), output = await (helper.produce || helper)({browser, context, candidate, outputDir, observeCreatedIdentities});
      gates[GATES[2]].assertions.push(...output.assertions);
      gates[GATES[2]].rawPaths.push(...output.rawPaths);
      gates[GATES[2]].blockers.push(...output.blockers);
    });
    await step(GATES[3], async () => {
      for (const width of [320, 390, 1440]) {
        await publicPage.setViewportSize({width, height: 900});
        await publicPage.goto(context.baseUrl + fixture.event.publicPath);
        await publicPage.keyboard.press('Tab');
        record(GATES[3], `skip-link-keyboard-${width}`, true, await publicPage.locator('.skip-link').evaluate((node) => node === document.activeElement));
        const pageScale = await publicPage.evaluate(htmlResponsiveProbe);
        record(GATES[3], `actual-200-percent-public-text-${width}`, true, pageScale.textIs200Percent);
        record(GATES[3], `200-percent-no-horizontal-overflow-${width}`, true, pageScale.pageFits);
        await screenshot(GATES[3], publicPage, `public-${width}-200percent.png`);
        const trigger = publicPage.locator('[data-public-action]:visible').first();
        await trigger.focus(); await publicPage.keyboard.press('Enter');
        await publicPage.getByRole('dialog').waitFor();
        const formScale = await publicPage.evaluate(htmlResponsiveProbe);
        record(GATES[3], `actual-200-percent-inserted-dialog-text-${width}`, true, formScale.textIs200Percent && formScale.dialogOpen);
        record(GATES[3], `200-percent-dialog-and-controls-fit-${width}`, true, formScale.pageFits && formScale.dialogFits && formScale.controlCount >= 3 && formScale.controlsFit);
        write(GATES[3], `responsive-${width}.json`, {page: pageScale, dialog: formScale});
        await screenshot(GATES[3], publicPage, `dialog-${width}-200percent.png`);
        await publicPage.keyboard.press('Escape');
        record(GATES[3], `dialog-returns-keyboard-focus-${width}`, true, await trigger.evaluate((node) => node === document.activeElement));
      }
      // Flutter 200-percent layout is covered by the rendered emulator test;
      // this exact-artifact gate still requires an enabled semantics tree.
      const appContext = await newContext({width: 390, height: 844}), appPage = await pageFor(appContext, 'responsive');
      await app(appPage);
      record(GATES[3], 'packaged-flutter-semantics-present', true, (await appPage.locator('flt-semantics').count()) > 0);
      await screenshot(GATES[3], appPage, 'packaged-flutter-390.png');
    });
    await step(GATES[4], async () => {
      const large = fixture.largeRoster;
      if (!large || !fixture.ownedFixtureIds.includes(large.eventId) || !Number.isInteger(large.expectedRows) || large.expectedRows < 1000 || !Array.isArray(large.expectedCsvHeaders) ||
          !Array.isArray(large.expectedCsvSpecialNames) || large.expectedCsvSpecialNames.length < 2) throw Error('Owned large-roster fixture (at least 1000 rows), CSV headers and escaping examples are required.');
      const exportContext = await newContext(), exportPage = await pageFor(exportContext, 'export');
      await login(exportPage, fixture.owner);
      const token = await browserToken(exportPage, fixture.owner);
      const {seen, pages} = await collectRosterPages((name, data) => callable(name, data, token), {eventId: large.eventId});
      record(GATES[4], 'large-roster-all-rows', large.expectedRows, seen);
      await app(exportPage, `/app/event/${encodeURIComponent(large.eventId)}`);
      await openCheckInConsole(exportPage);
      let uiPages = 1;
      while (await exportPage.getByText('Load more', {exact: true}).count()) {
        const next = exportPage.waitForResponse((response) => response.url().endsWith('/listEventRosterV2') && response.request().method() === 'POST');
        void next.catch(() => {});
        await textClick(exportPage, 'Load more');
        const payload = await (await next).json(), roster = payload.result ?? payload.data;
        if (!roster || !Array.isArray(roster.rows)) throw Error('Rendered roster pagination returned an error.');
        uiPages++;
        if (uiPages > 100) throw Error('Rendered roster pagination did not terminate.');
        if (!roster.nextCursor) {await exportPage.getByText('Load more', {exact: true}).waitFor({state: 'hidden'}); break;}
      }
      record(GATES[4], 'rendered-roster-page-count', pages, uiPages);
      const createdResponse = exportPage.waitForResponse((response) => response.url().endsWith('/createEventExportV2') && response.request().method() === 'POST');
      const exportedResponse = exportPage.waitForResponse(async (response) => {
        if (!response.url().endsWith('/getEventExportV2') || response.request().method() !== 'POST') return false;
        const payload = await response.json(); return (payload.result ?? payload.data)?.status === 'complete';
      }, {timeout: 120000});
      const browserDownload = exportPage.waitForEvent('download', {timeout: 180000});
      // Register rejection handlers before the click: an earlier UI failure
      // must not leave pending browser waits as unhandled rejections.
      for (const pending of [createdResponse, exportedResponse, browserDownload]) void pending.catch(() => {});
      await exportPage.getByRole('button', {name: 'Export all matching records', exact: true}).click();
      const creationPayload = await (await createdResponse).json(), created = creationPayload.result ?? creationPayload.data;
      const exportPayload = await (await exportedResponse).json(), exported = exportPayload.result ?? exportPayload.data;
      const signed = signedFixtureUrl(exported.url, fixture.firebase.storageBucket, created.jobId);
      const downloaded = await browserDownload;
      if (await downloaded.failure()) throw Error('Browser CSV download failed.');
      const stream = await downloaded.createReadStream(), chunks = [];
      for await (const chunk of stream) chunks.push(chunk);
      const bytes = Buffer.concat(chunks), rows = parseCsv(bytes.toString('utf8'));
      record(GATES[4], 'browser-export-filename', 'attendus-roster.csv', downloaded.suggestedFilename());
      record(GATES[4], 'downloaded-csv-headers', large.expectedCsvHeaders, rows[0]);
      record(GATES[4], 'downloaded-csv-full-row-count', large.expectedRows, rows.length - 1);
      record(GATES[4], 'every-csv-row-has-header-width', true, rows.every((row) => row.length === rows[0].length));
      const nameColumn = rows[0].indexOf('Name');
      const downloadedNames = new Set(rows.slice(1).map((row) => row[nameColumn]));
      record(GATES[4], 'csv-formula-and-multiline-values-preserved', large.expectedCsvSpecialNames,
        large.expectedCsvSpecialNames.filter((name) => downloadedNames.has(name)));
      await screenshot(GATES[4], exportPage, 'large-roster-export-complete.png');
      write(GATES[4], 'export-download.json', {jobId: created.jobId, byteLength: bytes.length, csvSha256: sha(bytes), rowCount: rows.length - 1, expiresAt: new Date(signed.expires).toISOString(), pages, uiPages});
      // Observe the real previously successful URL becoming expired. Do not
      // alter the signature/date or substitute a synthetic denial response.
      if (signed.expires - Date.now() > 7 * 60000) throw Error('Signed URL expiry exceeds the bounded observation window.');
      while (Date.now() < signed.expires + 5000) await delay(Math.min(15000, signed.expires + 5000 - Date.now()));
      const expired = await fetch(signed.url, {signal: AbortSignal.timeout(30000)});
      record(GATES[4], 'same-signed-url-expires', 403, expired.status);
    });
    await step(GATES[0], async () => {
      const helperFile = path.join(__dirname, 'browser-pilot.js');
      const committedHelpers = gitSourceFiles(path.resolve(__dirname, '../..'), 'tools/web_release_producers/');
      const helperBytes = committedHelpers['tools/web_release_producers/browser-pilot.js'];
      if (!fs.existsSync(helperFile) || !helperBytes || candidate.sourceFiles?.['tools/web_release_producers/browser-pilot.js'] !== sha(helperBytes)) {
        throw Error('Controlled pilot helper is unavailable or differs from the frozen candidate.');
      }
      if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) throw Error('Staging pilot cannot use an emulator environment.');
      const {initializeApp, applicationDefault, deleteApp} = serverDependencies('firebase-admin/app');
      const {getFirestore} = serverDependencies('firebase-admin/firestore');
      const observerApp = initializeApp({projectId: 'attendus-staging', credential: applicationDefault()}, `browser-pilot-${fixture.runId}`);
      try {
        const {runBrowserPilot, createPilotObserver} = require(helperFile);
        const observe = createPilotObserver({fixture, candidateIdentity: context, db: getFirestore(observerApp)});
        // All pilot mutations remain authenticated browser-user callables.
        // The protected ADC adapter reads scoped receipts/captures only.
        const report = await runBrowserPilot({fixture, candidateIdentity: context, callAs, observe});
        write(GATES[0], 'pilot-receipts.json', report);
        gates[GATES[0]].assertions.push(...report.assertions);
      } catch (error) {
        if (error.pilotReport) {
          write(GATES[0], 'pilot-receipts.json', error.pilotReport);
          gates[GATES[0]].assertions.push(...error.pilotReport.assertions);
        }
        throw error;
      } finally {await deleteApp(observerApp);}
    });
    // Run separate real engines. Playwright WebKit is labeled as WebKit;
    // neither it nor desktop viewport emulation claims physical Safari.
    const engines = [{name: 'firefox', type: firefox}, {name: 'webkit', type: webkit},
      {name: 'edge', type: chromium, channel: 'msedge'}, {name: 'chrome', type: chromium, channel: 'chrome'}];
    const scope = {deepJourneys: {name: 'chromium', version: browser.version()},
      additionalJourneys: engines.map((entry) => entry.name), brandedPreflight: brandedBrowsers,
      executed: [], completed: [], physicalSafari: 'separate required Safari producer'};
    write(GATES[3], 'browser-engine-scope.json', scope);
    for (const entry of engines) {
      let engine;
      const beforeBlockers = gates[GATES[0]].blockers.length;
      const beforeAssertions = Object.fromEntries(GATES.map((gate) => [gate, gates[gate].assertions.length]));
      await step(GATES[0], async () => {
        engine = await entry.type.launch({headless: true, ...(entry.channel ? {channel: entry.channel} : {})});
        const version = engine.version();
        scope.executed.push({name: entry.name, channel: entry.channel ?? null, version});
        record(GATES[0], `${entry.name}-runtime-version-reported`, true, typeof version === 'string' && version.trim().length > 0);
        const engineContext = await newContext({width: 1280, height: 900}, engine, entry.name), page = await pageFor(engineContext, 'engine-public');
        await page.goto(context.baseUrl + fixture.event.publicPath);
        record(GATES[0], `${entry.name}-public-event-title`, fixture.event.title, await page.getByRole('heading', {level: 1}).innerText());
        await page.locator('[data-public-action]:visible').first().click();
        await page.getByRole('dialog').waitFor();
        record(GATES[0], `${entry.name}-guest-form-present`, true, await page.getByRole('dialog').getByLabel('Full name', {exact: true}).isVisible());
        await page.keyboard.press('Escape');
        await login(page, fixture.unauthorized);
        await app(page, `/app/event/${encodeURIComponent(fixture.privateEventId)}`);
        await page.getByText('This event requires access', {exact: true}).waitFor();
        record(GATES[1], `${entry.name}-private-access-restricted`, true, await page.getByText('This event requires access', {exact: true}).isVisible());
        await page.reload(); await semantics(page);
        await page.getByText('This event requires access', {exact: true}).waitFor();
        record(GATES[1], `${entry.name}-reload-retains-restricted-state`, 0, await page.getByText('Manage event', {exact: true}).count());
        await page.goto(context.baseUrl + fixture.event.publicPath);
        await visibleHistoryTitle(page, history.titles[fixture.event.id]);
        await page.goto(context.baseUrl + `/event/${encodeURIComponent(fixture.secondEventId)}`);
        await visibleHistoryTitle(page, history.titles[fixture.secondEventId]);
        await page.goBack();
        record(GATES[2], `${entry.name}-back-route`, context.baseUrl + fixture.event.publicPath, page.url());
        record(GATES[2], `${entry.name}-back-visible-content`, true, await visibleHistoryTitle(page, history.titles[fixture.event.id]));
        await page.goForward();
        record(GATES[2], `${entry.name}-forward-visible-content`, true, await visibleHistoryTitle(page, history.titles[fixture.secondEventId]));
        await page.reload();
        record(GATES[2], `${entry.name}-forward-reload-route`, context.baseUrl + `/event/${encodeURIComponent(fixture.secondEventId)}`, page.url());
        record(GATES[2], `${entry.name}-reload-visible-content`, true, await visibleHistoryTitle(page, history.titles[fixture.secondEventId]));
        await page.setViewportSize({width: 390, height: 844});
        await page.goto(context.baseUrl + fixture.event.publicPath);
        const pageScale = await page.evaluate(htmlResponsiveProbe);
        record(GATES[3], `${entry.name}-actual-200-percent-text`, true, pageScale.textIs200Percent);
        record(GATES[3], `${entry.name}-390-200-percent-no-overflow`, true, pageScale.pageFits);
        await page.locator('[data-public-action]:visible').first().click();
        await page.getByRole('dialog').waitFor();
        const formScale = await page.evaluate(htmlResponsiveProbe);
        record(GATES[3], `${entry.name}-actual-200-percent-dialog-text`, true, formScale.textIs200Percent && formScale.dialogOpen);
        record(GATES[3], `${entry.name}-390-200-percent-dialog-controls-fit`, true, formScale.pageFits && formScale.dialogFits && formScale.controlCount >= 3 && formScale.controlsFit);
        write(GATES[3], `${entry.name}-responsive.json`, {page: pageScale, dialog: formScale});
        await screenshot(GATES[3], page, `${entry.name}-390-200percent.png`);
        await page.keyboard.press('Escape');
      });
      if (gates[GATES[0]].blockers.length > beforeBlockers) {
        for (const gate of [GATES[1], GATES[2], GATES[3]]) gates[gate].blockers.push(`${entry.name} did not complete the required browser journeys; see browser-auth-guest-organizer evidence.`);
      }
      if (gates[GATES[0]].blockers.length === beforeBlockers && GATES.every((gate) => gates[gate].assertions.slice(beforeAssertions[gate])
        .every((assertion) => isDeepStrictEqual(assertion.expected, assertion.actual)))) scope.completed.push(entry.name);
      if (engine) await engine.close();
    }
    write(GATES[3], 'browser-engine-scope.json', scope);
    for (const gate of GATES.slice(0, 4)) record(gate, 'required-browser-journeys-complete', engines.map((entry) => entry.name), scope.completed);
    await step(GATES[0], async () => {
      await Promise.allSettled([...identityObservations]);
      if (blocked.length) throw Error('Blocked unexpected network requests must be resolved before disposable-account deletion.');
      requirePassingBrowserJourneys(gates, browserErrors);
      const helperName = 'tools/web_release_producers/browser-communications.js';
      const helperBytes = gitSourceFiles(path.resolve(__dirname, '../..'), 'tools/web_release_producers/')[helperName];
      if (!helperBytes || candidate.sourceFiles?.[helperName] !== sha(helperBytes)) throw Error('Communications helper differs from the frozen candidate.');
      if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) throw Error('Staging communications cannot use emulator services.');
      const {initializeApp, applicationDefault, deleteApp} = serverDependencies('firebase-admin/app');
      const {getFirestore} = serverDependencies('firebase-admin/firestore');
      const {getAuth} = serverDependencies('firebase-admin/auth');
      const observerApp = initializeApp({projectId: 'attendus-staging', credential: applicationDefault()}, `browser-communications-${fixture.runId}`);
      try {
        const {runBrowserCommunications, createCommunicationsObserver} = require('./browser-communications');
        const observe = createCommunicationsObserver({fixture, candidateIdentity: context,
          db: getFirestore(observerApp), auth: getAuth(observerApp)});
        const report = await runBrowserCommunications({fixture, candidateIdentity: context, candidate,
          priorEvidence: context.priorEvidence ?? [], callAs, observe});
        write(GATES[0], 'communications-receipts.json', report);
        gates[GATES[0]].assertions.push(...report.assertions);
      } catch (error) {
        if (error.communicationsReport) {
          write(GATES[0], 'communications-receipts.json', error.communicationsReport);
          gates[GATES[0]].assertions.push(...error.communicationsReport.assertions);
        }
        throw error;
      } finally {await deleteApp(observerApp);}
    });
    await Promise.allSettled([...identityObservations]);
    fs.writeFileSync(path.join(outputDir, 'fixture-created-identities.json'), JSON.stringify({runId: fixture.runId,
      projectId: context.projectId, anonymousUids: [...anonymousUids].sort()}, null, 2));
    for (const gate of GATES) gates[gate].rawPaths.push('fixture-created-identities.json');
    for (const gate of GATES) record(gate, 'uncaught-browser-errors', [], browserErrors);
    for (const gate of GATES) record(gate, 'unexpected-blocked-network-requests', [], blocked);
    for (const gate of GATES) write(gate, `${gate}.json`, {identity, ...gates[gate]});
    fs.writeFileSync(path.join(outputDir, 'browser-network.json'), JSON.stringify({blocked, browserErrors, pageErrors: pageErrors.snapshot()}, null, 2));
    for (const gate of GATES) gates[gate].rawPaths.push('browser-network.json');
    return {gates, observedDeploymentIdentity: identity};
  } finally {
    const saveAppCheckMode = (phase) => fs.writeFileSync(path.join(outputDir, 'appcheck-browser-observations.json'),
      JSON.stringify({phase, ...appCheckMode.snapshot()}, null, 2));
    saveAppCheckMode('before-close');
    for (const gate of activeGates) gates[gate].rawPaths.push('appcheck-browser-observations.json');
    // Retain setup failures before teardown; replace with the completed
    // snapshot only after the browser and identity observations have settled.
    const savePageErrors = (phase) => fs.writeFileSync(path.join(outputDir, 'page-error-diagnostics.json'),
      JSON.stringify({phase, ...pageErrors.snapshot()}, null, 2));
    savePageErrors('before-close');
    for (const gate of activeGates) gates[gate].rawPaths.push('page-error-diagnostics.json');
    const saveAppCheckErrors = (phase) => fs.writeFileSync(path.join(outputDir, 'appcheck-error-diagnostics.json'),
      JSON.stringify({phase, ...appCheckErrors.snapshot()}, null, 2));
    await appCheckErrors.drain();
    saveAppCheckErrors('before-close');
    for (const gate of activeGates) gates[gate].rawPaths.push('appcheck-error-diagnostics.json');
    await browser.close();
    await Promise.allSettled([...identityObservations]);
    await appCheckErrors.drain();
    saveAppCheckMode('after-close');
    savePageErrors('after-close');
    saveAppCheckErrors('after-close');
    // Keep the cleanup manifest even when candidate identity or a browser
    // operation fails before a gate report can be produced.
    fs.writeFileSync(path.join(outputDir, 'fixture-created-identities.json'), JSON.stringify({runId: fixture.runId,
      projectId: context.projectId, anonymousUids: [...anonymousUids].sort()}, null, 2));
  }
}

module.exports = produce;
module.exports.produce = produce;
module.exports._test = {validateFixture, allowStagingRequest, scrubBrowserError, pageErrorDiagnostic, createPageErrorRecorder, projectAppCheckError, readAppCheckFailure, createAppCheckErrorRecorder, parseCsv, signedFixtureUrl, createdAnonymousUid, requirePassingBrowserJourneys, preflightBrandedBrowsers, htmlResponsiveProbe, readOwnedHistoryTitles, visibleHistoryTitle, openCheckInConsole, readOwnedMapEvents, openOwnedMapMarker, createBrowserAppCheckIntegration};
