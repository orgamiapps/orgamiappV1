"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const vm = require("node:vm");
const {validateContext, safariIdentity, targetUrl, createDriver, expectedCalendar, calendarProof, publicTitle, authIdentity, htmlResponsiveProbe} = require("../tools/web_release_producers/safari");
function fixture() {
  const candidate = {environment: "staging", projectId: "attendus-staging", sourceSha: "a".repeat(40), candidateRunId: "123"};
  const runId = "safari-qa-20261004", context = {...candidate, baseUrl: "https://attendus-staging.web.app", fixture: {
    runId, controlledRecipientDomain: "example.test", ownedFixtureIds: ["owner", "other", "event", "private", "second"],
    owner: {uid: "owner", email: `${runId}-owner@example.test`, password: "private-owner-password"},
    unauthorized: {uid: "other", email: `${runId}-other@example.test`, password: "private-other-password"},
    event: {id: "event", title: "Owned event", publicPath: "/event/event"}, privateEventId: "private", secondEventId: "second", firebase: {projectId: "attendus-staging", apiKey: "fixture-key"}}};
  return {candidate, context};
}
test("Safari requires frozen staging identities and retained owned actors/events", () => {
  const f = fixture(); assert.equal(validateContext(f.candidate, f.context).runId, f.context.fixture.runId);
  for (const mutate of [
    ({candidate}) => { candidate.environment = "production"; },
    ({context}) => { context.baseUrl = "https://attendus.app"; },
    ({context}) => { context.fixture.owner.email = "real@example.com"; },
    ({context}) => { context.fixture.privateEventId = "real-event"; },
    ({context}) => { context.requestedGates = ["observation"]; },
    ({context}) => { context.fixture.unauthorized.uid = "owner"; },
  ]) { const value = fixture(); mutate(value); assert.throws(() => validateContext(value.candidate, value.context)); }
});
test("reported WebKit or absent Safari/macOS capability evidence cannot pass", () => {
  const capabilities = {browserName: "safari", browserVersion: "26.6", platformName: "mac"};
  const system = {platform: "darwin", macosVersion: "15.7.9", macosBuild: "24G830", driverVersion: "Included with Safari 26.6", runnerImage: "macos15"};
  assert.equal(safariIdentity(capabilities, system).browserVersion, "26.6");
  for (const changed of [{browserName: "webkit"}, {browserName: "chrome"}, {browserVersion: ""}, {platformName: "linux"}]) assert.throws(() => safariIdentity({...capabilities, ...changed}, system));
  assert.throws(() => safariIdentity(capabilities, {...system, platform: "win32"}));
  assert.throws(() => safariIdentity(capabilities, {...system, driverVersion: "Playwright WebKit"}));
});
test("WebDriver targets remain loopback and Safari navigation cannot leave permitted staging routes", () => {
  assert.equal(targetUrl("/app/event/event"), "https://attendus-staging.web.app/app/event/event");
  for (const url of ["https://attendus.app/event/event", "//example.com/event/event", "/app/event/event?token=private", "/manage/secret", "/event/../profile", "/event/%2e%2e"]) assert.throws(() => targetUrl(url));
  assert.throws(() => createDriver({baseUrl: "https://remote-grid.example"}));
});
test("driver uses real Safari capability requests and never propagates credential echoes", async () => {
  const requests = [], secret = "private-owner-password";
  const driver = createDriver({fetchImpl: async (url, request) => {
    requests.push({url, ...request});
    if (url.endsWith("/session")) return {ok: true, json: async () => ({value: {sessionId: "session-1", capabilities: {browserName: "safari", browserVersion: "26.6", platformName: "mac"}}})};
    if (url.endsWith("/value")) return {ok: false, json: async () => ({value: {error: "invalid argument", message: `The password was ${secret}`, stacktrace: secret}})};
    return {ok: true, json: async () => ({value: null})};
  }});
  assert.equal((await driver.start()).browserName, "safari");
  await assert.rejects(() => driver.fill({"element-6066-11e4-a52e-4f735466cecf": "input"}, secret), (error) => !error.message.includes(secret) && error.code === "safari-webdriver-invalid-argument");
  assert.equal(JSON.parse(requests[0].body).capabilities.alwaysMatch.browserName, "safari");
  assert.equal(JSON.parse(requests[0].body).capabilities.alwaysMatch.acceptInsecureCerts, false);
  await driver.close(); assert.equal(requests.at(-1).method, "DELETE");
});
test("Safari auth observation reads only bound UID/anonymous state, never stored tokens", async () => {
  const user = {uid: "anonymous-fixture", isAnonymous: true, stsTokenManager: {accessToken: "secret-jwt", refreshToken: "secret-refresh"}};
  const driver = {executeAsync: async (script, args) => new Promise((resolve) => {
    const indexedDB = {open: () => {
      const open = {};
      queueMicrotask(() => {
        open.result = {close() {}, objectStoreNames: {contains: () => true}, transaction: () => ({objectStore: () => ({getAll: () => {
          const query = {}; queueMicrotask(() => {query.result = [{fbase_key: "firebase:authUser:fixture-key:[DEFAULT]", value: user}, {fbase_key: "firebase:authUser:other-key:[DEFAULT]", value: {uid: "unrelated"}}, {fbase_key: "firebase:authUser:fixture-key:attendus-public-web", value: {uid: "public-anonymous", isAnonymous: true}}]; query.onsuccess();}); return query;
        }})})}; open.onsuccess();
      }); return open;
    }};
    vm.runInNewContext(`(function(){${script}}).apply(null,args)`, {indexedDB, args: [...args, resolve]});
  })};
  const result = await authIdentity(driver, "fixture-key");
  assert.equal(JSON.stringify(result), JSON.stringify({uid: "anonymous-fixture", isAnonymous: true}));
  assert.equal(JSON.stringify(result).includes("secret"), false);
  assert.equal((await authIdentity(driver, "fixture-key", "attendus-public-web")).uid, "public-anonymous");
});
test("calendar proof binds real bytes to the live repeated-hour UTC schedule, revision and staging event URL", () => {
  const expected = expectedCalendar("event", {title: "Owned event", selectedDateTime: {toDate: () => new Date("2026-11-01T01:30:00-04:00")},
    eventDurationMinutes: 60, eventEnd: "2030-01-01T00:00:00Z", eventTimeZone: "America/New_York", eventRevision: 7});
  assert.equal(expected.startUtc, "20261101T053000Z"); assert.equal(expected.endUtc, "20261101T063000Z");
  const text = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:event@attendus.app\r\nDTSTART:20261101T053000Z\r\nDTEND:20261101T063000Z\r\nSUMMARY:Owned event\r\nSEQUENCE:7\r\nURL:https://attendus-staging.web.app/event/event\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
  const proof = calendarProof(Buffer.from(text), expected);
  assert.equal(proof.bytes, Buffer.byteLength(text)); assert.equal(proof.url, "https://attendus-staging.web.app/event/event");
  for (const incorrect of [
    text.replace("20261101T053000Z", "20000101T053000Z"), text.replace("20261101T063000Z", "20261101T073000Z"),
    text.replace("https://attendus-staging.web.app", "https://attendus.app"), text.replace("/event/event", "/event/unowned"),
    text.replace("UID:event@", "UID:other@"), text.replace("SEQUENCE:7", "SEQUENCE:6"),
    text.replace("DTEND:20261101T063000Z", "DTEND:20261101T063000Z\r\nDTEND:20000101T063000Z"),
    text.replace("DTSTART:", "DTSTART;TZID=America/New_York:"),
    text.replace("END:VEVENT", "END:VEVENT\r\nBEGIN:VEVENT\r\nUID:unrelated\r\nEND:VEVENT"),
    text.replace("SUMMARY:Owned event", "SUMMARY:Wrong event"),
  ]) assert.throws(() => calendarProof(Buffer.from(incorrect), expected), /safari-calendar/);
  assert.throws(() => calendarProof(Buffer.from("download requested"), expected));
  const folded = text.replace("URL:https://attendus-staging.web.app/event/event", "URL:https://attendus-staging.web.app/\r\n event/event");
  assert.equal(calendarProof(Buffer.from(folded), expected).url, expected.url);
  assert.throws(() => expectedCalendar("event", {title: "Incomplete", selectedDateTime: "2026-11-01T05:30:00Z"}), /schedule-incomplete/);
});
test("correct history URL cannot substitute for visible expected event content", async () => {
  let node = {textContent: "Second owned event", getBoundingClientRect: () => ({width: 200, height: 40})};
  let hidden = false; let reads = 0;
  const driver = {url: async () => "https://attendus-staging.web.app/event/second", execute: async (fn) => {
    reads++; return vm.runInNewContext(`(${fn.toString()})()`, {document: {querySelector: () => node}, getComputedStyle: () => ({display: hidden ? "none" : "block", visibility: "visible"})});
  }};
  assert.equal(await publicTitle(driver, "Second owned event"), "Second owned event");
  for (const change of [() => {hidden = true;}, () => {hidden = false; node.textContent = "Page unavailable";}, () => {node = null;}]) {
    change(); const before = reads;
    await assert.rejects(() => publicTitle(driver, "Second owned event", 100), /content-missing/);
    assert.ok(reads > before);
  }
});

test("200-percent probe scales inserted form from original computed baselines without 400-percent inheritance", () => {
  const nodes = []; let dialog = null;
  function node(tag, parent = null, base = null) {
    const properties = new Map();
    const result = {tagName: tag.toUpperCase(), parent, base, isConnected: true,
      box: {left: 12, right: 378, width: 366, height: 40}, clientWidth: 360, scrollWidth: 360,
      style: {getPropertyValue: (name) => properties.get(name)?.value || "", getPropertyPriority: (name) => properties.get(name)?.priority || "",
        setProperty: (name, value, priority = "") => properties.set(name, {value, priority}), removeProperty: (name) => properties.delete(name)},
      getBoundingClientRect() {return this.box;}};
    nodes.push(result); return result;
  }
  const body = node("body", null, 16);
  const heading = node("h1", body, 20); node("button", body, 16);
  const eyebrow = node("div", body, 13.12), footer = node("footer", body), footerText = node("span", footer);
  body.querySelectorAll = (selector) => {
    // A selector-aware mock must not silently return omitted div/span nodes.
    assert.equal(selector, "*"); return nodes.filter((value) => value !== body);
  };
  const computed = (value) => value.style.getPropertyValue("font-size") || `${value.base || (value.parent ? parseFloat(computed(value.parent)) : 16)}px`;
  const context = vm.createContext({document: {body, documentElement: {scrollWidth: 390}, querySelector: () => dialog}, innerWidth: 390,
    getComputedStyle: (value) => ({fontSize: computed(value), display: "block", visibility: "visible"})});
  const probe = () => vm.runInContext(`(${htmlResponsiveProbe.toString()})()`, context);
  assert.equal(probe().textIs200Percent, true); assert.equal(computed(heading), "40px");
  assert.equal(computed(eyebrow), "26.24px"); assert.equal(computed(footerText), "32px");
  dialog = node("dialog", null, 16);
  const label = node("label", dialog); const input = node("input", label); const textarea = node("textarea", dialog); const button = node("button", dialog);
  dialog.querySelectorAll = () => [input, textarea, button];
  for (let pass = 0; pass < 2; pass++) {
    const result = probe();
    assert.equal(result.textIs200Percent, true); assert.equal(result.controlsFit, true); assert.equal(result.dialogFits, true);
    assert.equal(result.controlCount, 3); assert.equal(computed(input), "32px"); assert.equal(computed(label), "32px");
    assert.equal(computed(heading), "40px");
    assert.equal(computed(eyebrow), "26.24px"); assert.equal(computed(footerText), "32px");
    assert.equal(result.samples.find((sample) => sample.tag === "input").before, 16);
  }
  // A fitting outer dialog/viewport cannot hide a clipped or oversized field.
  input.box = {...input.box, right: 600, width: 588};
  let result = probe(); assert.equal(result.pageFits, true); assert.equal(result.dialogFits, true); assert.equal(result.controlsFit, false);
  input.box = {...input.box, right: 378, width: 366}; button.scrollWidth = 700;
  result = probe(); assert.equal(result.dialogFits, true); assert.equal(result.controlsFit, false);
  button.scrollWidth = 360; dialog.scrollWidth = 700;
  assert.equal(probe().dialogFits, false);
});
