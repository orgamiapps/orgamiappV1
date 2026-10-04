'use strict';
const test = require('node:test'), assert = require('node:assert/strict'), vm = require('node:vm');
const {flutterSemanticsDom, ensureFlutterSemantics, activateFlutterSemanticsPage, activateFlutterSemanticsDriver} = require('../../tools/web_release_producers/flutter-semantics');

function dom({enabled = false, rectangle = {x: -1, y: -1, width: 1, height: 1}, count = 1, role = 'button', label = 'Enable accessibility'} = {}) {
  const state = {enabled, clicks: 0, count, queries: []};
  const element = {tagName: 'FLT-SEMANTICS-PLACEHOLDER', getAttribute: (name) => ({role, 'aria-label': label})[name],
    getBoundingClientRect: () => rectangle, click() {state.clicks++; state.enabled = true;}};
  const sandbox = {innerWidth: 1200, innerHeight: 900, getComputedStyle: () => ({display: 'block', visibility: 'visible'}),
    document: {querySelectorAll(selector) {state.queries.push(selector); if (selector === 'flt-semantics') return state.enabled ? [{}] : [];
      if (selector === 'flt-semantics-placeholder') return Array.from({length: state.count}, () => element); throw Error('Unapproved selector');}}};
  const execute = (fn, action) => vm.runInNewContext(`(${fn.toString()})(${JSON.stringify(action)})`, sandbox);
  return {state, element, execute};
}

test('serialized DOM function uses only exact engine selectors and activates offscreen AT control', () => {
  const f = dom(); assert.equal(f.execute(flutterSemanticsDom, 'inspect').kind, 'desktop-placeholder');
  assert.equal(f.execute(flutterSemanticsDom, 'activate-desktop').kind, 'desktop-activation-dispatched');
  assert.equal(f.state.clicks, 1); assert.equal(f.execute(flutterSemanticsDom, 'inspect').kind, 'enabled');
  assert.deepEqual([...new Set(f.state.queries)].sort(), ['flt-semantics', 'flt-semantics-placeholder']);
  assert.throws(() => f.execute(flutterSemanticsDom, '#arbitrary-button'), /invalid-action/);
});
test('ordinary button, duplicate node, wrong role/label and unrecognized geometry never activate', () => {
  for (const options of [{count: 2}, {role: 'link'}, {label: 'Delete account'}, {rectangle: {x: 10, y: 10, width: 30, height: 20}}]) {
    const f = dom(options); assert.throws(() => f.execute(flutterSemanticsDom, 'activate-desktop')); assert.equal(f.state.clicks, 0);
  }
  const f = dom({count: 0}); assert.equal(f.execute(flutterSemanticsDom, 'inspect').kind, 'waiting'); assert.equal(f.state.clicks, 0);
});
test('already-enabled tree requires no placeholder click', async () => {
  const f = dom({enabled: true});
  const result = await activateFlutterSemanticsDriver({execute: f.execute, click() {throw Error('No pointer click allowed');}});
  assert.equal(result.activation, 'already-enabled'); assert.equal(f.state.clicks, 0);
});
test('mobile full-view placeholder is returned for real pointer activation, never synthetic desktop click', async () => {
  const f = dom({rectangle: {x: 0, y: 0, width: 1200, height: 900}});
  assert.equal(f.execute(flutterSemanticsDom, 'inspect').kind, 'mobile-placeholder');
  assert.throws(() => f.execute(flutterSemanticsDom, 'activate-desktop'), /requires-offscreen/);
  let pointer = 0;
  const result = await activateFlutterSemanticsDriver({execute: f.execute, click: async (node) => {assert.equal(node, f.element); pointer++; f.state.enabled = true;}});
  assert.equal(result.activation, 'mobile-pointer-click'); assert.equal(pointer, 1); assert.equal(f.state.clicks, 0);
});
test('late placeholder is awaited, clicked once, and real semantics must appear afterward', async () => {
  let time = 0, inspected = 0, activated = 0;
  const result = await ensureFlutterSemantics({inspect: async () => {inspected++; return {kind: inspected < 3 ? 'waiting' : activated ? 'enabled' : 'desktop-placeholder'};},
    activateDesktop: async () => {activated++;}, activatePointer: async () => {throw Error('Wrong activation path');}},
  {timeoutMs: 100, pollMs: 10, now: () => time, sleep: async (ms) => {time += ms;}});
  assert.equal(result.activation, 'desktop-at-click'); assert.equal(activated, 1); assert.equal(inspected, 4);
});
test('missing tree or activation that never creates a tree fails at bounded deadline', async () => {
  for (const kind of ['waiting', 'desktop-placeholder']) {
    let time = 0, activated = 0;
    await assert.rejects(ensureFlutterSemantics({inspect: async () => ({kind}), activateDesktop: async () => {activated++;}, activatePointer: async () => {}},
      {timeoutMs: 30, pollMs: 10, now: () => time, sleep: async (ms) => {time += ms;}}), /startup-timeout/);
    assert.equal(activated, kind === 'waiting' ? 0 : 1);
  }
});
test('hung transport is bounded and does not dispatch a fallback action', async () => {
  let calls = 0;
  await assert.rejects(ensureFlutterSemantics({inspect: () => new Promise(() => {}), activateDesktop: () => {calls++;}, activatePointer: () => {calls++;}}, {timeoutMs: 15}), /startup-timeout/);
  assert.equal(calls, 0);
});
test('Playwright adapter dispatches through engine listener instead of impossible offscreen pointer click', async () => {
  const f = dom();
  const result = await activateFlutterSemanticsPage({evaluate: f.execute, locator() {throw Error('Desktop pointer must not be used');}});
  assert.equal(result.activation, 'desktop-at-click'); assert.equal(f.state.clicks, 1);
});
test('Safari adapter function remains serializable with no helper closure', async () => {
  const f = dom(); const driver = {execute: f.execute, click() {throw Error('No desktop WebDriver pointer');}};
  const result = await activateFlutterSemanticsDriver(driver);
  assert.equal(result.activation, 'desktop-at-click'); assert.equal(f.state.clicks, 1);
});

test('large-roster entry traverses management sheet Check-in control before waiting for roster', async () => {
  const {openCheckInConsole} = require('../../tools/web_release_producers/browser')._test;
  let state = 'event'; const steps = [];
  const visible = () => state === 'event' ? ['Manage event'] : state === 'management' ? ['Edit Event', 'Check-in'] : ['Check-in Console', 'Event roster'];
  const page = {getByText(text, options) {assert.equal(options.exact, true); const target = {
    last() {return target;}, async scrollIntoViewIfNeeded() {assert.ok(visible().includes(text), `${text} unavailable on ${state}`);},
    async click() {assert.ok(visible().includes(text), `${text} unavailable on ${state}`); steps.push(text); state = state === 'event' ? 'management' : 'console';},
    async waitFor() {assert.ok(visible().includes(text), `${text} unavailable on ${state}`); steps.push(`observed:${text}`);},
  }; return target;}};
  await openCheckInConsole(page);
  assert.equal(state, 'console'); assert.deepEqual(steps, ['Manage event', 'Check-in', 'observed:Check-in Console', 'observed:Event roster']);
});
