'use strict';
// Build integration_test/event_removal_preview.dart to build/event-removal-preview.
// This drives production widgets with loopback-only auth/data/function fixtures.
const {chromium, expect} = require('@playwright/test');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {allowedBrowserRequest} = require('./network-policy.cjs');
const {activateFlutterSemanticsPage, enterFlutterText} =
  require('../../tools/web_release_producers/flutter-semantics');

const scenarios = process.env.EVENT_REMOVAL_SCENARIOS?.split(',') ||
  ['empty', 'lost-response', 'populated', 'remote', 'direct'];
const titles = {
  empty: 'Creator garden evening',
  'lost-response': 'Lost response garden evening',
  populated: 'Registered community breakfast',
  remote: 'Remote removal garden evening',
  direct: 'Creator garden evening',
};

(async () => {
  const root = path.resolve(__dirname, '../../build/event-removal-preview');
  const output = process.env.EVENT_REMOVAL_EVIDENCE ||
    path.resolve(__dirname, '../../build/event-removal-browser');
  fs.mkdirSync(output, {recursive: true});
  assert(fs.existsSync(path.join(root, 'main.dart.js')), 'Build the loopback preview first');
  const types = {
    '.js': 'text/javascript', '.html': 'text/html', '.json': 'application/json',
    '.wasm': 'application/wasm', '.ttf': 'font/ttf', '.otf': 'font/otf',
    '.png': 'image/png', '.svg': 'image/svg+xml',
  };
  const server = http.createServer((req, res) => {
    const pathname = new URL(req.url, 'http://localhost').pathname;
    if (pathname === '/' || pathname.startsWith('/app/')) {
      res.setHeader('Content-Type', 'text/html');
      res.end('<!doctype html><html><head><base href="/"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head><body><script>window.attendusShowStartupError=e=>console.error(e);</script><script src="flutter_bootstrap.js"></script></body></html>');
      return;
    }
    const file = path.resolve(root, '.' + pathname);
    if (!file.startsWith(root + path.sep) || !fs.existsSync(file)) {
      res.writeHead(404); res.end(); return;
    }
    res.setHeader('Content-Type', types[path.extname(file)] || 'application/octet-stream');
    if (pathname === '/flutter_bootstrap.js') {
      res.end(fs.readFileSync(file, 'utf8').replace(
        '} : {},', '} : {canvasKitBaseUrl: "/canvaskit/"},'));
    } else {
      fs.createReadStream(file).pipe(res);
    }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({headless: true});
  const results = [];
  try {
    for (const [viewportName, viewport] of [
      ['desktop', {width: 1440, height: 1000}],
      ['phone', {width: 390, height: 844}],
    ].filter(([name]) => !process.env.EVENT_REMOVAL_VIEWPORT ||
        process.env.EVENT_REMOVAL_VIEWPORT === name)) {
      const context = await browser.newContext({viewport, deviceScaleFactor: 1});
      const blockedRequests = [];
      await context.route('**/*', route => {
        const request = route.request();
        if (request.url() === 'https://accounts.google.com/gsi/client') {
          return route.fulfill({
            status: 200, contentType: 'text/javascript',
            body: '/* Identity providers are stubbed in the loopback fixture. */',
          });
        }
        if (allowedBrowserRequest(request.url(), request.method())) {
          return route.continue();
        }
        blockedRequests.push({url: request.url(), method: request.method()});
        return route.abort();
      });
      for (const scenario of scenarios) {
        const page = await context.newPage();
        const errors = [];
        const consoleLog = [];
        page.on('pageerror', error => {
          errors.push(error.stack || error.message);
          consoleLog.push(`pageerror: ${error.stack || error.message}`);
        });
        page.on('console', message => {
          consoleLog.push(`${message.type()}: ${message.text()}`);
          if (message.type() === 'error') errors.push(message.text());
        });
        const prefix = `${viewportName}-${scenario}`;
        const eventCard = page.getByRole('button', {name: new RegExp(titles[scenario])}).first();
        const eventNodes = page.getByText(titles[scenario], {exact: true})
          .or(page.getByRole('button', {name: new RegExp(titles[scenario])}))
          .or(page.getByRole('group', {name: new RegExp(titles[scenario])}));
        const result = {viewport: viewportName, scenario, checks: [], pageErrors: errors};
        const capture = name => page.screenshot({path: path.join(output, `${prefix}-${name}.png`)});
        try {
          await page.goto(`http://127.0.0.1:${server.address().port}/?scenario=${scenario}`);
          await activateFlutterSemanticsPage(page, {timeoutMs: 30000});
          await expect(page.getByText(/^Fixture /).first()).toBeAttached({timeout: 60000});
          if (scenario !== 'direct') {
            await expect(eventCard)
              .toBeAttached({timeout: 60000});
            await page.waitForTimeout(250);
            await capture('discover');
          }
          if (scenario === 'remote') {
            await page.getByRole('button', {name: 'Remote delete fixture event', exact: true}).click();
            await expect(eventNodes).toHaveCount(0);
            await expect(page.getByText('Discover', {exact: true}).first()).toBeAttached();
            await capture('removed-without-refresh');
            result.checks.push('source deletion removes open Discover without refresh');
          } else {
            if (scenario !== 'direct') {
              await eventCard.click();
            }
            const manage = page.getByRole('button', {name: 'Manage event', exact: true});
            await expect(manage).toBeEnabled({timeout: 30000});
            await expect(page.getByText('This event requires access', {exact: true})).toHaveCount(0);
            await manage.click();
            await expect(page.getByText('Event Management', {exact: true})).toBeAttached();
            const remove = page.getByText('Delete or cancel event', {exact: true});
            for (let attempt = 0; attempt < 12 && !(await remove.isVisible()); attempt++) {
              await page.mouse.move(viewport.width / 2, viewport.height * 0.7);
              await page.mouse.wheel(0, 600);
              await page.waitForTimeout(100);
            }
            await remove.click({timeout: 15000});
            const actionName = scenario === 'populated' ? 'Review affected attendees' : 'Delete event';
            const action = page.getByRole('button', {name: actionName, exact: true});
            await expect(action).toBeEnabled({timeout: 15000});
            if (scenario === 'populated') {
              await expect(page.getByRole('button', {name: 'Delete event', exact: true})).toHaveCount(0);
              await enterFlutterText(page, 'Reason shared with attendees', 'Venue unavailable');
              await action.click();
              await expect(page.getByText('3 active registrations across the selected occurrences will be notified.', {exact: true}))
                .toBeAttached();
              await capture('cancellation-preview');
              await page.getByRole('button', {name: 'Cancel event', exact: true}).click();
              result.checks.push('populated event uses preview and preserves cancellation reason');
            } else {
              await capture('confirmation');
              await action.click();
            }
            const confirmation = scenario === 'populated' ? 'Event cancelled' : 'Event deleted';
            await expect(page.getByText(confirmation, {exact: true}).last()).toBeVisible({timeout: 20000});
            await expect(page.getByText('Discover', {exact: true}).first()).toBeAttached();
            await expect(eventNodes).toHaveCount(0);
            await expect(page.getByText('Event Management', {exact: true})).toHaveCount(0);
            await capture('success');
            result.checks.push('success visible', 'event and organizer routes closed', 'event absent from originating list');
            if (scenario === 'lost-response') {
              await expect(page.getByText('Fixture lost-response: calls=2 commits=1 replays=1', {exact: true})).toBeAttached();
              result.checks.push('lost response retries the same receipt with one commit');
            } else if (scenario === 'populated') {
              await expect(page.getByText('Fixture populated: calls=1 commits=1 replays=0 reason=Venue unavailable', {exact: true}))
                .toBeAttached();
            } else {
              await expect(page.getByText(`Fixture ${scenario}: calls=1 commits=1 replays=0`, {exact: true})).toBeAttached();
            }
            if (scenario === 'direct') result.checks.push('direct event root falls back to Discover');
          }
          if (scenario !== 'populated') {
            await page.getByRole('button', {name: 'Open fixture link', exact: true}).click();
            await expect(page.getByText('Event unavailable', {exact: true})).toBeAttached({timeout: 15000});
            await expect(page.getByText('This event requires access', {exact: true})).toHaveCount(0);
            await capture('deleted-link');
            result.checks.push('deleted link is unavailable instead of access request');
          }
          assert.deepEqual(errors, [], `${prefix} browser errors`);
          result.result = 'passed';
        } catch (error) {
          result.result = 'failed';
          result.error = error.stack || String(error);
          await capture('failed').catch(() => {});
          fs.writeFileSync(path.join(output, `${prefix}-failed.html`),
            await page.content().catch(() => 'Page unavailable'));
          console.error(`${prefix}: ${error.message}`);
        } finally {
          fs.writeFileSync(path.join(output, `${prefix}-console.log`), consoleLog.join('\n'));
          results.push(result);
          console.log(`${prefix}: ${result.result}`);
          await page.close();
        }
      }
      fs.writeFileSync(path.join(output, `${viewportName}-blocked-requests.json`),
        JSON.stringify(blockedRequests, null, 2));
      await context.close();
    }
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify({
      provenance: 'Loopback Flutter production widgets with fake Firebase delegates and blocked provider writes',
      browser: 'Headless Chromium; desktop and phone viewport layouts',
      mainDartJsSha256: crypto.createHash('sha256')
        .update(fs.readFileSync(path.join(root, 'main.dart.js'))).digest('hex'),
      physicalSafariQualified: false,
      results,
    }, null, 2));
    assert(results.every(result => result.result === 'passed'), 'Some browser scenarios failed; retained evidence contains details');
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => {console.error(error); process.exitCode = 1;});
