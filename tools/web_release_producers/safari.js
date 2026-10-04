"use strict";

// Branded Safari only. This producer uses Apple's W3C driver, not Playwright's
// patched WebKit. Passwords stay in WebDriver requests and never enter reports.
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const {spawn, execFileSync} = require("node:child_process");
const {createRequire} = require("node:module");
const dependencies = createRequire(path.resolve(__dirname, "../../functions/package.json"));
const {sha256, digest} = require("../web_release_contract");
const {validScope, bindingId} = require("../../functions/communications/qualification-isolation");
const {schedule, calendarDate, calendarText} = require("../../functions/events/schedule");
const GATE = "safari-web-acceptance";
const ORIGIN = "https://attendus-staging.web.app";
const ELEMENT = "element-6066-11e4-a52e-4f735466cecf";
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const fail = (code) => { throw Object.assign(new Error(code), {code}); };

function validateContext(candidate, context) {
  const fixture = context.fixture;
  if (candidate.environment !== "staging" || candidate.projectId !== "attendus-staging" || context.projectId !== candidate.projectId || context.baseUrl !== ORIGIN || context.sourceSha !== candidate.sourceSha || context.candidateRunId !== candidate.candidateRunId || process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) fail("safari-requires-frozen-staging");
  if (context.requestedGates && !context.requestedGates.includes(GATE)) fail("safari-does-not-produce-observations");
  if (!fixture || !/^[a-z0-9-]{8,80}$/.test(fixture.runId || "") || fixture.controlledRecipientDomain !== "example.test" || !Array.isArray(fixture.ownedFixtureIds) || fixture.firebase?.projectId !== candidate.projectId || !fixture.firebase.apiKey || !fixture.event?.title) fail("safari-fixture-invalid");
  for (const role of ["owner", "unauthorized"]) {
    const actor = fixture[role];
    if (!actor || !fixture.ownedFixtureIds.includes(actor.uid) || !actor.email?.startsWith(`${fixture.runId}-`) || !actor.email.endsWith("@example.test") || typeof actor.password !== "string" || actor.password.length < 10) fail("safari-actor-not-owned");
  }
  if (fixture.owner.uid === fixture.unauthorized.uid) fail("safari-distinct-actors-required");
  for (const id of [fixture.event.id, fixture.privateEventId, fixture.secondEventId]) if (typeof id !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(id) || !fixture.ownedFixtureIds.includes(id)) fail("safari-event-not-owned");
  if (fixture.event.publicPath !== `/event/${encodeURIComponent(fixture.event.id)}`) fail("safari-public-path-invalid");
  return fixture;
}
function safariIdentity(capabilities, system) {
  if (capabilities?.browserName?.toLowerCase() !== "safari" || typeof capabilities.browserVersion !== "string" || !/^[0-9][0-9A-Za-z. ()_-]{0,100}$/.test(capabilities.browserVersion) || !/^(mac|macos|mac os x)$/i.test(capabilities.platformName || "")) fail("actual-safari-capability-required");
  if (system?.platform !== "darwin" || !/^\d+\.\d+(?:\.\d+)?$/.test(system.macosVersion || "") || !/^Included with Safari|^SafariDriver|^safaridriver/i.test(system.driverVersion || "")) fail("actual-macos-driver-required");
  return {browserName: capabilities.browserName, browserVersion: capabilities.browserVersion, platformName: capabilities.platformName,
    macosVersion: system.macosVersion, macosBuild: system.macosBuild, driverVersion: system.driverVersion,
    runnerImage: system.runnerImage, runnerImageVersion: system.runnerImageVersion};
}
function targetUrl(pathname) {
  const url = new URL(pathname, ORIGIN);
  if (url.origin !== ORIGIN || url.username || url.password || url.search || url.hash || !/^\/(?:app\/discover|(?:app\/)?event\/[A-Za-z0-9_-]+)$/.test(url.pathname)) fail("safari-navigation-outside-owned-staging");
  return url.href;
}
function createDriver({baseUrl = "http://127.0.0.1:4446", fetchImpl = fetch, deadline = Date.now() + 20 * 60000} = {}) {
  if (!/^http:\/\/127\.0\.0\.1:[0-9]{4,5}$/.test(baseUrl)) fail("webdriver-must-be-loopback");
  let session;
  async function request(route, method = "GET", data, cleanup = false) {
    if (!route.startsWith("/") || route.includes("..")) fail("invalid-webdriver-route");
    const remaining = cleanup ? 10000 : Math.min(95000, deadline - Date.now());
    if (remaining <= 0) fail("safari-session-deadline");
    let response, body;
    try {
      response = await fetchImpl(`${baseUrl}${route}`, {method, headers: {"content-type": "application/json"}, ...(data === undefined ? {} : {body: JSON.stringify(data)}), signal: AbortSignal.timeout(remaining)});
      body = await response.json();
    } catch (_) { fail("safari-driver-transport-failed"); }
    if (!response.ok || body.value?.error) {
      const code = typeof body.value?.error === "string" && /^[a-z -]{1,80}$/.test(body.value.error) ? body.value.error.replaceAll(" ", "-") : "failed";
      fail(`safari-webdriver-${code}`); // Never include a server echo of input text.
    }
    return body.value;
  }
  const command = (route, method = "GET", data) => request(`/session/${session}${route}`, method, data);
  return {
    request,
    async start() {
      const result = await request("/session", "POST", {capabilities: {alwaysMatch: {browserName: "safari", acceptInsecureCerts: false, pageLoadStrategy: "normal"}}});
      if (!/^[A-Za-z0-9-]{1,128}$/.test(result?.sessionId || "")) fail("invalid-safari-session");
      session = result.sessionId;
      await command("/timeouts", "POST", {implicit: 0, pageLoad: 90000, script: 15000});
      return result.capabilities;
    },
    execute(fn, ...args) { return command("/execute/sync", "POST", {script: `return (${fn.toString()})(...arguments);`, args}); },
    executeAsync(script, args = []) { return command("/execute/async", "POST", {script, args}); },
    navigate(value) { return command("/url", "POST", {url: targetUrl(value)}); },
    url() { return command("/url"); },
    history(direction) { if (!["back", "forward", "refresh"].includes(direction)) fail("invalid-history-operation"); return command(`/${direction}`, "POST", {}); },
    resize(width, height) { return command("/window/rect", "POST", {width, height}); },
    click(element) { if (!element?.[ELEMENT]) fail("safari-element-missing"); return command(`/element/${encodeURIComponent(element[ELEMENT])}/click`, "POST", {}); },
    async fill(element, text) {
      if (!element?.[ELEMENT]) fail("safari-element-missing");
      const route = `/element/${encodeURIComponent(element[ELEMENT])}`;
      await command(`${route}/clear`, "POST", {}); await command(`${route}/value`, "POST", {text, value: [...text]});
    },
    key(value) { return command("/actions", "POST", {actions: [{type: "key", id: "keyboard", actions: [{type: "keyDown", value}, {type: "keyUp", value}]}]}); },
    screenshot() { return command("/screenshot"); },
    async close() { if (session) { try { await request(`/session/${session}`, "DELETE", undefined, true); } finally { session = null; } } },
  };
}
async function until(check, code, timeout = 60000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { const value = await check(); if (value) return value; await delay(350); }
  fail(code);
}
function visibleElement({css, text, input}) {
  const visible = (node) => { const rect = node.getBoundingClientRect(), style = getComputedStyle(node); return rect.width > 0 && rect.height > 0 && style.visibility !== "hidden" && style.display !== "none"; };
  if (css) return [...document.querySelectorAll(css)].find(visible) || null;
  if (input) return [...document.querySelectorAll("input,textarea")].find((node) => visible(node) && [node.getAttribute("aria-label"), node.placeholder, ...[...(node.labels || [])].map((label) => label.textContent.trim())].includes(input)) || null;
  const nodes = [...document.querySelectorAll("flt-semantics,[role=button],button,a,span,h1,h2,p")].filter((node) => visible(node) && (node.getAttribute("aria-label") === text || node.textContent.trim() === text));
  return nodes.filter((node) => !nodes.some((other) => other !== node && node.contains(other))).at(-1) || null;
}
async function find(driver, selector, timeout = 60000) { return until(() => driver.execute(visibleElement, selector), "safari-visible-control-not-found", timeout); }
async function publicTitle(driver, expected, timeout = 60000) {
  return until(async () => {
    const actual = await driver.execute(() => {
      const node = document.querySelector("h1"); if (!node) return null;
      const rect = node.getBoundingClientRect(), style = getComputedStyle(node);
      return rect.width > 0 && rect.height > 0 && style.visibility !== "hidden" && style.display !== "none" ? node.textContent : null;
    });
    return actual === expected ? actual : false;
  }, "safari-public-event-content-missing", timeout);
}
async function click(driver, selector) {
  const element = await find(driver, selector);
  await driver.execute((node) => node.scrollIntoView({block: "center"}), element); await driver.click(element);
}
async function semantics(driver) {
  const placeholder = await until(async () => await driver.execute(visibleElement, {css: "flt-semantics-placeholder"}) || await driver.execute(visibleElement, {css: "flt-semantics"}), "safari-flutter-first-frame-missing", 90000);
  if (await driver.execute((node) => node.tagName.toLowerCase() === "flt-semantics-placeholder", placeholder)) await driver.click(placeholder);
  await find(driver, {css: "flt-semantics"}, 90000);
}
async function authIdentity(driver, apiKey, appName = "[DEFAULT]") {
  if (!["[DEFAULT]", "attendus-public-web"].includes(appName)) fail("safari-auth-app-invalid");
  return driver.executeAsync(`
    const key=arguments[0], appName=arguments[1], done=arguments[arguments.length-1];
    const opening=indexedDB.open('firebaseLocalStorageDb');
    opening.onerror=()=>done({error:'auth-storage-unavailable'});
    opening.onsuccess=()=>{ const db=opening.result;
      if(!db.objectStoreNames.contains('firebaseLocalStorage')){db.close();done(null);return;}
      const query=db.transaction('firebaseLocalStorage').objectStore('firebaseLocalStorage').getAll();
      query.onerror=()=>{db.close();done({error:'auth-storage-unavailable'});};
      query.onsuccess=()=>{const rows=query.result.filter(row=>row.fbase_key==='firebase:authUser:'+key+':'+appName); db.close();
        if(rows.length>1){done({error:'ambiguous-auth-identity'});return;}
        const user=rows[0]?.value; done(user?{uid:user.uid,isAnonymous:user.isAnonymous===true}:null);};
    };`, [apiKey, appName]);
}
async function verifyOwnedFixture(context) {
  const {initializeApp, applicationDefault, deleteApp} = dependencies("firebase-admin/app");
  const {getFirestore} = dependencies("firebase-admin/firestore");
  const app = initializeApp({projectId: "attendus-staging", credential: applicationDefault()}, `safari-${Date.now()}`);
  const db = getFirestore(app), f = context.fixture;
  try {
    const scope = (await db.doc(`QualificationScopes/${f.runId}`).get()).data();
    if (!validScope(scope, f.runId, context.projectId, Date.now())) fail("safari-live-scope-invalid");
    const setup = await db.doc(`QualificationSetup/${f.runId}`).get();
    if (setup.get("sourceSha") !== context.sourceSha || setup.get("candidateRunId") !== context.candidateRunId || setup.get("state") !== "seeded") fail("safari-live-fixture-candidate-mismatch");
    for (const uid of [f.owner.uid, f.unauthorized.uid]) {
      const binding = await db.doc(`QualificationBindings/${bindingId("account", uid)}`).get();
      if (!scope.actorUids.includes(uid) || binding.get("runId") !== f.runId || binding.get("projectId") !== context.projectId || binding.get("state") !== "bound") fail("safari-live-actor-not-owned");
    }
    const eventTitles = {}; let calendar;
    for (const id of [f.event.id, f.privateEventId, f.secondEventId]) {
      const [event, binding] = await Promise.all([db.doc(`Events/${id}`).get(), db.doc(`QualificationBindings/${bindingId("event", id)}`).get()]);
      if (!scope.eventIds.includes(id) || !event.exists || event.get("customerUid") !== f.owner.uid || binding.get("runId") !== f.runId || binding.get("projectId") !== context.projectId || binding.get("state") !== "bound") fail("safari-live-event-not-owned");
      const title = event.get("title");
      if (typeof title !== "string" || !title.trim() || title.length > 500) fail("safari-live-event-title-invalid");
      eventTitles[id] = title;
      if (id === f.event.id) calendar = expectedCalendar(id, event.data());
    }
    if (eventTitles[f.event.id] !== f.event.title) fail("safari-fixture-title-differs-from-live-event");
    return {projectId: context.projectId, runId: f.runId, eventIds: [f.event.id, f.privateEventId, f.secondEventId], eventTitles, calendar, checkedAt: new Date().toISOString()};
  } finally { await db.terminate(); await deleteApp(app); }
}
function expectedCalendar(eventId, event) {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(eventId || "")) fail("safari-calendar-event-invalid");
  const dates = schedule(event);
  if (!dates.start || !dates.end || dates.end <= dates.start || typeof event.title !== "string" || !event.title.trim()) fail("safari-calendar-live-schedule-incomplete");
  return {eventId, uid: `${eventId}@attendus.app`, title: event.title, revision: Math.max(0, Number(event.eventRevision) || 0),
    startUtc: calendarDate(dates.start), endUtc: calendarDate(dates.end), url: targetUrl(`/event/${eventId}`)};
}
function calendarProof(bytes, expected) {
  if (!Buffer.isBuffer(bytes) || bytes.length > 1024 * 1024 || !expected || !/^[A-Za-z0-9_-]{1,128}$/.test(expected.eventId || "") ||
      expected.uid !== `${expected.eventId}@attendus.app` || !/^\d{8}T\d{6}Z$/.test(expected.startUtc || "") || !/^\d{8}T\d{6}Z$/.test(expected.endUtc || "") ||
      !Number.isSafeInteger(expected.revision) || expected.revision < 0 || expected.url !== targetUrl(`/event/${expected.eventId}`)) fail("safari-calendar-download-invalid");
  const lines = bytes.toString("utf8").replace(/\r?\n[ \t]/g, "").split(/\r?\n/).filter(Boolean);
  if (lines[0] !== "BEGIN:VCALENDAR" || lines.at(-1) !== "END:VCALENDAR" ||
      ["BEGIN:VCALENDAR", "END:VCALENDAR", "BEGIN:VEVENT", "END:VEVENT"].some((value) => lines.filter((line) => line === value).length !== 1)) fail("safari-calendar-download-invalid");
  const start = lines.indexOf("BEGIN:VEVENT"), end = lines.indexOf("END:VEVENT");
  if (start >= end) fail("safari-calendar-download-invalid");
  const properties = lines.slice(start + 1, end), wanted = {UID: expected.uid, DTSTART: expected.startUtc, DTEND: expected.endUtc,
    URL: calendarText(expected.url), SUMMARY: calendarText(expected.title), SEQUENCE: String(expected.revision)};
  if (properties.some((line) => /^(BEGIN|END):/.test(line))) fail("safari-calendar-download-invalid");
  const values = {};
  for (const [key, value] of Object.entries(wanted)) {
    const matches = properties.filter((line) => line.startsWith(`${key}:`) || line.startsWith(`${key};`));
    if (matches.length !== 1 || matches[0] !== `${key}:${value}`) fail("safari-calendar-differs-from-live-event");
    values[key] = matches[0].slice(key.length + 1);
  }
  return {sha256: sha256(bytes), bytes: bytes.length, eventId: expected.eventId, contentType: "text/calendar",
    startUtc: values.DTSTART, endUtc: values.DTEND, url: values.URL, revision: Number(values.SEQUENCE), liveExpectationSha256: digest(expected)};
}
async function produce({candidate, context, outputDir}) {
  const fixture = validateContext(candidate, context);
  const evidence = {assertions: [], blockers: [], rawPaths: []}; const anonymous = new Set(); let child, driver; let sessionReady = false; let stage = "preflight";
  const record = (id, expected, actual) => evidence.assertions.push({id, expected, actual});
  const write = (name, value) => { const target = path.join(outputDir, "safari", name); fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, Buffer.isBuffer(value) ? value : JSON.stringify(value, null, 2) + "\n"); evidence.rawPaths.push(`safari/${name}`); };
  const identity = {projectId: candidate.projectId, sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId, runId: fixture.runId, releaseId: candidate.releaseId};
  async function observeAuth() {
    const current = new URL(await driver.url());
    if (current.origin !== ORIGIN) fail("safari-auth-origin-changed");
    const user = await authIdentity(driver, fixture.firebase.apiKey, current.pathname.startsWith("/app/") ? "[DEFAULT]" : "attendus-public-web");
    if (user?.error) fail(user.error);
    if (user?.isAnonymous && typeof user.uid === "string" && user.uid.length <= 128 && !/[\/\x00-\x1f]/.test(user.uid)) anonymous.add(user.uid);
    return user;
  }
  async function app(route = "/app/discover") { await driver.navigate(route); await semantics(driver); await observeAuth(); }
  async function login(account) {
    await app(); await click(driver, {text: "Log in"});
    try { await find(driver, {text: "Welcome back"}, 3000); }
    catch (error) { if (error.code !== "safari-visible-control-not-found") throw error; await click(driver, {text: "Log in"}); }
    await observeAuth(); // Capture the guest UID before full-account login replaces it.
    await driver.fill(await find(driver, {input: "Email address"}), account.email);
    await driver.fill(await find(driver, {input: "Password"}), account.password); await driver.key("\uE007");
    await until(async () => (await observeAuth())?.uid === account.uid, "safari-ui-login-identity-mismatch", 90000);
    await find(driver, {text: "Discover"}); record(`ui-login-${account.uid}`, account.uid, (await observeAuth()).uid);
  }
  async function shot(name) {
    if (await driver.execute(() => [...document.querySelectorAll('input[type="password"]')].some((node) => node.value))) fail("safari-screenshot-secret-input-present");
    const png = Buffer.from(await driver.screenshot(), "base64");
    if (png.length > 10 * 1024 * 1024 || png.subarray(0, 8).toString("hex") !== "89504e470d0a1a0a") fail("safari-screenshot-invalid");
    write(name, png);
  }
  try {
    if (process.platform !== "darwin" || process.env.RUNNER_OS !== "macOS" || process.env.GITHUB_ACTIONS !== "true") fail("safari-requires-hosted-macos-runner");
    const owned = await verifyOwnedFixture(context);
    write("fixture-ownership.json", {...identity, ...owned});
    const response = await fetch(`${ORIGIN}/release-manifest.json`, {redirect: "error", signal: AbortSignal.timeout(30000)});
    const hash = sha256(Buffer.from(await response.arrayBuffer()));
    if (!response.ok || hash !== candidate.webFiles["release-manifest.json"]) fail("safari-live-artifact-mismatch");
    execFileSync("sudo", ["-n", "/usr/bin/safaridriver", "--enable"], {timeout: 60000, stdio: "pipe"});
    const system = {platform: process.platform, macosVersion: execFileSync("sw_vers", ["-productVersion"], {encoding: "utf8", timeout: 10000}).trim(),
      macosBuild: execFileSync("sw_vers", ["-buildVersion"], {encoding: "utf8", timeout: 10000}).trim(),
      driverVersion: execFileSync("/usr/bin/safaridriver", ["--version"], {encoding: "utf8", timeout: 10000}).trim(), runnerImage: process.env.ImageOS || null, runnerImageVersion: process.env.ImageVersion || null};
    child = spawn("/usr/bin/safaridriver", ["--port", "4446"], {stdio: "ignore"}); child.on("error", () => {});
    driver = createDriver();
    await until(async () => { try { return (await driver.request("/status"))?.ready === true; } catch (_) { if (child.exitCode !== null) fail("safari-driver-exited"); return false; } }, "safari-driver-not-ready", 30000);
    const browser = safariIdentity(await driver.start(), system); sessionReady = true; write("browser.json", {...identity, ...browser, manifestSha256: hash}); record("actual-branded-safari", "safari", browser.browserName.toLowerCase());
    await driver.resize(1280, 1000);
    stage = "guest-form"; await driver.navigate(fixture.event.publicPath);
    const publicIdentity = await driver.execute(() => { const node = document.getElementById("attendus-public-config"); const data = node ? JSON.parse(node.textContent) : null; return {title: document.querySelector("h1")?.textContent, projectId: data?.firebase?.projectId}; });
    if (publicIdentity.projectId !== candidate.projectId) fail("safari-public-page-project-mismatch");
    record("public-event-title", fixture.event.title, publicIdentity.title); await click(driver, {css: "[data-public-action]"});
    await driver.fill(await find(driver, {css: "dialog input[name=fullName]"}), "Controlled Safari Guest");
    await driver.fill(await find(driver, {css: "dialog input[name=email]"}), "invalid-address");
    record("guest-invalid-email-is-blocked", false, await driver.execute(() => document.querySelector("dialog form").checkValidity()));
    await click(driver, {css: "dialog button[type=submit]"});
    record("invalid-guest-form-remains-open", true, await driver.execute(() => document.querySelector("dialog")?.open === true));
    await observeAuth(); await driver.key("\uE00C");
    await until(() => driver.execute(() => !document.querySelector("dialog")), "safari-dialog-did-not-close");
    record("dialog-restores-trigger-focus", true, await driver.execute(() => document.activeElement?.hasAttribute("data-public-action") === true));
    await shot("guest-form.png");
    stage = "responsive"; await driver.resize(500, 900);
    const responsive = await driver.execute(() => { const nodes = [...document.querySelectorAll("h1,h2,p,a,dt,dd,button,label,input")], sizes = nodes.map((node) => parseFloat(getComputedStyle(node).fontSize)); nodes.forEach((node, i) => { node.style.fontSize = `${sizes[i] * 2}px`; }); return {width: innerWidth, scrollWidth: document.documentElement.scrollWidth, titleSize: parseFloat(getComputedStyle(document.querySelector("h1")).fontSize)}; });
    record("narrow-safari-viewport", true, responsive.width >= 280 && responsive.width <= 600);
    record("200-percent-text-no-horizontal-overflow", true, responsive.scrollWidth <= responsive.width);
    await click(driver, {css: "[data-public-action]"}); await find(driver, {css: "dialog input[name=fullName]"});
    const formFits = await driver.execute(() => { const dialog = document.querySelector("dialog"), nodes = [...dialog.querySelectorAll("h2,p,a,button,label,input")], sizes = nodes.map((node) => parseFloat(getComputedStyle(node).fontSize)); nodes.forEach((node, i) => { node.style.fontSize = `${sizes[i] * 2}px`; }); return dialog.getBoundingClientRect().width <= innerWidth && document.documentElement.scrollWidth <= innerWidth; });
    record("200-percent-guest-dialog-fits", true, formFits);
    write("responsive.json", {...identity, requestedWindowWidth: 500, textScale: 2, ...responsive}); await shot("narrow-200-percent.png"); await driver.key("\uE00C");
    await driver.resize(1280, 1000);
    stage = "public-history"; await driver.navigate(fixture.event.publicPath); await driver.navigate(`/event/${fixture.secondEventId}`);
    await driver.history("back"); record("public-back-content", owned.eventTitles[fixture.event.id], await publicTitle(driver, owned.eventTitles[fixture.event.id]));
    record("public-back-route", targetUrl(fixture.event.publicPath), await driver.url());
    await driver.history("forward"); await driver.history("refresh"); record("public-forward-reload-content", owned.eventTitles[fixture.secondEventId], await publicTitle(driver, owned.eventTitles[fixture.secondEventId]));
    record("public-forward-reload-route", targetUrl(`/event/${fixture.secondEventId}`), await driver.url());
    stage = "owner-management"; await login(fixture.owner); await app(`/app/event/${fixture.event.id}`);
    await click(driver, {text: "Manage event"}); await find(driver, {text: "Edit Event"}); record("owner-management-ui-opened", true, !!await driver.execute(visibleElement, {text: "Edit Event"})); await shot("owner-management.png");
    stage = "calendar-download"; await app(`/app/event/${fixture.event.id}`);
    const downloads = path.join(os.homedir(), "Downloads"), existing = new Set(fs.existsSync(downloads) ? fs.readdirSync(downloads) : []);
    await click(driver, {text: "Add to calendar"}); await click(driver, {text: "Apple Calendar"});
    const downloaded = await until(async () => {
      const files = fs.existsSync(downloads) ? fs.readdirSync(downloads).filter((name) => !existing.has(name) && /^attendus-event(?:[- ]?\(?\d+\)?)?\.ics$/.test(name)) : [];
      if (files.length > 1) fail("safari-download-ambiguous"); if (!files.length) return null;
      const target = path.join(downloads, files[0]); const stat = fs.lstatSync(target);
      if (stat.isSymbolicLink() || !stat.isFile() || stat.size > 1024 * 1024) fail("safari-download-invalid-file");
      const bytes = fs.readFileSync(target); return bytes.length ? bytes : null;
    }, "safari-calendar-download-not-observed", 60000);
    write("calendar-download.txt", downloaded); write("calendar-expected.json", {...identity, ...owned.calendar});
    const calendar = calendarProof(downloaded, owned.calendar); write("calendar.json", {...identity, ...calendar});
    record("downloaded-calendar-matches-event", fixture.event.id, calendar.eventId);
    record("calendar-start-matches-live-event", owned.calendar.startUtc, calendar.startUtc); record("calendar-end-matches-live-event", owned.calendar.endUtc, calendar.endUtc);
    record("calendar-link-stays-in-staging", owned.calendar.url, calendar.url);
    stage = "account-switch"; await app(); await click(driver, {text: "Profile"}); await click(driver, {text: "Settings"}); await click(driver, {text: "Sign out"});
    await until(async () => (await observeAuth())?.uid !== fixture.owner.uid, "safari-signout-kept-former-account");
    await login(fixture.unauthorized); await app(`/app/event/${fixture.privateEventId}`);
    await find(driver, {text: "This event requires access"});
    record("former-owner-management-not-visible", false, !!await driver.execute(visibleElement, {text: "Manage event"})); await shot("switched-private-route.png");
    stage = "flutter-history"; await app(`/app/event/${fixture.event.id}`); await find(driver, {text: owned.eventTitles[fixture.event.id]}); await app(`/app/event/${fixture.secondEventId}`);
    await find(driver, {text: owned.eventTitles[fixture.secondEventId]});
    await driver.history("back"); await semantics(driver); await find(driver, {text: owned.eventTitles[fixture.event.id]}); record("flutter-back-route", targetUrl(`/app/event/${fixture.event.id}`), await driver.url());
    record("flutter-back-content", true, !!await driver.execute(visibleElement, {text: owned.eventTitles[fixture.event.id]}));
    await driver.history("forward"); await driver.history("refresh"); await semantics(driver);
    await find(driver, {text: owned.eventTitles[fixture.secondEventId]});
    record("flutter-forward-reload-route", targetUrl(`/app/event/${fixture.secondEventId}`), await driver.url());
    record("flutter-forward-reload-content", true, !!await driver.execute(visibleElement, {text: owned.eventTitles[fixture.secondEventId]}));
    record("history-retains-switched-identity", fixture.unauthorized.uid, (await observeAuth())?.uid || null);
    await app(`/app/event/${fixture.privateEventId}`); await driver.history("refresh"); await semantics(driver); await find(driver, {text: "This event requires access"});
    record("private-route-remains-denied-after-reload", false, !!await driver.execute(visibleElement, {text: "Manage event"}));
  } catch (error) {
    const code = typeof error.code === "string" && /^[a-z0-9-]{1,100}$/.test(error.code) ? error.code : "safari-execution-failed";
    evidence.blockers.push(`${stage}:${code}`); record(`${stage}-completed`, true, false);
    write("failure.json", {...identity, stage, code, observedAt: new Date().toISOString()});
  } finally {
    // Failed App Check or form rendering may happen after Firebase already
    // created an anonymous identity. Reconcile both app storage namespaces.
    if (sessionReady) try {
      if (new URL(await driver.url()).origin === ORIGIN) for (const appName of ["[DEFAULT]", "attendus-public-web"]) {
        const user = await authIdentity(driver, fixture.firebase.apiKey, appName);
        if (user?.error) fail(user.error);
        if (user?.isAnonymous && typeof user.uid === "string" && user.uid.length <= 128 && !/[\/\x00-\x1f]/.test(user.uid)) anonymous.add(user.uid);
      }
    } catch (_) { evidence.blockers.push("safari-final-auth-observation-failed"); }
    write("anonymous-identities.json", {...identity, observedAt: new Date().toISOString(), anonymousUids: [...anonymous].sort(), disposition: "Retained for exact scoped reconciliation; no deletion performed"});
    if (driver) try { await driver.close(); } catch (_) { evidence.blockers.push("safari-session-cleanup-failed"); }
    if (child && child.exitCode === null) child.kill("SIGTERM");
    write("journey.json", {...identity, assertions: evidence.assertions, blockers: evidence.blockers, observedAt: new Date().toISOString()});
  }
  return {gates: {[GATE]: evidence}};
}
module.exports = {produce, validateContext, safariIdentity, targetUrl, createDriver, expectedCalendar, calendarProof, publicTitle, authIdentity, GATE};
