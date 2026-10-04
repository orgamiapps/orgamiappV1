"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const {test} = require("node:test");

function fixture(windows = [], configured = true) {
  const calls = {opened: [], focused: [], shown: [], order: [], firebase: []};
  const listeners = {};
  let background;
  const context = vm.createContext({
    URL,
    self: {
      location: {origin: "https://attendus-staging.web.app"},
      addEventListener: (name, handler) => {
        calls.order.push(name);
        listeners[name] = handler;
      },
      registration: {showNotification: (...args) => calls.shown.push(args)},
      clients: {
        matchAll: async () => windows,
        openWindow: async (url) => {
          calls.opened.push(url);
          return {focus: async () => calls.focused.push(url)};
        },
      },
    },
    importScripts: (url) => calls.order.push(url),
    firebase: {
      initializeApp: (config) => calls.firebase.push(config),
      messaging: () => ({onBackgroundMessage: (handler) => { background = handler; }}),
    },
  });
  let source = fs.readFileSync(path.join(__dirname, "../web/firebase-messaging-sw.js"), "utf8");
  if (configured) {
    for (const [key, value] of Object.entries({API_KEY: "demo-key", AUTH_DOMAIN: "demo.invalid", PROJECT_ID: "demo-attendus-admin", STORAGE_BUCKET: "demo-attendus-admin.appspot.com", MESSAGING_SENDER_ID: "123456789", APP_ID: "1:123456789:web:demo"})) {
      source = source.replaceAll(`__ATTENDUS_FIREBASE_${key}__`, value);
    }
  }
  vm.runInContext(source, context);
  async function click(data, action = "") {
    const waiting = [];
    let closed = false;
    let stopped = false;
    listeners.notificationclick({
      action,
      notification: {data, close: () => { closed = true; }},
      stopImmediatePropagation: () => { stopped = true; },
      waitUntil: (work) => waiting.push(work),
    });
    await Promise.all(waiting);
    assert.equal(closed, true);
    assert.equal(stopped, true);
  }
  return {calls, click, background: (payload) => background(payload)};
}

test("FCM event and community clicks use restored-auth app routes on the current origin", async () => {
  const f = fixture();
  assert.equal(f.calls.order[0], "notificationclick");
  for (const type of ["event_reminder", "event_changes", "geofence_checkin", "new_event", "ticket_update", "organizer_feedback", "event_feedback"]) {
    await f.click({FCM_MSG: {data: {type, eventId: "event_1", recipientUid: "account-a"}, fcmOptions: {link: "https://evil.invalid/"}}});
    assert.equal(f.calls.opened.at(-1), "https://attendus-staging.web.app/app/event/event_1");
  }
  await f.click({FCM_MSG: {data: {type: "org_update", organizationId: "group-2"}}});
  assert.equal(f.calls.opened.at(-1), "https://attendus-staging.web.app/app/community/group-2");
});

test("conversation clicks keep the app's existing auth continuation query", async () => {
  const f = fixture();
  for (const type of ["message", "new_message", "group_message", "message_mention"]) {
    await f.click({type, conversationId: "chat_3"});
    assert.equal(f.calls.opened.at(-1), "https://attendus-staging.web.app/?conversationId=chat_3");
  }
});

test("Discovery pushes preserve a single event or open the public app home for a batch", async () => {
  const f = fixture();
  await f.click({FCM_MSG: {data: {type: "discovery_new_events", eventId: "event-1"}}});
  assert.equal(f.calls.opened.at(-1), "https://attendus-staging.web.app/app/event/event-1");
  for (const eventId of ["", null]) {
    await f.click({FCM_MSG: {data: {type: "discovery_new_events", eventId}}});
    assert.equal(f.calls.opened.at(-1), "https://attendus-staging.web.app/app/discover");
  }
  const count = f.calls.opened.length;
  for (const eventId of [42, "../private", "https://evil.invalid"]) {
    await f.click({FCM_MSG: {data: {type: "discovery_new_events", eventId}}});
  }
  assert.equal(f.calls.opened.length, count);
});

test("unknown types, malformed IDs, arbitrary links, and notification actions cannot navigate", async () => {
  const f = fixture();
  for (const id of [null, undefined, 7, {}, [], "", "../private", "a/b", "https://evil.invalid", "a?next=x", "a#x", " a", "a\n", "a".repeat(301)]) {
    await f.click({FCM_MSG: {data: {type: "event_reminder", eventId: id}, fcmOptions: {link: "https://evil.invalid"}}});
  }
  for (const data of [null, [], {}, {type: "unknown", eventId: "valid", url: "https://evil.invalid"}]) {
    await f.click(data);
  }
  await f.click({type: "org_update", organizationId: "valid"}, "unknown-action");
  assert.deepEqual(f.calls.opened, []);
});

test("existing same-origin app window is navigated and focused; unrelated origins are untouched", async () => {
  const navigated = [];
  let focused = false;
  const f = fixture([
    {url: "https://other.invalid", navigate: () => assert.fail("cross-origin window")},
    {url: "https://attendus-staging.web.app/old", navigate: async (url) => {
      navigated.push(url);
      return {focus: async () => { focused = true; }};
    }},
  ]);
  await f.click({type: "event_changes", eventId: "new"});
  assert.deepEqual(navigated, ["https://attendus-staging.web.app/app/event/new"]);
  assert.equal(focused, true);
  assert.deepEqual(f.calls.opened, []);
});

test("a closing app window falls back to opening the same-origin destination", async () => {
  const f = fixture([{url: "https://attendus-staging.web.app/", navigate: async () => { throw Error("closed"); }}]);
  await f.click({type: "org_update", organizationId: "group"});
  assert.deepEqual(f.calls.opened, ["https://attendus-staging.web.app/app/community/group"]);
});

test("FCM display is not duplicated and data-only messages do not fabricate empty alerts", () => {
  const f = fixture();
  f.background({notification: {title: "Title", body: "Body"}, data: {type: "event_changes", eventId: "event"}});
  f.background({data: {type: "event_changes", eventId: "event"}});
  f.background({});
  assert.deepEqual(f.calls.shown, []);
});

test("unconfigured local worker never imports or initializes the external Firebase provider", () => {
  const f = fixture([], false);
  assert.deepEqual(f.calls.firebase, []);
  assert.deepEqual(f.calls.order.filter((entry) => entry.startsWith("https://")), []);
  assert.deepEqual(f.calls.shown, []);
});
