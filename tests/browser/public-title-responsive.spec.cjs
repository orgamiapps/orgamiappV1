'use strict';

const {test, expect} = require('@playwright/test');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {memoryAdmin} = require('../../functions/test/helpers/community-memory');
const {createPublicWeb} = require('../../functions/public-web/renderer');
const {htmlResponsiveProbe} = require('../../tools/web_release_producers/safari');

// Exercise the real server renderer and shipped assets with an in-memory read
// boundary. All browser requests are intercepted; no Auth, provider or database
// connection is needed for these static layout regressions.
async function renderedPage(kind, title) {
  const previous = Object.fromEntries(['GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT', 'FUNCTIONS_EMULATOR']
    .map((name) => [name, process.env[name]]));
  Object.assign(process.env, {GCLOUD_PROJECT: 'demo-attendus-admin', GOOGLE_CLOUD_PROJECT: 'demo-attendus-admin', FUNCTIONS_EMULATOR: 'true'});
  const rows = {
    'AppConfig/publicWeb': {publicPagesEnabled: true, inlineRegistrationEnabled: true, accountlessRegistrationEnabled: true},
    'Events/layout': {title, description: 'Controlled layout fixture.', private: false, status: 'active',
      selectedDateTime: '2035-10-04T15:15:00Z', eventDuration: 2, eventTimeZone: 'America/New_York',
      imageUrl: 'https://layout.invalid/public-web/v1/event-fallback.svg',
      locationType: 'in_person', location: 'Controlled venue', ticketsEnabled: false,
      confirmedRegistrationCount: 0, issuedTickets: 0, reservedTickets: 0},
    'Organizations/layout': {name: title, description: 'Controlled community fixture.', publicPageEnabled: true,
      bannerUrl: 'https://layout.invalid/public-web/v1/event-fallback.svg'},
  };
  const query = {where() { return this; }, limit() { return this; }, async get() { return {docs: []}; }};
  const db = {collection(name) { return {...query, doc(id) {
    const data = rows[`${name}/${id}`];
    return {async get() { return {exists: !!data, data: () => data, ref: {collection: () => query}}; }};
  }}; }};
  let status, html;
  const response = {set() { return this; }, status(value) { status = value; return this; }, send(value) { html = value; return this; }};
  try {
    await createPublicWeb({firestore: () => db})({method: 'GET', path: `/${kind}/layout`}, response);
    expect(status).toBe(200);
    return html;
  } finally {
    for (const [name, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[name]; else process.env[name] = value;
    }
  }
}

// These manage-page cases exercise real HTTP handlers with a known synthetic
// session at the in-memory server boundary. They cover rendered status/actions,
// not browser cookie transport or token exchange. No registration or provider
// mutation is reachable through this GET-only browser boundary.
for (const scenario of [
  {name: 'pending', status: 'pending', label: 'Pending approval'},
  {name: 'waitlisted', status: 'waitlisted', label: 'Waitlisted'},
  {name: 'declined', status: 'declined', label: 'Declined'},
  {name: 'confirmed-rsvp', status: 'confirmed', label: 'Confirmed', method: 'PUBLISH'},
  {name: 'confirmed-ticket', status: 'confirmed', label: 'Confirmed', method: 'PUBLISH', ticket: true},
  {name: 'cancelled', status: 'cancelled', label: 'Cancelled', method: 'CANCEL'},
]) {
  test(`managed ${scenario.name} shows truthful status and eligible artifacts`, async ({page}, info) => {
    const rawSession = 'synthetic_browser_manage_session_1234567890';
    const sessionId = createHash('sha256').update(rawSession).digest('hex');
    const admin = memoryAdmin({
      'AppConfig/publicWeb': {publicPagesEnabled: true},
      [`GuestManageSessions/${sessionId}`]: {status: 'active', registrationId: 'registration', guestId: 'guest',
        csrfToken: 'synthetic-csrf', expiresAt: new Date(Date.now() + 2 * 3600000)},
      'RegisterAttendance/registration': {eventId: 'event', guestId: 'guest', realName: 'Controlled guest',
        status: scenario.status, ...(scenario.ticket ? {ticketId: 'ticket'} : {})},
      'GuestAttendees/guest': {maskedEmail: 'c***@qualification.example.test'},
      'Events/event': {title: 'Controlled registration status', status: 'active',
        selectedDateTime: new Date('2035-10-04T15:15:00Z'), eventDurationMinutes: 90, eventTimeZone: 'UTC',
        ticketsEnabled: !!scenario.ticket},
      ...(scenario.ticket ? {'Tickets/ticket': {eventId: 'event', registrationId: 'registration', guestId: 'guest',
        ticketCode: 'A1B2C3D4', price: 0}} : {}),
    });
    const handler = createPublicWeb(admin);
    const unexpected = [];
    const webRoot = path.resolve(__dirname, '../../web');
    await page.route('**/*', async (route) => {
      const request = route.request(), url = new URL(request.url());
      if (url.origin !== 'https://layout.invalid' || request.method() !== 'GET') {
        unexpected.push({origin: url.origin, method: request.method()}); return route.abort();
      }
      if (['/manage', '/manage/calendar.ics', '/manage/ticket.svg'].includes(url.pathname)) {
        let status = 200, body = '';
        const headers = {};
        const response = {set(key, value) {headers[key] = value; return this;},
          status(value) {status = value; return this;}, type(value) {headers['Content-Type'] = value; return this;},
          send(value) {body = value; return this;}, end() {return this;}};
        await handler({method: 'GET', path: url.pathname,
          get: (name) => name === 'cookie' ? `attendus_guest_manage=${rawSession}` : undefined}, response);
        return route.fulfill({status, headers: {'Content-Type': 'text/html', ...headers}, body});
      }
      if (/^\/public-web\/v1\/assets\/[a-f0-9]{64}\/(?:public|registration-email-v2)\.css$/.test(url.pathname) || url.pathname === '/icons/Icon-192.png') {
        return route.fulfill({status: 200, path: path.join(webRoot, url.pathname.slice(1)),
          contentType: url.pathname.endsWith('.css') ? 'text/css' : 'image/png'});
      }
      unexpected.push({path: url.pathname, method: request.method()}); return route.abort();
    });
    await page.setViewportSize({width: 320, height: 844});
    expect((await page.goto('https://layout.invalid/manage')).status()).toBe(200);
    await expect(page.getByRole('heading', {level: 1})).toHaveText('Controlled registration status');
    await expect.poll(() => page.locator('.brand img').evaluate((image) => image.complete && image.naturalWidth > 0)).toBe(true);
    const status = await page.locator('.details > div').filter({has: page.locator('dt', {hasText: /^Status$/})}).locator('dd').textContent();
    const artifacts = await page.evaluate(async () => {
      const results = {};
      for (const name of ['calendar.ics', 'ticket.svg']) {
        const response = await fetch(`/manage/${name}`);
        results[name] = {status: response.status, body: await response.text()};
      }
      return results;
    });
    const bounds = await page.evaluate(htmlResponsiveProbe);
    const ticketBounds = scenario.ticket ? await page.locator('.ticket-code').evaluate((element) => {
      const box = element.getBoundingClientRect(), style = getComputedStyle(element);
      const content = {left: box.left + parseFloat(style.borderLeftWidth) + parseFloat(style.paddingLeft),
        right: box.right - parseFloat(style.borderRightWidth) - parseFloat(style.paddingRight)};
      const range = document.createRange(); range.selectNodeContents(element.querySelector('strong'));
      const image = element.querySelector('img').getBoundingClientRect();
      return {content, image: {left: image.left, right: image.right, width: image.width, height: image.height},
        codeText: element.querySelector('strong').textContent,
        codeBoxes: [...range.getClientRects()].map((rect) => ({left: rect.left, right: rect.right}))};
    }) : null;
    const detailBounds = await page.locator('.details').evaluate((element) => {
      const box = element.getBoundingClientRect();
      return {left: box.left, right: box.right, values: [...element.querySelectorAll('dt,dd')].map((value) => {
        const range = document.createRange(); range.selectNodeContents(value);
        return {text: value.textContent, overflow: getComputedStyle(value).overflowX,
          textBoxes: [...range.getClientRects()].map((rect) => ({left: rect.left, right: rect.right}))};
      })};
    });
    await page.getByText('Update confirmation email', {exact: true}).click();
    await expect(page.getByRole('textbox', {name: 'Email address', exact: true})).toBeVisible();
    const expandedBounds = await page.evaluate(htmlResponsiveProbe);
    const contactBounds = await page.locator('.contact-update').evaluate((element) => {
      const box = element.getBoundingClientRect();
      return {left: box.left, right: box.right, pageFits: document.documentElement.scrollWidth <= window.innerWidth + 1,
        controls: [...element.querySelectorAll('input:not([type=hidden]),button')].map((control) => {
          const rect = control.getBoundingClientRect();
          return {tag: control.tagName, left: rect.left, right: rect.right};
        })};
    });
    // Reset the scroll position before full-page capture so offscreen fixed
    // skip links remain outside the captured page rather than over its middle.
    await page.evaluate(() => window.scrollTo({top: 0, left: 0, behavior: 'instant'}));
    await page.screenshot({path: info.outputPath(`manage-${scenario.name}-320px-200percent.png`), fullPage: true});
    await info.attach('status-and-artifacts.json', {body: JSON.stringify({status, artifacts, bounds, ticketBounds, detailBounds, expandedBounds, contactBounds, unexpected}), contentType: 'application/json'});
    expect(status).toBe(scenario.label);
    expect(bounds.textIs200Percent).toBe(true); expect(bounds.pageFits).toBe(true);
    for (const value of detailBounds.values) {
      expect(['hidden', 'clip']).not.toContain(value.overflow);
      for (const box of value.textBoxes) {
        expect(box.left).toBeGreaterThanOrEqual(detailBounds.left - 1);
        expect(box.right).toBeLessThanOrEqual(detailBounds.right + 1);
      }
    }
    expect(contactBounds.pageFits).toBe(true);
    expect(expandedBounds.textIs200Percent).toBe(true);
    for (const box of contactBounds.controls) {
      expect(box.left).toBeGreaterThanOrEqual(contactBounds.left - 1);
      expect(box.right).toBeLessThanOrEqual(contactBounds.right + 1);
    }
    expect(unexpected).toEqual([]);
    const pass = page.getByRole('link', {name: 'Check in or get my event pass', exact: true});
    const calendar = page.getByRole('link', {name: 'Download calendar invite', exact: true});
    if (scenario.method === 'PUBLISH') await expect(pass).toBeVisible(); else await expect(pass).toHaveCount(0);
    if (scenario.method) {
      await expect(calendar).toBeVisible();
      expect(artifacts['calendar.ics'].status).toBe(200);
      expect(artifacts['calendar.ics'].body).toContain(`METHOD:${scenario.method}`);
      expect(artifacts['calendar.ics'].body).toContain('DTSTART:20351004T151500Z');
      expect(artifacts['calendar.ics'].body).toContain('DTEND:20351004T164500Z');
    } else {
      await expect(calendar).toHaveCount(0);
      expect(artifacts['calendar.ics'].status).toBe(409);
      expect(artifacts['calendar.ics'].body).not.toContain('METHOD:PUBLISH');
    }
    if (scenario.ticket) {
      await expect(page.getByRole('heading', {name: 'Your ticket', exact: true})).toBeVisible();
      await expect.poll(() => page.locator('.ticket-code img').evaluate((image) => image.complete && image.naturalWidth > 0)).toBe(true);
      expect(artifacts['ticket.svg'].status).toBe(200);
      expect(artifacts['ticket.svg'].body).toContain('<svg');
      expect(ticketBounds.codeText).toBe('A1B2C3D4');
      expect(ticketBounds.image.width).toBeCloseTo(ticketBounds.image.height, 1);
      for (const box of [ticketBounds.image, ...ticketBounds.codeBoxes]) {
        expect(box.left).toBeGreaterThanOrEqual(ticketBounds.content.left - 1);
        expect(box.right).toBeLessThanOrEqual(ticketBounds.content.right + 1);
      }
    } else {
      await expect(page.locator('.manage-ticket')).toHaveCount(0);
      expect(artifacts['ticket.svg'].status).toBe(404);
    }
  });
}

for (const [kind, label, title] of [
  ['event', 'qualification-title', 'Controlled web qualification pilot'],
  ['event', 'unbroken-title', 'CommunityQualificationCelebrationWithoutWordBoundaries'],
  ['community', 'community-name', 'CommunityQualificationCelebrationWithoutWordBoundaries'],
]) {
  test(`${label} wraps without hiding content at 320px and actual 200-percent text`, async ({page}, info) => {
    const html = await renderedPage(kind, title);
    const webRoot = path.resolve(__dirname, '../../web');
    await page.route('**/*', async (route) => {
      const url = new URL(route.request().url());
      if (url.origin !== 'https://layout.invalid' || route.request().method() !== 'GET') return route.abort();
      if (url.pathname === `/${kind}/layout`) return route.fulfill({status: 200, contentType: 'text/html', body: html});
      // Only real local visual assets, never executable scripts or SDK requests.
      if (/^\/public-web\/v1\/(?:assets\/[a-f0-9]{64}\/(?:public|registration-email-v2)\.css|event-fallback\.svg)$/.test(url.pathname) || url.pathname === '/icons/Icon-192.png') {
        return route.fulfill({status: 200, path: path.join(webRoot, url.pathname.slice(1)),
          contentType: url.pathname.endsWith('.css') ? 'text/css' : url.pathname.endsWith('.svg') ? 'image/svg+xml' : 'image/png'});
      }
      return route.abort();
    });
    await page.setViewportSize({width: 320, height: 844});
    await page.goto(`https://layout.invalid/${kind}/layout`);
    await expect(page.getByRole('heading', {level: 1})).toHaveText(title);
    await expect.poll(() => page.locator('.hero img,.community-hero img').evaluate((image) => image.complete && image.naturalWidth > 0)).toBe(true);
    const before = await page.locator('h1').evaluate((element) => parseFloat(getComputedStyle(element).fontSize));
    const result = await page.evaluate(htmlResponsiveProbe);
    const heading = await page.locator('h1').evaluate((element) => {
      const range = document.createRange(); range.selectNodeContents(element);
      return {text: element.textContent, size: parseFloat(getComputedStyle(element).fontSize),
        overflow: getComputedStyle(element).overflowX,
        textBoxes: [...range.getClientRects()].map((rect) => ({left: rect.left, right: rect.right}))};
    });
    await page.screenshot({path: info.outputPath(`${label}-320px-200percent.png`), fullPage: true});
    await info.attach('actual-text-and-bounds.json', {body: JSON.stringify({result, heading}), contentType: 'application/json'});
    expect(result.textIs200Percent).toBe(true);
    expect(heading.size).toBeCloseTo(before * 2, 1);
    expect(heading.text).toBe(title);
    expect(['hidden', 'clip']).not.toContain(heading.overflow);
    expect(result.pageFits).toBe(true);
    for (const box of heading.textBoxes) {
      expect(box.left).toBeGreaterThanOrEqual(0);
      expect(box.right).toBeLessThanOrEqual(321);
    }
  });
}
