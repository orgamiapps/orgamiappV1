const {test, expect} = require('@playwright/test');
const {allowedBrowserRequest} = require('./network-policy.cjs');
const fixtureHeaders = {'x-fixture-token': process.env.ATTENDUS_FIXTURE_TOKEN};

test.beforeEach(async ({page}) => {
  // Allow SDK delivery only. Authentication, callable and data traffic must stay local.
  await page.route('**/*', (route) => {
    if (allowedBrowserRequest(route.request().url(), route.request().method())) return route.continue();
    return route.abort('blockedbyclient');
  });
});

async function fixture(request, name, project, body = {}) {
  const id = `${process.env.ATTENDUS_BROWSER_RUN_ID}-${project}-${name}-${Date.now()}`;
  expect((await request.post(`/__fixtures/${id}`, {data: body, headers: fixtureHeaders})).ok()).toBeTruthy();
  return id;
}

test('public page renders safely and keeps private events unavailable', async ({page, request}, info) => {
  const id = await fixture(request, 'public', info.project.name);
  const response = await page.goto(`/event/${id}`);
  expect(response.status()).toBe(200);
  await expect(page.getByRole('heading', {name: 'Browser fixture event'})).toBeVisible();
  await expect.poll(() => page.locator('.brand img').evaluate((img) => img.complete && img.naturalWidth > 0)).toBe(true);
  expect(response.headers()['content-security-policy']).toContain('http://127.0.0.1:5101');
  const config = JSON.parse(await page.locator('#attendus-public-config').textContent());
  expect(config.firebase.projectId).toBe('demo-attendus-admin');
  const hidden = await fixture(request, 'private', info.project.name, {private: true});
  expect((await page.goto(`/event/${hidden}`)).status()).toBe(404);
  await expect(page.getByRole('heading', {name: 'Page not found'})).toBeVisible();
  for (const flag of ['hidden', 'deleted']) {
    const blocked = await fixture(request, flag, info.project.name, {[flag]: true});
    expect((await page.goto(`/event/${blocked}`)).status()).toBe(404);
  }
});

test('guest registers with required answer; lost acknowledgment retries one admission', async ({page, request}, info) => {
  const id = await fixture(request, 'retry', info.project.name);
  let dropped = false;
  const keys = [];
  await page.route('**/startPublicRegistrationV3', async (route) => {
    if (route.request().method() !== 'POST') return route.continue();
    keys.push(route.request().postDataJSON().data.idempotencyKey);
    const response = await route.fetch();
    if (!dropped) { dropped = true; return route.abort('failed'); }
    return route.fulfill({response});
  });
  await page.goto(`/event/${id}`);
  await page.locator('[data-public-action]:visible').first().click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await dialog.getByLabel('Full name', {exact: true}).fill('Browser Guest');
  await dialog.getByLabel('Email address', {exact: true}).fill(`${id}@example.test`);
  await dialog.getByLabel('Accessibility needs', {exact: true}).fill('Step-free access');
  const submit = dialog.getByRole('button', {name: 'Get ticket', exact: true});
  await submit.click();
  await expect(dialog.locator('.dialog-status')).toHaveClass(/error/);
  await expect(submit).toBeEnabled();
  await submit.click();
  await expect(dialog.locator('.dialog-status')).toHaveText('Confirmation complete.');
  expect(keys.length).toBeGreaterThanOrEqual(2);
  expect(new Set(keys).size).toBe(1);
  expect(await (await request.get(`/__fixtures/${id}`, {headers: fixtureHeaders})).json()).toMatchObject({confirmed: 1, registrations: 1});
  await expect.poll(async () => (await (await request.get(`/__fixtures/${id}`, {headers: fixtureHeaders})).json()).capturedDeliveries,
    {timeout: 180000}).toBe(1);
  await dialog.getByRole('button', {name: 'Close', exact: true}).click();
  await expect(dialog).toHaveCount(0);
});

test('cancelled events offer no registration and small viewports do not overflow', async ({page, request}, info) => {
  const id = await fixture(request, 'cancelled', info.project.name, {cancelled: true});
  await page.setViewportSize({width: 320, height: 700});
  await page.goto(`/event/${id}`);
  await expect(page.locator('[data-public-action]')).toHaveCount(0);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBeTruthy();
  await page.screenshot({path: info.outputPath('cancelled-320px.png'), fullPage: true});
  await page.evaluate(() => {
    const sizes = [...document.querySelectorAll('h1,h2,p,a,dt,dd,button')]
      .map((element) => [element, parseFloat(getComputedStyle(element).fontSize)]);
    for (const [element, size] of sizes) element.style.fontSize = `${size * 2}px`;
  });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBeTruthy();
  await page.screenshot({path: info.outputPath('cancelled-320px-200percent.png'), fullPage: true});
  expect(await page.locator('.skip-link').evaluate((link) => link.getBoundingClientRect().bottom)).toBeLessThanOrEqual(0);
  await page.bringToFront();
  if (info.project.name === 'webkit') {
    // Windows WebKit skips links with both Tab and Alt+Tab in this runtime.
    // Verify focused presentation here; real Safari keyboard traversal is a
    // separate device acceptance gate, not implied by programmatic focus.
    await page.locator('.skip-link').focus();
    info.annotations.push({type: 'acceptance-gap', description: 'Safari skip-link keyboard traversal requires device verification.'});
  } else {
    await page.keyboard.press('Tab');
  }
  await expect(page.locator('.skip-link')).toBeFocused();
  expect(await page.locator('.skip-link').evaluate((link) => link.getBoundingClientRect().top)).toBeGreaterThanOrEqual(0);
});

test('disabled paid checkout makes no registration request', async ({page, request}, info) => {
  const id = await fixture(request, 'paid', info.project.name, {paid: true});
  const calls = [];
  page.on('request', (req) => { if (/startPublicRegistration/.test(req.url())) calls.push(req.url()); });
  await page.goto(`/event/${id}`);
  const trigger = page.locator('[data-public-action]:visible').first();
  await trigger.focus();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', {name: 'Paid checkout is temporarily unavailable'})).toBeVisible();
  expect(calls).toEqual([]);
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(trigger).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', {name: 'Paid checkout is temporarily unavailable'})).toBeVisible();
  expect(calls).toEqual([]);
});

test('registration stays keyboard-operable at narrow width and 200-percent text', async ({page, request}, info) => {
  const id = await fixture(request, 'keyboard', info.project.name);
  await page.setViewportSize({width: 390, height: 844});
  await page.goto(`/event/${id}`);
  const trigger = page.locator('[data-public-action]:visible').first();
  await trigger.focus();
  await page.keyboard.press('Enter');
  const dialog = page.getByRole('dialog');
  await expect(dialog.getByLabel('Accessibility needs', {exact: true})).toBeVisible();
  await dialog.getByRole('button', {name: 'Get ticket', exact: true}).click();
  await expect(dialog.getByLabel('Full name', {exact: true})).toBeFocused();
  expect(await (await request.get(`/__fixtures/${id}`, {headers: fixtureHeaders})).json()).toMatchObject({registrations: 0});
  await page.evaluate(() => {
      const sizes = [...document.querySelectorAll('dialog h2,dialog label,dialog input,dialog button,dialog p')]
        .map((element) => [element, parseFloat(getComputedStyle(element).fontSize)]);
      for (const [element, size] of sizes) element.style.fontSize = `${size * 2}px`;
  });
  await dialog.getByLabel('Full name', {exact: true}).fill('Keyboard Guest');
  await page.keyboard.press('Tab');
  await expect(dialog.getByLabel('Email address', {exact: true})).toBeFocused();
  await page.keyboard.type(`${id}@example.test`);
  await page.keyboard.press('Tab');
  await expect(dialog.getByLabel('Accessibility needs', {exact: true})).toBeFocused();
  await page.keyboard.type('Step-free access');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBeTruthy();
  await dialog.getByRole('button', {name: 'Get ticket', exact: true}).scrollIntoViewIfNeeded();
  await page.screenshot({path: info.outputPath('registration-390px-200percent.png'), fullPage: true});
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  await expect(trigger).toBeFocused();
});

test('deep links survive real browser back-forward navigation and reload', async ({page, request}, info) => {
  const first = await fixture(request, 'history-first', info.project.name);
  const second = await fixture(request, 'history-second', info.project.name, {cancelled: true});
  await page.goto(`/event/${first}`);
  await expect(page.locator('[data-public-action]:visible').first()).toBeVisible();
  await page.goto(`/event/${second}`);
  await expect(page.locator('[data-public-action]')).toHaveCount(0);
  await page.goBack();
  await expect(page).toHaveURL(new RegExp(`/event/${first}$`));
  await expect(page.locator('[data-public-action]:visible').first()).toBeVisible();
  await page.goForward();
  await expect(page).toHaveURL(new RegExp(`/event/${second}$`));
  await page.reload();
  await expect(page.locator('[data-public-action]')).toHaveCount(0);
  await expect(page.getByRole('heading', {name: 'Browser fixture event'})).toBeVisible();
});
