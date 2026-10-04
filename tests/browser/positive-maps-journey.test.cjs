'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {bindingId} = require('../../functions/communications/qualification-isolation');
const {readOwnedMapEvents, openOwnedMapMarker} = require('../../tools/web_release_producers/browser')._test;

const NOW = Date.parse('2026-10-04T12:00:00Z');
function fixtureDb() {
  const runId = 'qa-maps-20261004', sourceSha = 'a'.repeat(40), candidateRunId = '12345678';
  const fixture = {runId, sourceSha, candidateRunId, controlledRecipientDomain: 'example.test',
    runStartsAt: new Date(NOW).toISOString(), eventClosesAt: new Date(NOW + 105 * 60000).toISOString(),
    ownedFixtureIds: ['owner', 'attendee', 'unauthorized', 'pilot', 'private', 'history', 'analytics'],
    event: {id: 'pilot', title: 'Controlled pilot', publicPath: '/event/pilot'}, privateEventId: 'private',
    secondEventId: 'history', canaryEventId: 'analytics',
    firebase: {projectId: 'attendus-staging', apiKey: 'controlled-key', storageBucket: 'attendus-staging.appspot.com'}};
  for (const role of ['owner', 'attendee', 'unauthorized']) fixture[role] = {uid: role, email: `${runId}-${role}@example.test`, password: 'controlled-password'};
  const context = {projectId: 'attendus-staging', baseUrl: 'https://attendus-staging.web.app', sourceSha, candidateRunId, fixture};
  const rows = new Map([
    [`QualificationScopes/${runId}`, {schemaVersion: 1, projectId: context.projectId, status: 'active', mode: 'capture',
      createdAt: new Date(NOW - 60000), expiresAt: new Date(NOW + 3600000), actorUids: ['owner'], recipientUids: ['attendee'],
      eventIds: ['pilot', 'private', 'history', 'analytics'], organizationIds: [], conversationIds: [], recipientEmailHashes: []}],
    [`QualificationSetup/${runId}`, {state: 'seeded', projectId: context.projectId, sourceSha, candidateRunId}],
  ]);
  const bound = {schemaVersion: 1, state: 'bound', projectId: context.projectId, runId};
  rows.set(`QualificationBindings/${bindingId('account', 'owner')}`, {...bound});
  for (const [index, id] of ['history', 'analytics'].entries()) {
    const [latitude, longitude] = index ? [40.7851, -73.9683] : [40.7829, -73.9654];
    rows.set(`QualificationBindings/${bindingId('event', id)}`, {...bound});
    rows.set(`Events/${id}`, {title: `Controlled ${id} event`, customerUid: 'owner', private: false, status: 'active',
      locationType: 'in_person', latitude, longitude, locationName: `Synthetic qualification venue ${index ? 'B' : 'A'}`,
      location: 'Central Park — synthetic test location, not a real event venue',
      selectedDateTime: {toMillis: () => NOW - 15 * 60000}, eventDurationMinutes: 120});
  }
  const reads = [], db = {projectId: 'attendus-staging', doc: path => ({path}),
    runTransaction: async (fn, options) => {
      assert.deepEqual(options, {readOnly: true});
      return fn({get: async ref => {reads.push(ref.path); const data = rows.get(ref.path);
        return {id: ref.path.split('/').at(-1), exists: data !== undefined, get: key => data?.[key], data: () => data};}});
    }};
  return {context, db, rows, reads};
}

test('Maps metadata comes from the two owned synthetic events in one read-only scope transaction', async () => {
  const value = fixtureDb(), result = await readOwnedMapEvents(value.context, value.db, NOW);
  assert.deepEqual(result.events.map(e => [e.id, e.latitude, e.longitude, e.locationName]), [
    ['history', 40.7829, -73.9654, 'Synthetic qualification venue A'],
    ['analytics', 40.7851, -73.9683, 'Synthetic qualification venue B'],
  ]);
  assert.equal(result.sourceSha, value.context.sourceSha); assert.equal(result.candidateRunId, value.context.candidateRunId);
  assert.equal(result.checkedAt, new Date(NOW).toISOString());
  assert.equal(value.reads.length, 8);
  assert.equal(value.reads.some(path => path === 'Events/pilot' || path === 'Events/private'), false);
});

test('Maps guard rejects foreign project, candidate, duplicate/missing IDs before any read', async () => {
  for (const mutate of [v => {v.db.projectId = 'orgami-66nxok';}, v => {v.context.fixture.sourceSha = 'b'.repeat(40);},
    v => {v.context.fixture.candidateRunId = 'other';}, v => {v.context.fixture.canaryEventId = 'history';},
    v => {delete v.context.fixture.canaryEventId;}, v => {v.context.fixture.ownedFixtureIds = v.context.fixture.ownedFixtureIds.filter(id => id !== 'analytics');}]) {
    const value = fixtureDb(); mutate(value); await assert.rejects(readOwnedMapEvents(value.context, value.db, NOW));
    assert.equal(value.reads.length, 0);
  }
});

test('Maps guard rejects scope, setup, event/account binding, and deletion changes', async () => {
  const mutations = [
    v => {v.rows.get(`QualificationScopes/${v.context.fixture.runId}`).mode = 'normal';},
    v => {v.rows.get(`QualificationScopes/${v.context.fixture.runId}`).eventIds = ['history'];},
    v => {v.rows.get(`QualificationScopes/${v.context.fixture.runId}`).actorUids = [];},
    v => {v.rows.get(`QualificationScopes/${v.context.fixture.runId}`).expiresAt = new Date(NOW);},
    v => {v.rows.get(`QualificationSetup/${v.context.fixture.runId}`).sourceSha = 'b'.repeat(40);},
    v => {v.rows.get(`QualificationSetup/${v.context.fixture.runId}`).state = 'retired';},
    v => {v.rows.get(`QualificationBindings/${bindingId('event', 'analytics')}`).runId = 'other-run';},
    v => {v.rows.delete(`QualificationBindings/${bindingId('account', 'owner')}`);},
    v => {v.rows.set('account_deletion_jobs/owner', {state: 'pending'});},
  ];
  for (const mutate of mutations) {const value = fixtureDb(); mutate(value); await assert.rejects(readOwnedMapEvents(value.context, value.db, NOW));}
});

test('Maps guard rejects old coordinate-free fixtures and ineligible, renamed or non-owned events', async () => {
  for (const patch of [{latitude: 0, longitude: 0}, {latitude: 90.1}, {latitude: 40.7829}, {locationName: 'Real venue'},
    {location: 'Another address'}, {customerUid: 'foreign'}, {private: true}, {deleted: true}, {isHidden: true},
    {status: 'pending_approval'}, {locationType: 'online'}, {title: ''}, {title: 'Controlled history event'},
    {selectedDateTime: {toMillis: () => NOW - 240 * 60000}}, {eventDurationMinutes: 0}]) {
    const value = fixtureDb(); Object.assign(value.rows.get('Events/analytics'), patch);
    await assert.rejects(readOwnedMapEvents(value.context, value.db, NOW));
  }
  const missing = fixtureDb(); missing.rows.delete('Events/analytics');
  await assert.rejects(readOwnedMapEvents(missing.context, missing.db, NOW));
});

// This is an injected Playwright transport, not a fake provider or staged UI
// acceptance. It models separate map/sheet/details states so a URL shortcut,
// search substitution, wrong event or missing control cannot satisfy the test.
function pageTransport(events, fault) {
  let state = 'discover'; const actions = [], selected = events[0];
  const visible = key => {
    if (key === 'entry') return state === 'discover';
    if (key === 'map') return state === 'map';
    if (key === 'error') return state === 'map' && fault === 'unavailable';
    if (key.startsWith('marker:')) return state === 'map' && key !== `marker:${fault === 'missing-marker' ? events[1].title : ''}`;
    if (key === 'details-button') return state === 'sheet';
    if (key === `text:${selected.title}`) return ['sheet', 'details'].includes(state) && !(state === 'details' && fault === 'wrong-details');
    if (key === `text:${selected.locationName}\n${selected.location}`) return state === 'sheet' && fault !== 'wrong-sheet';
    if (key === 'text:Manage event') return state === 'details' && fault !== 'no-management';
    return false;
  };
  const locator = key => ({
    first() {return this;}, last() {return this;},
    getByRole(role, options) {
      assert.equal(key, 'map'); assert.equal(role, 'button'); assert.equal(options.exact, true);
      assert.ok(events.some(e => e.title === options.name)); return locator(`marker:${options.name}`);
    },
    count: async () => visible(key) ? 1 : 0,
    waitFor: async options => {
      const expected = options?.state !== 'hidden';
      assert.equal(visible(key), expected, `Expected ${key} ${expected ? 'visible' : 'hidden'} while ${state}`);
      actions.push(['wait', key, expected]);
    },
    click: async options => {
      assert.equal(options, undefined, 'No forced/scripted marker click'); assert.equal(visible(key), true);
      actions.push(['click', key]);
      if (key === 'entry') state = 'map';
      else if (key === `marker:${selected.title}`) state = fault === 'no-sheet' ? 'map' : 'sheet';
      else if (key === 'details-button') state = fault === 'stuck-sheet' ? 'sheet' : 'details';
      else throw Error('Unexpected UI mutation');
    },
  });
  return {actions, page: {
    locator: selector => {assert.equal(selector, '.gm-style'); return locator('map');},
    getByRole: (role, options) => {assert.equal(role, 'button'); assert.equal(options.exact, true);
      assert.ok(['View events map', 'View event details'].includes(options.name)); return locator(options.name === 'View events map' ? 'entry' : 'details-button');},
    getByText: (text, options) => {assert.equal(options.exact, true); return locator(text === 'Map unavailable' ? 'error' : `text:${text}`);},
    // No evaluate(), goto(), provider callback or query search entrypoint.
  }};
}

test('positive journey waits for both real marker controls, clicks one, verifies its venue and navigates via details CTA', async () => {
  const value = fixtureDb(), {events} = await readOwnedMapEvents(value.context, value.db, NOW);
  const ui = pageTransport(events), screenshots = [];
  const result = await openOwnedMapMarker(ui.page, events, {screenshot: async name => screenshots.push(name)});
  assert.deepEqual(ui.actions.filter(row => row[0] === 'click'), [
    ['click', 'entry'], ['click', `marker:${events[0].title}`], ['click', 'details-button'],
  ]);
  const secondMarkerWait = ui.actions.findIndex(row => row[1] === `marker:${events[1].title}`);
  assert.ok(secondMarkerWait < ui.actions.findIndex(row => row[0] === 'click' && row[1].startsWith('marker:')));
  assert.deepEqual(result.markerEventIds, ['history', 'analytics']); assert.equal(result.selectedEventId, 'history');
  assert.equal(result.detailsTitle, events[0].title); assert.equal(result.detailsManagementVisible, true);
  assert.deepEqual(screenshots, ['discover-maps-markers.png', 'discover-maps-selected-event.png', 'discover-maps-event-details.png']);
});

for (const fault of ['missing-marker', 'unavailable', 'no-sheet', 'wrong-sheet', 'stuck-sheet', 'wrong-details', 'no-management']) {
  test(`positive Maps journey fails and retains screenshot when ${fault}`, async () => {
    const value = fixtureDb(), {events} = await readOwnedMapEvents(value.context, value.db, NOW);
    const ui = pageTransport(events, fault), screenshots = [];
    await assert.rejects(openOwnedMapMarker(ui.page, events, {screenshot: async name => screenshots.push(name)}));
    assert.equal(screenshots.at(-1), 'discover-maps-failure.png');
    if (fault === 'missing-marker' || fault === 'unavailable') assert.deepEqual(ui.actions.filter(row => row[0] === 'click'), [['click', 'entry']]);
  });
}

test('missing/ambiguous landmark manifests fail before any UI action', async () => {
  const value = fixtureDb(), {events} = await readOwnedMapEvents(value.context, value.db, NOW);
  for (const invalid of [[], [events[0]], [events[0], events[0]], [events[0], {...events[1], title: events[0].title}],
    [events[0], {...events[1], locationName: ''}]]) await assert.rejects(openOwnedMapMarker({}, invalid));
});
