// Run under Firebase emulators:exec --only auth --project demo-attendus-admin.
// Build integration_test/web_session_harness.dart into build/web-auth-session first.
const {chromium, firefox, webkit} = require('@playwright/test');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {allowedBrowserRequest} = require('./network-policy.cjs');

(async () => {
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9190');
  const root = path.resolve(__dirname, '../../build/web-auth-session');
  const types = {'.css': 'text/css', '.js': 'text/javascript', '.html': 'text/html', '.json': 'application/json', '.wasm': 'application/wasm'};
  const server = http.createServer((req, res) => {
    if (new URL(req.url, 'http://localhost').pathname === '/') {
      res.setHeader('Content-Type', 'text/html');
      // FlutterFire hydrates Auth during Firebase.initializeApp, before Dart's
      // useAuthEmulator call. Configure the same SDK/app first so a restarted
      // emulator session is never validated against production.
      res.end(`<!doctype html><html><head><base href="/"><style>flutter-view{display:none}</style></head><body>
        <script type="module">
          import {initializeApp} from 'https://www.gstatic.com/firebasejs/12.15.0/firebase-app.js';
          import {initializeAuth,connectAuthEmulator,indexedDBLocalPersistence,browserLocalPersistence,browserSessionPersistence,browserPopupRedirectResolver,debugErrorMap} from 'https://www.gstatic.com/firebasejs/12.15.0/firebase-auth.js';
          const app = initializeApp({apiKey:'fake-api-key',appId:'1:123:web:test',messagingSenderId:'123',projectId:'demo-attendus-admin',authDomain:'127.0.0.1'});
          const auth = initializeAuth(app,{errorMap:debugErrorMap,persistence:[indexedDBLocalPersistence,browserLocalPersistence,browserSessionPersistence],popupRedirectResolver:browserPopupRedirectResolver});
          connectAuthEmulator(auth,'http://127.0.0.1:9190');
          const script = document.createElement('script'); script.src='flutter_bootstrap.js'; document.body.appendChild(script);
        </script></body></html>`);
      return;
    }
    const file = path.resolve(root, '.' + new URL(req.url, 'http://localhost').pathname.replace(/\/$/, '/index.html'));
    if (!file.startsWith(root + path.sep) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
    res.setHeader('Content-Type', types[path.extname(file)] || 'application/octet-stream');
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}/`;
  try {
    const selected = process.env.ATTENDUS_SESSION_BROWSERS?.split(',');
    for (const [name, browser, options, legacy] of [
      ['chromium', chromium, {}], ['firefox', firefox, {}], ['webkit', webkit, {}],
      ['mobile-chromium', chromium, {isMobile: true, viewport: {width: 390, height: 844}}],
      ['chromium-legacy', chromium, {}, true],
    ].filter(([name]) => !selected || selected.includes(name))) {
      const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'attendus-session-'));
      let context;
      let starts = 0;
      const open = async () => {
        context = await browser.launchPersistentContext(profile, {headless: true, timeout: 60000, ...options});
        context.setDefaultTimeout(60000);
        await context.route('**/*', route => allowedBrowserRequest(route.request().url(), route.request().method())
          ? route.continue() : route.abort('blockedbyclient'));
        const page = await context.newPage();
        page.on('pageerror', error => console.error(`${name}: ${error.message.slice(0, 400)}`));
        page.on('console', message => { if (message.type() === 'error') console.error(`${name}: ${message.text().slice(0, 400)}`); });
        page.on('requestfailed', request => console.error(`${name}: request failed ${new URL(request.url()).hostname} ${request.failure()?.errorText}`));
        console.log(`${name}: opening harness`);
        await page.goto(legacy && starts++ === 0 ? `${url}?legacy=1` : url);
        await page.locator('#session-status, #session-error').waitFor({timeout: 60000});
        if (await page.locator('#session-error').count()) throw new Error(await page.locator('#session-error').textContent());
        return page;
      };
      try {
        let page = await open();
        assert.equal(await page.locator('#session-status').textContent(), 'signed-out');
        await page.locator('#email').fill(`restart-${randomUUID()}@example.test`);
        await page.getByRole('button', {name: 'Create test account'}).click();
        await page.waitForFunction(() => document.querySelector('#session-status').textContent.startsWith('account:'));
        const identity = await page.locator('#session-status').textContent();
        await context.close(); // Actually terminate the process; no storageState injection.
        page = await open();
        assert.equal(await page.locator('#session-status').textContent(), identity, `${name}: browser restart`);
        await page.reload();
        await page.locator('#session-status').waitFor();
        assert.equal(await page.locator('#session-status').textContent(), identity);
        const second = await context.newPage();
        await second.goto(url);
        await second.locator('#session-status').waitFor();
        assert.equal(await second.locator('#session-status').textContent(), identity);
        console.log(`${name}: restart, reload, second tab verified; original tab signed in = ${(await page.locator('#session-status').textContent()) === identity}`);
        assert.equal(await page.locator('#session-status').textContent(), identity, 'opening another tab must not sign out the original tab');
        await page.getByRole('button', {name: 'Log out', exact: true}).click();
        await second.waitForFunction(() => document.querySelector('#session-status').textContent === 'signed-out');
        await context.close();
        page = await open();
        assert.equal(await page.locator('#session-status').textContent(), 'signed-out');
        console.log(`${name}: restart, reload, second tab, cross-tab logout, reopened logout PASS`);
      } finally {
        await context?.close();
        // Delete only this harness's freshly allocated temporary profile.
        assert.equal(path.dirname(path.resolve(profile)), path.resolve(os.tmpdir()));
        assert.ok(path.basename(profile).startsWith('attendus-session-'));
        fs.rmSync(profile, {recursive: true, force: true});
      }
    }
  } finally { await new Promise(resolve => server.close(resolve)); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
