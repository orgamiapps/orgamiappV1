'use strict';
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const {files, gitSourceFiles} = require('../web_release_contract');
const sha = (value) => crypto.createHash('sha256').update(value).digest('hex');

function verifyTree(root, expected) {
  if (!root || !path.isAbsolute(root) || !expected || !Object.keys(expected).length) throw Error('Missing verified artifact directory/manifest.');
  const actual = files(root);
  if (JSON.stringify(Object.entries(actual).sort()) !== JSON.stringify(Object.entries(expected).sort())) throw Error('Cache transition artifact bytes differ from their captured manifest.');
  return JSON.parse(fs.readFileSync(path.join(root, 'release-manifest.json'), 'utf8'));
}
function artifactPath(root, pathname) {
  const decoded = decodeURIComponent(pathname);
  if (decoded.includes('\\') || decoded.includes('\0') || decoded.split('/').includes('..')) throw Error('Unsafe artifact request path.');
  const relative = decoded.replace(/^\/+/, '');
  const resolved = path.resolve(root, relative || 'index.html');
  if (resolved !== root && !resolved.startsWith(root + path.sep)) throw Error('Artifact request escaped root.');
  return resolved;
}
const types = {'.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json', '.wasm': 'application/wasm',
  '.png': 'image/png', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.ttf': 'font/ttf'};

function verifyFirebaseApps(apps, expected) {
  if (!Array.isArray(apps) || !apps.length) throw Error('Predecessor exposes no initialized Firebase application.');
  return apps.map(({name, options}) => {
    if (!options || ['projectId', 'apiKey', 'appId', 'storageBucket'].some((key) => options[key] !== expected[key]) ||
        (options.authDomain && !['attendus-staging.firebaseapp.com', 'attendus-staging.web.app'].includes(options.authDomain))) {
      throw Error('Predecessor Firebase application options are not the verified staging configuration.');
    }
    return {name, projectId: options.projectId, appId: options.appId, storageBucket: options.storageBucket, apiKeySha256: sha(options.apiKey)};
  });
}

function verifyMessagingWorker(source, expected) {
  // Parse only literal options. Never execute an unverified worker to discover
  // its destination, and reject dynamic initialization/configuration.
  const initializations = [...source.matchAll(/firebase\.initializeApp\(\s*(\{[^{}]*\}|[A-Za-z_$][\w$]*)\s*\)/g)];
  if (initializations.length !== 1) throw Error('Predecessor messaging worker has an unverifiable Firebase initialization.');
  let literal = initializations[0][1];
  if (!literal.startsWith('{')) {
    const escaped = literal.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    literal = new RegExp(`(?:const|let|var)\\s+${escaped}\\s*=\\s*(\\{[^{}]*\\})`).exec(source)?.[1];
  }
  if (!literal) throw Error('Predecessor messaging worker configuration is not literal.');
  const options = {};
  for (const match of literal.matchAll(/(?:["']?)([A-Za-z][A-Za-z0-9]*)(?:["']?)\s*:\s*(["'])([A-Za-z0-9_:./-]+)\2/g)) options[match[1]] = match[3];
  verifyFirebaseApps([{name: 'messaging-worker', options}], expected);
  const imports = [...source.matchAll(/importScripts\(\s*(['"])([^'"]+)\1\s*\)/g)].map((match) => match[2]);
  if (!imports.length || imports.some((value) => !/^https:\/\/www\.gstatic\.com\/firebasejs\/[0-9.]+\/firebase-(app|messaging)-compat\.js$/.test(value))) {
    throw Error('Predecessor messaging worker imports are not verified Firebase SDK assets.');
  }
  return {sha256: sha(source), projectId: options.projectId, appId: options.appId, imports};
}

async function produce({browser, context, candidate, outputDir, observeCreatedIdentities}) {
  const assertions = [], rawPaths = [], blockers = [];
  const committedHelpers = gitSourceFiles(path.resolve(__dirname, '../..'), 'tools/web_release_producers/');
  const helperBytes = committedHelpers['tools/web_release_producers/browser-cache-upgrade.js'];
  if (!helperBytes || candidate.sourceFiles?.['tools/web_release_producers/browser-cache-upgrade.js'] !== sha(helperBytes)) {
    throw Error('Cache producer source differs from the frozen candidate.');
  }
  const artifacts = context.artifacts;
  if (!artifacts || artifacts.previousStagingHostingVersion !== candidate.predecessor?.staging?.hostingVersion) {
    return {assertions, rawPaths, blockers: ['A captured previous staging Hosting artifact bound to the candidate predecessor is required.']};
  }
  const previous = verifyTree(artifacts.previousStagingRoot, artifacts.previousStagingFiles);
  const current = verifyTree(artifacts.webRoot, candidate.webFiles);
  if (current.currentRelease !== candidate.releaseId || previous.currentRelease === candidate.releaseId) throw Error('Cache upgrade requires distinct, correctly bound predecessor and candidate releases.');
  const workerProof = verifyMessagingWorker(fs.readFileSync(path.join(artifacts.previousStagingRoot, 'firebase-messaging-sw.js'), 'utf8'), context.fixture.firebase);
  let phase = 'previous', activeRoot = artifacts.previousStagingRoot;
  const served = [], blocked = [];
  const server = http.createServer((request, response) => {
    try {
      if (!['GET', 'HEAD'].includes(request.method)) {response.writeHead(405); response.end(); return;}
      let file = artifactPath(activeRoot, new URL(request.url, 'http://localhost').pathname);
      if (!fs.existsSync(file) || !fs.statSync(file).isFile()) file = path.join(activeRoot, 'index.html');
      const bytes = fs.readFileSync(file), relative = path.relative(activeRoot, file).replaceAll('\\', '/');
      served.push({phase, path: relative, sha256: sha(bytes)});
      response.writeHead(200, {'content-type': types[path.extname(file)] || 'application/octet-stream',
        'cache-control': relative.startsWith('releases/') ? 'public,max-age=31536000,immutable' : 'no-cache,max-age=0,must-revalidate'});
      response.end(request.method === 'HEAD' ? undefined : bytes);
    } catch {response.writeHead(400); response.end();}
  });
  await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
  // localhost is explicitly authorized by the staging App Check site key.
  // Chromium resolves its IPv4 loopback address to the owned listener below.
  const port = server.address().port, origin = `http://localhost:${port}`;
  const allow = require('./browser')._test.allowStagingRequest;
  async function isolatedContext(serviceWorkers) {
    const isolated = await browser.newContext({viewport: {width: 1280, height: 900}, serviceWorkers});
    await isolated.route('**/*', async (route) => {
    const request = route.request(), url = new URL(request.url());
    const local = ['127.0.0.1', 'localhost'].includes(url.hostname) && url.port === String(port) && url.protocol === 'http:';
    if (local || allow(request.url(), request.method(), context, await request.allHeaders())) return route.continue();
    blocked.push({origin: url.origin, path: url.pathname}); return route.abort('blockedbyclient');
    });
    await isolated.routeWebSocket('**/*', (socket) => socket.close());
    return isolated;
  }
  let browserContext, page, preflight;
  async function createPage(serviceWorkers) {
    browserContext = await isolatedContext(serviceWorkers);
    page = await browserContext.newPage(); observeCreatedIdentities?.(page);
    page.setDefaultTimeout(60000);
  }
  async function ready() {
    await page.waitForFunction(() => performance.getEntriesByName('attendus-first-frame').length > 0, undefined, {timeout: 120000});
    const placeholder = page.locator('flt-semantics-placeholder');
    if (await placeholder.count()) await placeholder.first().click({force: true});
    await page.locator('flt-semantics').first().waitFor();
  }
  async function storageState() {
    return page.evaluate(async () => {
      const databases = await indexedDB.databases();
      let uid = null;
      if (databases.some((db) => db.name === 'firebaseLocalStorageDb')) {
        uid = await new Promise((resolve, reject) => {
          const open = indexedDB.open('firebaseLocalStorageDb');
          open.onerror = () => reject(Error('Cannot inspect browser auth identity.'));
          open.onsuccess = () => {
            const db = open.result;
            if (!db.objectStoreNames.contains('firebaseLocalStorage')) {db.close(); resolve(null); return;}
            const request = db.transaction('firebaseLocalStorage').objectStore('firebaseLocalStorage').getAll();
            request.onsuccess = () => {const user = request.result.find((row) => row.fbase_key?.startsWith('firebase:authUser:')); db.close(); resolve(user?.value?.uid || null);};
            request.onerror = () => {db.close(); reject(Error('Cannot read browser auth identity.'));};
          };
        });
      }
      return {uid, cacheNames: await caches.keys(), workers: (await navigator.serviceWorker.getRegistrations()).map((entry) => (entry.active || entry.waiting || entry.installing)?.scriptURL || null)};
    });
  }
  async function login() {
    await page.getByText('Log in', {exact: true}).last().click();
    if (!await page.getByText('Welcome back', {exact: true}).isVisible()) await page.getByText('Log in', {exact: true}).last().click();
    await page.getByRole('textbox', {name: 'Email address', exact: true}).fill(context.fixture.owner.email);
    await page.getByRole('textbox', {name: 'Password', exact: true}).fill(context.fixture.owner.password);
    await page.getByRole('textbox', {name: 'Password', exact: true}).press('Enter');
    await page.getByText('Welcome back', {exact: true}).waitFor({state: 'hidden'});
  }
  try {
    await createPage('block');
    await page.goto(origin + '/app/discover'); await ready();
    const options = await page.evaluate(() => (globalThis.firebase_core?.getApps?.() || globalThis.firebase?.apps || [])
      .map((app) => ({name: app.name, options: {...app.options}})));
    const apps = verifyFirebaseApps(options, context.fixture.firebase);
    await login();
    const isolatedState = await storageState();
    if (isolatedState.uid !== context.fixture.owner.uid || isolatedState.workers.length || blocked.length) {
      throw Error('Worker-blocked predecessor login or network-isolation preflight failed.');
    }
    preflight = {apps, uid: isolatedState.uid, workers: isolatedState.workers, workerProof};
    assertions.push({id: 'predecessor-runtime-staging-project-before-workers', expected: ['attendus-staging'], actual: [...new Set(apps.map((app) => app.projectId))]});
    assertions.push({id: 'predecessor-no-workers-during-isolation-preflight', expected: [], actual: isolatedState.workers});
    await browserContext.close();
    // Enable workers only after real runtime options/login and the captured
    // messaging worker's literal provider configuration are verified.
    await createPage('allow');
    await page.goto(origin + '/app/discover'); await ready(); await login();
    await page.reload(); await ready();
    const before = await storageState();
    assertions.push({id: 'prior-artifact-authenticated-warm-uid', expected: context.fixture.owner.uid, actual: before.uid});
    assertions.push({id: 'prior-artifact-main-loaded', expected: true, actual: served.some((entry) => entry.phase === 'previous' && entry.path === `releases/${previous.currentRelease}/main.dart.js`)});
    phase = 'candidate'; activeRoot = artifacts.webRoot;
    await page.reload(); await ready();
    const after = await storageState();
    assertions.push({id: 'candidate-preserves-prior-auth-uid', expected: before.uid, actual: after.uid});
    assertions.push({id: 'candidate-main-loaded-after-upgrade', expected: candidate.webFiles[`releases/${candidate.releaseId}/main.dart.js`],
      actual: served.find((entry) => entry.phase === 'candidate' && entry.path === `releases/${candidate.releaseId}/main.dart.js`)?.sha256 || 'not-loaded'});
    assertions.push({id: 'legacy-flutter-worker-retired', expected: false, actual: after.workers.some((url) => url?.includes('flutter_service_worker.js'))});
    assertions.push({id: 'legacy-flutter-caches-retired', expected: [], actual: after.cacheNames.filter((name) => name.startsWith('flutter-'))});
    const screenshot = 'cache-upgrade-candidate.png'; await page.screenshot({path: path.join(outputDir, screenshot)}); rawPaths.push(screenshot);
    const evidence = 'cache-upgrade.json';
    fs.writeFileSync(path.join(outputDir, evidence), JSON.stringify({previousHostingVersion: artifacts.previousStagingHostingVersion,
      previousRelease: previous.currentRelease, candidateRelease: candidate.releaseId, preflight, before, after, served, blocked}, null, 2)); rawPaths.push(evidence);
  } catch (error) {
    let message = String(error.message || error);
    for (const role of ['owner', 'attendee', 'unauthorized']) message = message.split(context.fixture[role].password).join('[redacted]');
    blockers.push(message.replace(/eyJ[A-Za-z0-9_.-]+/g, '[token]'));
    const evidence = 'cache-upgrade-failure.json';
    fs.writeFileSync(path.join(outputDir, evidence), JSON.stringify({phase, previousRelease: previous.currentRelease,
      candidateRelease: candidate.releaseId, served, blocked, blockers}, null, 2)); rawPaths.push(evidence);
  } finally {await browserContext?.close(); await new Promise((resolve) => server.close(resolve));}
  return {assertions, rawPaths, blockers};
}
module.exports = {produce, _test: {artifactPath, verifyTree, verifyFirebaseApps, verifyMessagingWorker}};
