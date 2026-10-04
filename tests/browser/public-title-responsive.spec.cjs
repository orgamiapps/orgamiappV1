'use strict';

const {test, expect} = require('@playwright/test');
const path = require('node:path');
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
      locationType: 'in_person', location: 'Controlled venue', ticketsEnabled: false},
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
