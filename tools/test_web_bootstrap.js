"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const {test} = require("node:test");

const read = (name) => fs.readFileSync(path.join(__dirname, "../web", name), "utf8");
const tick = () => new Promise((resolve) => setImmediate(resolve));

async function entryFixture({url = "http://localhost:8080/app/discover", production = false, controlled = false, unavailableStorage = false} = {}) {
  const scripts = [];
  const redirects = [];
  const deletedCaches = [];
  const errors = [];
  const registeredWorkers = [];
  const listeners = {};
  const values = new Map([["firebase-auth-user", "preserve-account-session"]]);
  const storage = {
    getItem: (key) => {
      if (unavailableStorage) throw Error("private storage unavailable");
      return values.get(key) ?? null;
    },
    setItem: (key, value) => {
      if (unavailableStorage) throw Error("private storage unavailable");
      values.set(key, value);
    },
    clear: () => assert.fail("bootstrap must not clear authentication storage"),
    removeItem: () => assert.fail("bootstrap must not remove authentication state"),
  };
  const caches = {keys: async () => ["flutter-app-cache", "firebase-auth-cache"], delete: async (name) => deletedCaches.push(name)};
  const parsed = new URL(url);
  const window = {
    location: {href: url, origin: parsed.origin, hostname: parsed.hostname, port: parsed.port,
      replace: (next) => redirects.push(next)},
    history: {replaceState: () => {}},
    localStorage: storage,
    sessionStorage: storage,
    caches,
    addEventListener: (name, callback) => { listeners[name] = callback; },
  };
  let unregistered = 0;
  const worker = {scriptURL: `${parsed.origin}/flutter_service_worker.js`};
  const navigator = {serviceWorker: {
    controller: controlled ? worker : null,
    getRegistrations: async () => controlled ? [{active: worker, unregister: async () => { unregistered++; }}] : [],
    register: async (workerUrl) => registeredWorkers.push(workerUrl),
  }};
  let source = [...read("index.html").matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].map((match) => match[1]).find((code) => code.includes("bootstrapAttendus"));
  assert.ok(source, "the actual startup entry script is present");
  if (production) {
    for (const [key, value] of Object.entries({
      PRIMARY_ORIGIN: "https://attendus.app", SECONDARY_ORIGIN: "https://www.attendus.app",
      FIREBASE_HOSTING_ORIGIN: "https://orgami-66nxok.web.app", FIREBASE_APP_ORIGIN: "https://orgami-66nxok.firebaseapp.com",
      WORKER_BRIDGE_ENABLED: "true",
    })) source = source.replaceAll(`__ATTENDUS_${key}__`, value);
  }
  vm.runInNewContext(source, {
    window, navigator, URL,
    performance: {now: () => 1},
    console: {warn: () => {}, error: (...args) => errors.push(args)},
    caches,
    document: {
      getElementById: () => ({classList: {add: () => {}}, textContent: ""}),
      createElement: () => ({}), body: {appendChild: (script) => scripts.push(script)},
    },
  });
  await tick();
  await listeners.load?.();
  await tick();
  return {scripts, redirects, deletedCaches, errors, registeredWorkers, values, unregistered};
}

test("unconfigured local Flutter run starts despite unresolved release-origin placeholders", async () => {
  const f = await entryFixture();
  assert.equal(f.scripts.length, 1);
  assert.equal(f.scripts[0].src, "flutter_bootstrap.js");
  assert.deepEqual(f.errors, []);
  assert.deepEqual(f.redirects, []);
  assert.deepEqual(f.deletedCaches, ["flutter-app-cache"]);
  assert.equal(f.values.get("firebase-auth-user"), "preserve-account-session");
});

test("private browsing storage failure cannot prevent local bootstrap", async () => {
  const f = await entryFixture({unavailableStorage: true});
  assert.equal(f.scripts.length, 1);
  assert.deepEqual(f.errors, []);
  assert.deepEqual(f.redirects, []);
});

test("packaged origin configuration preserves the legacy-worker migration boundary", async () => {
  const f = await entryFixture({url: "https://attendus.app/app/discover?q=music", production: true, controlled: true});
  assert.equal(f.unregistered, 1);
  assert.equal(f.scripts.length, 0, "controlled page must finish migration before loading release code");
  assert.equal(f.redirects.length, 1);
  const bridge = new URL(f.redirects[0]);
  assert.equal(bridge.origin, "https://orgami-66nxok.web.app");
  const returned = new URL(bridge.searchParams.get("attendus_worker_return"));
  assert.equal(returned.origin, "https://attendus.app");
  assert.equal(returned.searchParams.get("q"), "music");
  assert.equal(returned.searchParams.get("attendus_worker_migrated"), "1");
  assert.deepEqual(f.deletedCaches, ["flutter-app-cache"]);
  assert.equal(f.values.get("firebase-auth-user"), "preserve-account-session");
});

async function runtimeFixture(releaseBase) {
  let config;
  let engine;
  let ran = false;
  const errors = [];
  let source = read("flutter_bootstrap.js").replace("{{flutter_js}}", "").replace("{{flutter_build_config}}", "");
  if (releaseBase) source = source.replaceAll("__ATTENDUS_RELEASE_BASE__", releaseBase);
  vm.runInNewContext(source, {
    _flutter: {loader: {load: async (options) => {
      config = options.config;
      await options.onEntrypointLoaded({initializeEngine: async (value) => {
        engine = value;
        return {runApp: async () => { ran = true; }};
      }});
    }}},
    document: {getElementById: () => null},
    performance: {mark: () => {}},
    window: {requestAnimationFrame: (callback) => callback(), attendusShowStartupError: (error) => errors.push(error)},
  });
  await tick();
  return {config, engine, ran, errors};
}

test("unpackaged Flutter bootstrap leaves default local asset resolution intact", async () => {
  const f = await runtimeFixture();
  assert.equal(f.ran, true);
  assert.deepEqual(f.errors, []);
  assert.deepEqual(Object.keys(f.config), []);
  assert.deepEqual(Object.keys(f.engine), []);
});

test("packaged Flutter bootstrap retains the immutable release asset namespace", async () => {
  const f = await runtimeFixture("/releases/release-fixture/");
  assert.equal(f.ran, true);
  assert.deepEqual(f.errors, []);
  assert.equal(f.config.entrypointBaseUrl, "/releases/release-fixture/");
  assert.equal(f.config.canvasKitBaseUrl, "/releases/release-fixture/canvaskit/");
  assert.equal(f.engine.assetBase, "/releases/release-fixture/");
});
