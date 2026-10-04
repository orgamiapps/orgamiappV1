'use strict';

// These are temporary UI fixtures, not provider deliveries or captured messages.
// No callable, outbound queue, or provider API is invoked by this module.
const crypto = require('node:crypto');
const {isDeepStrictEqual} = require('node:util');
const {validatePilot} = require('./browser-pilot');
const {bindingId, validScope} = require('../../functions/communications/qualification-isolation');
const PROJECT = 'attendus-staging';
const KIND = 'synthetic-owned-inbox-ui';

function normalize(value) {
  if (value instanceof Date) {
    const millis = value.getTime(), seconds = Math.floor(millis / 1000);
    if (!Number.isFinite(millis)) throw Error('inbox-invalid-timestamp');
    return ['timestamp', seconds, (millis - seconds * 1000) * 1000000];
  }
  if (typeof value?.toDate === 'function' && Number.isInteger(value.seconds) && Number.isInteger(value.nanoseconds)) {
    return ['timestamp', value.seconds, value.nanoseconds];
  }
  // Containers have distinct tags: a stored map/array/string cannot impersonate
  // a Firestore Timestamp, and cleanup preserves sub-millisecond precision.
  if (Array.isArray(value)) return ['array', value.map(normalize)];
  if (value && typeof value === 'object') return ['object', Object.keys(value).sort().map((key) => [key, normalize(value[key])])];
  return value;
}
const digest = (value) => crypto.createHash('sha256').update(JSON.stringify(normalize(value))).digest('hex');
const reject = (code) => { const error = new Error(code); error.code = code; throw error; };

function fixtureCases(fixture) {
  return [
    {id: 'discovery-single', type: 'discovery_new_events', eventId: fixture.event.id},
    {id: 'group-event', type: 'group_event', eventId: fixture.event.id},
    {id: 'event-update', type: 'event_update', eventId: fixture.event.id},
    {id: 'event-feedback', type: 'event_feedback', eventId: fixture.event.id,
      data: {action: 'open_feedback', eventId: fixture.event.id}},
    {id: 'admin-nested', type: 'event_reminder', data: {eventId: fixture.event.id}},
    {id: 'discovery-missing', type: 'discovery_new_events', batch: true},
    {id: 'discovery-null', type: 'discovery_new_events', eventId: null, batch: true},
    {id: 'discovery-empty', type: 'discovery_new_events', eventId: '', batch: true},
  ];
}

function createInboxStore({fixture, candidateIdentity, db, attemptId, now = () => Date.now()}) {
  const identity = {...validatePilot(fixture, candidateIdentity), ownerUid: fixture.owner.uid, evidenceKind: KIND, attemptId};
  if (db.projectId !== PROJECT || process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST ||
      !/^[a-f0-9]{24}$/.test(attemptId || '') || !fixture.event.title ||
      candidateIdentity.baseUrl !== 'https://attendus-staging.web.app') reject('inbox-invalid-environment');
  const collection = db.collection(`users/${identity.ownerUid}/notifications`);
  const planned = new Map();

  async function guard(tx, active = true) {
    const refs = [db.doc(`QualificationScopes/${identity.runId}`), db.doc(`QualificationSetup/${identity.runId}`),
      db.doc(`QualificationBindings/${bindingId('account', identity.ownerUid)}`),
      db.doc(`QualificationBindings/${bindingId('event', identity.eventId)}`),
      db.doc(`users/${identity.ownerUid}`), db.doc(`Events/${identity.eventId}`), db.doc(`account_deletion_jobs/${identity.ownerUid}`)];
    const [scope, setup, ownerBinding, eventBinding, user, event, deleting] = await Promise.all(refs.map((ref) => tx.get(ref)));
    if (setup.get('state') !== 'seeded' || setup.get('projectId') !== PROJECT || setup.get('sourceSha') !== identity.sourceSha ||
        setup.get('candidateRunId') !== identity.candidateRunId || !setup.get('ownedFixtureIds')?.includes(identity.ownerUid) ||
        !setup.get('ownedFixtureIds')?.includes(identity.eventId) ||
        [ownerBinding, eventBinding].some((row) => row.get('schemaVersion') !== 1 || row.get('projectId') !== PROJECT ||
          row.get('runId') !== identity.runId || row.get('state') !== 'bound') ||
        !user.exists || event.get('customerUid') !== identity.ownerUid || deleting.exists ||
        (active && (!validScope(scope.data(), identity.runId, PROJECT, now()) ||
          !scope.get('actorUids').includes(identity.ownerUid) || !scope.get('recipientUids').includes(identity.ownerUid) ||
          !scope.get('eventIds').includes(identity.eventId)))) reject('inbox-live-ownership-changed');
  }

  function matches(snapshot, expected) {
    if (!snapshot.exists) return false;
    const data = snapshot.data();
    if (typeof data.isRead !== 'boolean') return false;
    return isDeepStrictEqual(normalize({...data, isRead: false}), normalize(expected));
  }
  const count = async () => (await collection.count().get()).data().count;
  return {
    identity,
    async preflight() {
      await db.runTransaction((tx) => guard(tx), {readOnly: true});
      const result = await count();
      if (result !== 0) reject('inbox-not-empty-before-fixtures');
      return result;
    },
    async create(item) {
      const allowed = fixtureCases(fixture).find((entry) => entry.id === item.id);
      if (!allowed || !isDeepStrictEqual(allowed, item)) reject('inbox-unapproved-fixture-shape');
      const id = `${identity.runId}-inbox-${attemptId}-${item.id}`;
      if (planned.has(id)) reject('inbox-create-repeated');
      const {id: caseId, batch, ...fields} = item;
      const payload = {title: `Synthetic inbox ${caseId}`, body: 'Controlled UI routing fixture; not a delivered notification.',
        ...fields, createdAt: new Date(now()), isRead: false};
      const data = {...payload, qualificationFixture: {...identity, caseId, payloadSha256: digest(payload)}};
      const ref = collection.doc(id);
      // Track the exact intended write before commit so a lost acknowledgement
      // can be reconciled without retrying create or touching another document.
      planned.set(id, {ref, data});
      try {
        await db.runTransaction(async (tx) => { await guard(tx); tx.create(ref, data); });
      } catch (error) {
        // A definite collision belongs to a previous writer. Even identical
        // content must never make it eligible for this invocation's cleanup.
        if (error.code === 6 || error.code === 'already-exists') planned.delete(id);
        throw error;
      }
      return {id, caseId, title: payload.title, target: batch ? 'discovery' : identity.eventId};
    },
    async read(id) {
      const entry = planned.get(id);
      if (!entry) reject('inbox-read-not-owned');
      const snapshot = await entry.ref.get();
      if (!matches(snapshot, entry.data)) reject('inbox-fixture-content-changed');
      return {id, isRead: snapshot.get('isRead'), payloadSha256: entry.data.qualificationFixture.payloadSha256};
    },
    async cleanup() {
      const deletedIds = [], remainingIds = [], failures = [];
      for (const [id, entry] of planned) {
        try {
          await db.runTransaction(async (tx) => {
            await guard(tx, false);
            const snapshot = await tx.get(entry.ref);
            if (!snapshot.exists) return;
            if (!matches(snapshot, entry.data)) reject('inbox-cleanup-content-changed');
            tx.delete(entry.ref);
          });
          if ((await entry.ref.get()).exists) remainingIds.push(id); else deletedIds.push(id);
        } catch (_) { failures.push(id); }
      }
      let afterCount = null;
      try { afterCount = await count(); } catch (_) { failures.push('count-unavailable'); }
      return {attemptedIds: [...planned.keys()], deletedIds, remainingIds, failures, afterCount};
    },
  };
}

async function runBrowserInbox({fixture, candidateIdentity, db, page, openApp, currentUid, screenshot, timeoutMs = 240000}) {
  const store = createInboxStore({fixture, candidateIdentity, db, attemptId: crypto.randomBytes(12).toString('hex')});
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1000 || timeoutMs > 300000) reject('inbox-invalid-deadline');
  const report = {schemaVersion: 1, identity: store.identity, evidenceKind: KIND, assertions: [], entries: [], cleanup: null};
  const end = Date.now() + timeoutMs;
  const remaining = () => { const value = end - Date.now(); if (value <= 0) reject('inbox-deadline-exceeded'); return Math.min(value, 60000); };
  const check = (id, expected, actual) => { report.assertions.push({id, expected, actual}); if (!isDeepStrictEqual(expected, actual)) reject(`inbox-${id}`); };
  let failure;
  try {
    check('owner-authenticated-before-fixtures', fixture.owner.uid, await currentUid());
    check('inbox-empty-before-synthetic-fixtures', 0, await store.preflight());
    for (const item of fixtureCases(fixture)) {
      check(`${item.id}-owner-before-create`, fixture.owner.uid, await currentUid());
      const entry = await store.create(item); report.entries.push(entry);
      await openApp('/app/discover'); remaining();
      check(`${item.id}-owner-before-tap`, fixture.owner.uid, await currentUid());
      await page.getByRole('button', {name: 'Notifications', exact: true}).click({timeout: remaining()});
      await page.getByText(entry.title, {exact: true}).click({timeout: remaining()});
      if (item.batch) {
        await page.getByText('Discover', {exact: true}).first().waitFor({state: 'visible', timeout: remaining()});
        await page.getByRole('button', {name: 'Notifications', exact: true}).waitFor({state: 'visible', timeout: remaining()});
        check(`${item.id}-explicit-discover-url`, `${candidateIdentity.baseUrl}/app/discover`, page.url());
      } else {
        await page.getByText(fixture.event.title, {exact: true}).first().waitFor({state: 'visible', timeout: remaining()});
        await page.getByText('Manage event', {exact: true}).waitFor({state: 'visible', timeout: remaining()});
        check(`${item.id}-owned-event-visible`, fixture.event.title, await page.getByText(fixture.event.title, {exact: true}).first().innerText());
      }
      check(`${item.id}-inbox-tile-left`, 0, await page.getByText(entry.title, {exact: true}).count());
      let state;
      const readDeadline = Date.now() + Math.min(10000, remaining());
      do {
        state = await store.read(entry.id);
        if (state.isRead || Date.now() >= readDeadline) break;
        await new Promise((resolve) => setTimeout(resolve, 200));
      } while (true);
      check(`${item.id}-read-by-real-client`, true, state.isRead);
      Object.assign(entry, state);
      if (screenshot) await screenshot(`synthetic-inbox-${item.id}.png`);
    }
  } catch (error) { failure = error; }
  finally {
    report.cleanup = await store.cleanup();
    for (const [id, expected, actual] of [
      ['synthetic-inbox-cleanup-failures', [], report.cleanup.failures],
      ['synthetic-inbox-cleanup-remaining', [], report.cleanup.remainingIds],
      ['inbox-empty-after-synthetic-fixtures', 0, report.cleanup.afterCount],
    ]) report.assertions.push({id, expected, actual});
    if (report.cleanup.failures.length || report.cleanup.remainingIds.length || report.cleanup.afterCount !== 0) failure = new Error('inbox-cleanup-incomplete');
  }
  if (failure) {
    // Do not propagate SDK messages, bearer URLs, account details or tokens.
    const error = new Error(/^inbox-[a-z0-9-]+$/.test(failure.message || '') ? failure.message : 'inbox-ui-execution-failed');
    error.inboxReport = report; throw error;
  }
  return report;
}

module.exports = {runBrowserInbox, _test: {createInboxStore, fixtureCases, normalize}};
