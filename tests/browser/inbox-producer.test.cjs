'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {createRequire} = require('node:module');
const path = require('node:path');
const {Timestamp} = createRequire(path.resolve(__dirname, '../../functions/package.json'))('firebase-admin/firestore');
const {runBrowserInbox, _test: {createInboxStore, fixtureCases, normalize}} = require('../../tools/web_release_producers/browser-inbox');
const {bindingId} = require('../../functions/communications/qualification-isolation');

function clone(value) {
  if (value instanceof Timestamp) return value;
  if (value instanceof Date) return new Date(value);
  if (Array.isArray(value)) return value.map(clone);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, clone(item)]));
  return value;
}

function setup() {
  const runId = 'webqa-20261004-0123456789', sourceSha = 'a'.repeat(40), candidateRunId = 'candidate-1';
  const fixture = {projectId: 'attendus-staging', runId, sourceSha, candidateRunId, controlledRecipientDomain: 'example.test',
    event: {id: `${runId}-event`, title: 'Owned event'}, eventClosesAt: new Date(Date.now() + 3600000).toISOString(), ownedFixtureIds: []};
  for (const role of ['owner', 'attendee', 'staff', 'unauthorized']) {
    fixture[role] = {uid: `${runId}-${role}`, email: `${runId}-${role}@example.test`}; fixture.ownedFixtureIds.push(fixture[role].uid);
  }
  fixture.ownedFixtureIds.push(fixture.event.id);
  const candidateIdentity = {projectId: fixture.projectId, sourceSha, candidateRunId, baseUrl: 'https://attendus-staging.web.app'};
  const docs = new Map(), writes = [], db = {projectId: fixture.projectId, docs, writes, failDelete: false, loseCreateAck: false};
  const snapshot = (ref) => ({exists: docs.has(ref.path), data: () => clone(docs.get(ref.path)), get: (key) => docs.get(ref.path)?.[key]});
  db.doc = (path) => ({path, get: async () => snapshot({path})});
  db.collection = (path) => ({doc: (id) => db.doc(`${path}/${id}`), count: () => ({get: async () => ({data: () => ({count: [...docs.keys()].filter((key) => key.startsWith(`${path}/`) && key.split('/').length === path.split('/').length + 1).length})})})});
  db.runTransaction = async (operation) => {
    const pending = [];
    const result = await operation({get: async (ref) => snapshot(ref),
      create: (ref, data) => pending.push({kind: 'create', ref, data}), delete: (ref) => pending.push({kind: 'delete', ref})});
    for (const item of pending) {
      if (item.kind === 'create' && docs.has(item.ref.path)) throw Object.assign(new Error('already exists'), {code: 6});
      if (item.kind === 'delete' && db.failDelete) throw Error('denied');
    }
    for (const item of pending) {
      writes.push({kind: item.kind, path: item.ref.path});
      if (item.kind === 'create') docs.set(item.ref.path, clone(item.data)); else docs.delete(item.ref.path);
    }
    if (pending.some((item) => item.kind === 'create') && db.loseCreateAck) throw Object.assign(Error('lost acknowledgement'), {code: 14});
    return result;
  };
  docs.set(`QualificationSetup/${runId}`, {...candidateIdentity, state: 'seeded', ownedFixtureIds: fixture.ownedFixtureIds});
  docs.set(`QualificationScopes/${runId}`, {schemaVersion: 1, projectId: fixture.projectId, status: 'active', mode: 'capture',
    createdAt: new Date(Date.now() - 1000), expiresAt: new Date(Date.now() + 3600000), actorUids: [fixture.owner.uid], recipientUids: [fixture.owner.uid],
    eventIds: [fixture.event.id], organizationIds: [], conversationIds: [], recipientEmailHashes: []});
  for (const [kind, id] of [['account', fixture.owner.uid], ['event', fixture.event.id]]) docs.set(`QualificationBindings/${bindingId(kind, id)}`,
    {schemaVersion: 1, projectId: fixture.projectId, runId, state: 'bound'});
  docs.set(`users/${fixture.owner.uid}`, {uid: fixture.owner.uid});
  docs.set(`Events/${fixture.event.id}`, {customerUid: fixture.owner.uid});
  const args = {fixture, candidateIdentity, db, attemptId: 'b'.repeat(24)};
  return {...args, store: () => createInboxStore(args)};
}

function browser(value, {failTap = false} = {}) {
  let view = 'discovery';
  const path = (title) => [...value.db.docs.keys()].find((key) => key.startsWith(`users/${value.fixture.owner.uid}/notifications/`) && value.db.docs.get(key).title === title);
  const visible = (name) => name === 'Discover' ? view === 'discovery' : name === 'Notifications' ? view === 'discovery' :
    name === 'Manage event' || name === value.fixture.event.title ? view === 'event' : view === 'inbox' && !!path(name);
  const locator = (name) => ({first() {return this;}, async click() {
    if (!visible(name)) throw Error('Control not visible');
    if (name === 'Notifications') {view = 'inbox'; return;}
    if (failTap) throw Error('https://provider.invalid/secret?token=sensitive');
    const doc = value.db.docs.get(path(name)); doc.isRead = true;
    view = doc.type === 'discovery_new_events' && !doc.eventId ? 'discovery' : 'event';
  }, async waitFor() {assert.equal(visible(name), true, name);}, async count() {return Number(visible(name));}, async innerText() {assert.equal(visible(name), true); return name;}});
  return {page: {getByRole: (_, options) => locator(options.name), getByText: (name) => locator(name), url: () => `${value.candidateIdentity.baseUrl}/app/discover`},
    openApp: async () => {view = 'discovery';}, currentUid: async () => value.fixture.owner.uid};
}

test('synthetic inbox rejects production, unowned actors and real recipients before writes', () => {
  for (const mutate of [v => v.db.projectId = 'orgami-66nxok', v => v.fixture.owner.email = 'real@example.com',
    v => v.fixture.ownedFixtureIds = [], v => v.candidateIdentity.baseUrl = 'https://attendus.app']) {
    const value = setup(); mutate(value); assert.throws(value.store); assert.deepEqual(value.db.writes, []);
  }
});

test('live stale scope, foreign binding and candidate drift prevent creates', async () => {
  for (const mutate of [v => v.db.docs.get(`QualificationScopes/${v.fixture.runId}`).expiresAt = new Date(0),
    v => v.db.docs.get(`QualificationScopes/${v.fixture.runId}`).recipientUids = [],
    v => v.db.docs.get(`QualificationBindings/${bindingId('account', v.fixture.owner.uid)}`).runId = 'foreign',
    v => v.db.docs.get(`QualificationSetup/${v.fixture.runId}`).sourceSha = 'c'.repeat(40)]) {
    const value = setup(); mutate(value); await assert.rejects(value.store().create(fixtureCases(value.fixture)[0])); assert.deepEqual(value.db.writes, []);
  }
});

test('fixture shapes cannot write another event or add arbitrary notification fields', async () => {
  const value = setup(), store = value.store();
  await assert.rejects(store.create({...fixtureCases(value.fixture)[0], eventId: 'foreign'}));
  await assert.rejects(store.create({...fixtureCases(value.fixture)[0], fcmToken: 'forbidden'}));
  assert.deepEqual(value.db.writes, []);
});

test('browser orchestration exercises eight synthetic routes/read states and cleanup with injected UI boundaries', async () => {
  const value = setup(), report = await runBrowserInbox({...value, ...browser(value)});
  assert.equal(report.evidenceKind, 'synthetic-owned-inbox-ui'); assert.equal(report.entries.length, 8);
  assert.ok(report.assertions.every((item) => JSON.stringify(item.expected) === JSON.stringify(item.actual)));
  assert.equal(report.cleanup.deletedIds.length, 8); assert.equal(report.cleanup.afterCount, 0);
  assert.equal(value.db.writes.filter((item) => item.kind === 'create').length, 8);
  assert.ok(value.db.writes.every((item) => item.path.startsWith(`users/${value.fixture.owner.uid}/notifications/${value.fixture.runId}-inbox-`)));
});

test('a UI failure is sanitized and still deletes only its exact synthetic record', async () => {
  const value = setup();
  await assert.rejects(runBrowserInbox({...value, ...browser(value, {failTap: true})}), (error) => {
    assert.equal(error.message, 'inbox-ui-execution-failed'); assert.equal(error.inboxReport.cleanup.afterCount, 0);
    assert.equal(error.inboxReport.cleanup.deletedIds.length, 1); return true;
  });
});

test('a definite create collision is never overwritten or eligible for cleanup', async () => {
  const value = setup(), store = value.store(), item = fixtureCases(value.fixture)[0];
  const id = `${value.fixture.runId}-inbox-${value.attemptId}-${item.id}`, path = `users/${value.fixture.owner.uid}/notifications/${id}`;
  value.db.docs.set(path, {title: 'Existing record'});
  await assert.rejects(store.create(item)); const cleanup = await store.cleanup();
  assert.deepEqual(value.db.docs.get(path), {title: 'Existing record'}); assert.deepEqual(value.db.writes, []); assert.equal(cleanup.afterCount, 1);
});

test('an unknown create acknowledgement is reconciled by exact provenance without a new mutation key', async () => {
  const value = setup(), store = value.store(); value.db.loseCreateAck = true;
  await assert.rejects(store.create(fixtureCases(value.fixture)[0]));
  const cleanup = await store.cleanup(); assert.equal(cleanup.afterCount, 0); assert.equal(cleanup.deletedIds.length, 1);
  assert.equal(value.db.writes.filter((item) => item.kind === 'create').length, 1);
});

test('changed content or provenance is retained and cleanup fails closed', async () => {
  for (const mutate of [doc => doc.body = 'Changed content', doc => doc.qualificationFixture.runId = 'foreign']) {
    const value = setup(), store = value.store(), entry = await store.create(fixtureCases(value.fixture)[0]);
    const path = `users/${value.fixture.owner.uid}/notifications/${entry.id}`; mutate(value.db.docs.get(path));
    const cleanup = await store.cleanup(); assert.deepEqual(cleanup.failures, [entry.id]); assert.equal(cleanup.afterCount, 1);
    assert.equal(value.db.writes.filter((item) => item.kind === 'delete').length, 0);
  }
});

test('nanosecond timestamp changes refuse cleanup with actual Firestore Timestamp instances', async () => {
  const value = setup(), store = value.store(), entry = await store.create(fixtureCases(value.fixture)[0]);
  const target = `users/${value.fixture.owner.uid}/notifications/${entry.id}`;
  const original = Timestamp.fromDate(value.db.docs.get(target).createdAt);
  value.db.docs.get(target).createdAt = new Timestamp(original.seconds, original.nanoseconds + 1);
  const cleanup = await store.cleanup();
  assert.deepEqual(cleanup.failures, [entry.id]); assert.equal(cleanup.afterCount, 1);
  assert.equal(value.db.writes.filter((item) => item.kind === 'delete').length, 0);
});

test('timestamp canonicalization preserves precision and cannot be forged by stored strings/maps/arrays', async () => {
  const date = new Date('2026-10-04T10:20:30.123Z'), timestamp = Timestamp.fromDate(date);
  assert.deepEqual(normalize(date), normalize(timestamp));
  assert.notDeepEqual(normalize(timestamp), normalize(new Timestamp(timestamp.seconds, timestamp.nanoseconds + 1)));
  for (const replacement of [date.toISOString(), ['timestamp', timestamp.seconds, timestamp.nanoseconds],
    {seconds: timestamp.seconds, nanoseconds: timestamp.nanoseconds}]) {
    assert.notDeepEqual(normalize(timestamp), normalize(replacement));
  }
  const value = setup(), store = value.store(), entry = await store.create(fixtureCases(value.fixture)[0]);
  const target = `users/${value.fixture.owner.uid}/notifications/${entry.id}`;
  value.db.docs.get(target).createdAt = value.db.docs.get(target).createdAt.toISOString();
  const cleanup = await store.cleanup(); assert.deepEqual(cleanup.failures, [entry.id]); assert.equal(cleanup.afterCount, 1);
});

test('cleanup permission failure blocks the evidence and preserves remaining records', async () => {
  const value = setup(); value.db.failDelete = true;
  await assert.rejects(runBrowserInbox({...value, ...browser(value)}), (error) => {
    assert.equal(error.message, 'inbox-cleanup-incomplete'); assert.equal(error.inboxReport.cleanup.afterCount, 8);
    assert.equal(error.inboxReport.cleanup.failures.length, 8); return true;
  });
});

test('another actor or pre-existing inbox fails before fixture creation', async () => {
  const value = setup();
  await assert.rejects(runBrowserInbox({...value, ...browser(value), currentUid: async () => value.fixture.attendee.uid}));
  assert.deepEqual(value.db.writes, []);
  value.db.docs.set(`users/${value.fixture.owner.uid}/notifications/pre-existing`, {title: 'Preserve'});
  await assert.rejects(runBrowserInbox({...value, ...browser(value)}));
  assert.deepEqual(value.db.writes, []); assert.ok(value.db.docs.has(`users/${value.fixture.owner.uid}/notifications/pre-existing`));
});
