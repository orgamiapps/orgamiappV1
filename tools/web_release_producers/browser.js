'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {isDeepStrictEqual} = require('node:util');
const {createRequire} = require('node:module');
const dependencies = createRequire(path.resolve(__dirname, '../../tests/browser/package.json'));
const serverDependencies = createRequire(path.resolve(__dirname, '../../functions/package.json'));
const {gitSourceFiles} = require('../web_release_contract');
const {chromium, firefox, webkit} = dependencies('@playwright/test');
const GATES = ['browser-auth-guest-organizer', 'account-switch-privacy', 'cache-upgrade-deeplinks',
  'accessibility-responsive', 'large-roster-export-download-expiry'];
const sha = (value) => crypto.createHash('sha256').update(value).digest('hex');
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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
  const url = new URL(value), fixture = context.fixture;
  if (['data:', 'blob:', 'about:'].includes(url.protocol)) return true;
  if (url.origin === context.baseUrl) return true;
  if (url.protocol !== 'https:') return false;
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
    if (method === 'GET' && /^\/maps-api-v3\/api\/js\//.test(url.pathname)) return true;
    const key = fixture.mapsApiKey;
    if (!key) return false;
    const keyed = url.searchParams.getAll('key').length === 1 && url.searchParams.get('key') === key;
    if (method === 'GET' && /^\/maps\/api\//.test(url.pathname)) return keyed;
    return method === 'POST' && /^\/\$rpc\/google\.maps\./.test(url.pathname) &&
      (keyed || headers['x-goog-api-key'] === key);
  }
  if (url.hostname === 'firebaseappcheck.googleapis.com') {
    const project = url.pathname.match(/^\/v1\/projects\/([^/]+)\/apps\/([^/:]+)/);
    return !!project && [fixture.firebase.projectId, fixture.firebase.projectNumber].filter(Boolean).includes(project[1]) &&
      decodeURIComponent(project[2]) === fixture.firebase.appId;
  }
  if (method === 'GET' && url.hostname === 'storage.googleapis.com') return url.pathname.startsWith(`/${fixture.firebase.storageBucket}/private-event-exports/`);
  return false;
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

async function produce({candidate, context, outputDir}) {
  const fixture = validateFixture(context);
  const replayOnly = context.requestedGates?.length === 1 && context.requestedGates[0] === 'post-close-replay';
  if (context.requestedGates && !replayOnly) throw Error('Browser evidence supports only full journeys or post-close-replay.');
  const activeGates = replayOnly ? ['post-close-replay'] : GATES;
  fs.mkdirSync(outputDir, {recursive: true});
  const gates = Object.fromEntries(activeGates.map((id) => [id, {assertions: [], rawPaths: [], blockers: []}]));
  const blocked = [], browserErrors = [], identityObservations = new Set(), anonymousUids = new Set();
  let appCheckToken;
  const write = (gate, name, value) => { fs.writeFileSync(path.join(outputDir, name), JSON.stringify(value, null, 2)); gates[gate].rawPaths.push(name); };
  const record = (gate, id, expected, actual) => gates[gate].assertions.push({id, expected, actual});
  const scrub = (error) => {
    let result = String(error?.message || error).replace(/https?:\/\/[^\s)]+/g, (url) => {try {const parsed = new URL(url); return parsed.origin + (/^\/manage\/[A-Za-z0-9_-]{20,}/.test(parsed.pathname) ? '/manage/[redacted]' : parsed.pathname);} catch {return '[url]';}});
    for (const account of Object.values(fixture)) {
      if (typeof account?.password === 'string' && account.password) result = result.split(account.password).join('[redacted]');
    }
    return result.replace(/eyJ[A-Za-z0-9_.-]+/g, '[token]');
  };
  const browser = await chromium.launch({headless: true});
  async function newContext(viewport = {width: 1440, height: 1000}, engine = browser) {
    const browserContext = await engine.newContext({viewport, serviceWorkers: replayOnly ? 'block' : 'allow'});
    await browserContext.route('**/*', async (route) => {
      const request = route.request(), url = new URL(request.url());
      const headers = await request.allHeaders();
      if (!allowStagingRequest(request.url(), request.method(), context, headers)) {
        blocked.push({method: request.method(), origin: url.origin, path: url.pathname});
        return route.abort('blockedbyclient');
      }
      if (headers['x-firebase-appcheck']) appCheckToken = headers['x-firebase-appcheck'];
      return route.continue();
    });
    await browserContext.routeWebSocket('**/*', (socket) => { blocked.push({method: 'WEBSOCKET', origin: new URL(socket.url()).origin}); socket.close(); });
    return browserContext;
  }
  async function pageFor(browserContext) {
    const page = await browserContext.newPage();
    page.setDefaultTimeout(30000);
    page.on('pageerror', (error) => browserErrors.push(scrub(error)));
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
    const placeholder = page.locator('flt-semantics-placeholder');
    if (await placeholder.count()) await placeholder.first().click({force: true});
    await page.locator('flt-semantics').first().waitFor({timeout: 90000});
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
    try {await operation();} catch (error) {gates[gate].blockers.push(scrub(error));}
  }
  async function browserToken(page, account) {
    // Read only the currently authenticated browser identity in memory. The
    // token never enters evidence, traces, screenshots, or error messages.
    const user = await page.evaluate(async () => new Promise((resolve, reject) => {
      const open = indexedDB.open('firebaseLocalStorageDb');
      open.onerror = () => reject(Error('Browser authentication storage unavailable.'));
      open.onsuccess = () => {
        const db = open.result;
        if (!db.objectStoreNames.contains('firebaseLocalStorage')) {db.close(); resolve(null); return;}
        const request = db.transaction('firebaseLocalStorage').objectStore('firebaseLocalStorage').getAll();
        request.onsuccess = () => {
          const value = request.result.find((row) => row.fbase_key?.startsWith('firebase:authUser:'))?.value;
          db.close(); resolve(value ? {uid: value.uid, token: value.stsTokenManager?.accessToken} : null);
        };
        request.onerror = () => {db.close(); reject(Error('Browser authentication state unavailable.'));};
      };
    }));
    if (user?.uid !== account.uid || !user.token) throw Error('Browser session does not match the owned fixture actor.');
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
      const actorContext = await newContext(), page = await pageFor(actorContext);
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
      write(gate, 'browser-replay-network.json', {identity, blocked, browserErrors});
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
    const publicContext = await newContext(), publicPage = await pageFor(publicContext);
    const ownerContext = await newContext(), ownerPage = await pageFor(ownerContext);
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
      if (!fixture.mapsApiKey) throw Error('A verified staging Maps browser key is required for Discover/Maps acceptance.');
      await ownerPage.waitForFunction(() => typeof globalThis.google?.maps?.Map === 'function', undefined, {timeout: 30000});
      const mapsLoader = await ownerPage.locator('script[data-attendus-google-maps]').getAttribute('src');
      record(GATES[0], 'discover-maps-loader-bound-to-staging-key', fixture.mapsApiKey, new URL(mapsLoader).searchParams.get('key'));
      await ownerPage.getByRole('button', {name: 'View events map', exact: true}).click();
      await ownerPage.locator('.gm-style').first().waitFor({timeout: 30000});
      record(GATES[0], 'discover-renders-live-map', true, await ownerPage.locator('.gm-style').first().isVisible());
      record(GATES[0], 'discover-map-not-unavailable', 0, await ownerPage.getByText('Map unavailable', {exact: true}).count());
      record(GATES[0], 'discover-maps-requests-not-blocked', [], blocked.filter((entry) => /^https:\/\/maps\./.test(entry.origin)));
      await screenshot(GATES[0], ownerPage, 'discover-maps.png');
      await app(ownerPage, `/app/event/${encodeURIComponent(fixture.event.id)}`);
      await ownerPage.getByText('Manage event', {exact: true}).waitFor();
      record(GATES[0], 'owner-management-visible', true, await ownerPage.getByText('Manage event', {exact: true}).isVisible());
      await screenshot(GATES[0], ownerPage, 'owner-event-management.png');
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
      await publicPage.goto(context.baseUrl + `/event/${encodeURIComponent(fixture.secondEventId)}`);
      await publicPage.goBack();
      record(GATES[2], 'back-restores-event-route', context.baseUrl + fixture.event.publicPath, publicPage.url());
      await publicPage.goForward(); await publicPage.reload();
      record(GATES[2], 'forward-reload-preserves-second-route', context.baseUrl + `/event/${encodeURIComponent(fixture.secondEventId)}`, publicPage.url());
      const firstAppPath = `/app/event/${encodeURIComponent(fixture.event.id)}`;
      const secondAppPath = `/app/event/${encodeURIComponent(fixture.secondEventId)}`;
      await app(ownerPage, firstAppPath);
      await ownerPage.getByText(fixture.event.title, {exact: true}).first().waitFor();
      await app(ownerPage, secondAppPath);
      await ownerPage.goBack(); await semantics(ownerPage);
      await ownerPage.getByText(fixture.event.title, {exact: true}).first().waitFor();
      record(GATES[2], 'flutter-back-restores-event-deep-link', context.baseUrl + firstAppPath, ownerPage.url());
      await ownerPage.goForward(); await ownerPage.reload(); await semantics(ownerPage);
      record(GATES[2], 'flutter-forward-reload-preserves-deep-link', context.baseUrl + secondAppPath, ownerPage.url());
      record(GATES[2], 'flutter-history-retains-switched-actor', fixture.unauthorized.uid,
        (await browserToken(ownerPage, fixture.unauthorized)) ? fixture.unauthorized.uid : null);
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
        await publicPage.evaluate(() => {
          const sizes = [...document.querySelectorAll('h1,h2,p,a,dt,dd,button,label,input')].map((node) => [node, parseFloat(getComputedStyle(node).fontSize)]);
          for (const [node, size] of sizes) node.style.fontSize = `${size * 2}px`;
        });
        record(GATES[3], `200-percent-no-horizontal-overflow-${width}`, true, await publicPage.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
        await screenshot(GATES[3], publicPage, `public-${width}-200percent.png`);
        const trigger = publicPage.locator('[data-public-action]:visible').first();
        await trigger.focus(); await publicPage.keyboard.press('Enter');
        await publicPage.getByRole('dialog').waitFor();
        await publicPage.keyboard.press('Escape');
        record(GATES[3], `dialog-returns-keyboard-focus-${width}`, true, await trigger.evaluate((node) => node === document.activeElement));
      }
      // Flutter 200-percent layout is covered by the rendered emulator test;
      // this exact-artifact gate still requires an enabled semantics tree.
      const appContext = await newContext({width: 390, height: 844}), appPage = await pageFor(appContext);
      await app(appPage);
      record(GATES[3], 'packaged-flutter-semantics-present', true, (await appPage.locator('flt-semantics').count()) > 0);
      await screenshot(GATES[3], appPage, 'packaged-flutter-390.png');
    });
    await step(GATES[4], async () => {
      const large = fixture.largeRoster;
      if (!large || !fixture.ownedFixtureIds.includes(large.eventId) || !Number.isInteger(large.expectedRows) || large.expectedRows < 1000 || !Array.isArray(large.expectedCsvHeaders) ||
          !Array.isArray(large.expectedCsvSpecialNames) || large.expectedCsvSpecialNames.length < 2) throw Error('Owned large-roster fixture (at least 1000 rows), CSV headers and escaping examples are required.');
      const exportContext = await newContext(), exportPage = await pageFor(exportContext);
      await login(exportPage, fixture.owner);
      const token = await browserToken(exportPage, fixture.owner);
      let cursor, seen = 0, pages = 0; const rowIds = new Set();
      do {
        const roster = await callable('listEventRosterV2', {eventId: large.eventId, ...(cursor ? {cursor} : {})}, token);
        for (const row of roster.rows || []) {const id = row.registrationId || row.id; if (!id || rowIds.has(id)) throw Error('Roster contains a duplicate or missing row identity.'); rowIds.add(id); seen++;}
        cursor = roster.nextCursor; pages++;
        if (pages > 100) throw Error('Roster pagination did not terminate.');
      } while (cursor);
      record(GATES[4], 'large-roster-all-rows', large.expectedRows, seen);
      await app(exportPage, `/app/event/${encodeURIComponent(large.eventId)}`);
      await textClick(exportPage, 'Manage event');
      await exportPage.getByText('Check-in Console', {exact: true}).waitFor();
      await exportPage.getByText('Event roster', {exact: true}).waitFor();
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
        const engineContext = await newContext({width: 1280, height: 900}, engine), page = await pageFor(engineContext);
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
        await page.goto(context.baseUrl + `/event/${encodeURIComponent(fixture.secondEventId)}`);
        await page.goBack();
        record(GATES[2], `${entry.name}-back-route`, context.baseUrl + fixture.event.publicPath, page.url());
        await page.goForward(); await page.reload();
        record(GATES[2], `${entry.name}-forward-reload-route`, context.baseUrl + `/event/${encodeURIComponent(fixture.secondEventId)}`, page.url());
        await page.setViewportSize({width: 390, height: 844});
        await page.goto(context.baseUrl + fixture.event.publicPath);
        await page.evaluate(() => {
          const sizes = [...document.querySelectorAll('h1,h2,p,a,dt,dd,button,label,input')].map((node) => [node, parseFloat(getComputedStyle(node).fontSize)]);
          for (const [node, size] of sizes) node.style.fontSize = `${size * 2}px`;
        });
        record(GATES[3], `${entry.name}-390-200-percent-no-overflow`, true, await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
        await screenshot(GATES[3], page, `${entry.name}-390-200percent.png`);
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
    fs.writeFileSync(path.join(outputDir, 'browser-network.json'), JSON.stringify({blocked, browserErrors}, null, 2));
    for (const gate of GATES) gates[gate].rawPaths.push('browser-network.json');
    return {gates, observedDeploymentIdentity: identity};
  } finally {
    await browser.close();
    await Promise.allSettled([...identityObservations]);
    // Keep the cleanup manifest even when candidate identity or a browser
    // operation fails before a gate report can be produced.
    fs.writeFileSync(path.join(outputDir, 'fixture-created-identities.json'), JSON.stringify({runId: fixture.runId,
      projectId: context.projectId, anonymousUids: [...anonymousUids].sort()}, null, 2));
  }
}

module.exports = produce;
module.exports.produce = produce;
module.exports._test = {validateFixture, allowStagingRequest, parseCsv, signedFixtureUrl, createdAnonymousUid, requirePassingBrowserJourneys, preflightBrandedBrowsers};
