'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const {createRequire} = require('node:module');
const fs = require('node:fs');
const {fixtureOwner} = require('./fixture-ownership.cjs');
const owner = fixtureOwner(process.env);
const ownedEvents = new Set(), ownedUsers = new Set();
const configBefore = new Map();
const startedAt = Date.now();
const backend = createRequire(path.resolve(__dirname, '../../functions/package.json'));
assert.equal(process.env.GCLOUD_PROJECT, 'demo-attendus-admin');
for (const key of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']) {
  assert.match(process.env[key] || '', /^127\.0\.0\.1:\d+$/);
}
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.GUEST_CONTACT_KMS_KEY_NAME = 'emulator';
process.env.GUEST_CONTACT_HMAC_KEY = 'emulator-only-contact-hmac-key-32-bytes';
const express = backend('express');
const admin = backend('./firebase-admin-compat');
const {createPublicWeb} = backend('./public-web/renderer');
const db = admin.firestore();
const app = express();
app.use('/__fixtures', (req, res, next) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'content-type,x-fixture-token');
  res.set('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});
app.use((req, res, next) => {
  if (req.path.startsWith('/__') && req.path !== '/__health') {
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Headers', 'content-type,x-fixture-token');
    if (req.method === 'OPTIONS') return res.sendStatus(204);
    if (!owner.authorizes(req.get('x-fixture-token'))) return res.sendStatus(403);
  }
  next();
});
app.use(express.json());
app.use(express.urlencoded({extended: false}));
app.get('/__health', (_req, res) => res.json({project: 'demo-attendus-admin', runId: owner.runId}));
function manifest() {
  const directory = process.env.ATTENDUS_BROWSER_EVIDENCE;
  if (!directory) return;
  fs.mkdirSync(directory, {recursive: true});
  fs.writeFileSync(path.join(directory, 'fixture-manifest.json'), JSON.stringify({runId: owner.runId,
    project: 'demo-attendus-admin', startedAt, eventIds: [...ownedEvents], userIds: [...ownedUsers]}, null, 2));
}
async function setConfig(name, value) {
  const ref = db.collection('AppConfig').doc(name);
  if (!configBefore.has(name)) { const before = await ref.get(); configBefore.set(name, before.exists ? before.data() : null); }
  await ref.set(value);
}
app.post('/__accounts/:role', async (req, res) => {
  if (!['owner', 'attendee'].includes(req.params.role)) return res.sendStatus(400);
  const uid = `${owner.runId}-${req.params.role}`, email = `${uid}@example.test`;
  const password = 'LocalFixturePassword123!';
  let user;
  try { user = await admin.auth().getUser(uid); } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
    user = await admin.auth().createUser({uid, email, password, emailVerified: true,
      displayName: req.params.role === 'owner' ? 'UI Fixture Organizer' : 'UI Fixture Attendee'});
  }
  if (!owner.ownsEmail(user.email)) return res.sendStatus(409);
  ownedUsers.add(uid); manifest();
  const profileRef = db.collection('Customers').doc(uid);
  if (!(await profileRef.get()).exists) await profileRef.create({uid, email, name: user.displayName,
    username: `u${owner.runId.slice(8, 16)}_${req.params.role}`, isDiscoverable: true, eventsCreated: 0, groupsCreated: 0,
    bio: 'Local browser qualification account.', createdAt: new Date()});
  res.json({uid, email, password, name: user.displayName});
});
app.post('/__track', async (req, res) => {
  if (req.body.idToken) {
    const token = await admin.auth().verifyIdToken(req.body.idToken);
    const user = await admin.auth().getUser(token.uid);
    if (!owner.ownsEmail(user.email) && !(token.firebase?.sign_in_provider === 'anonymous' && Date.parse(user.metadata.creationTime) >= startedAt)) return res.sendStatus(400);
    ownedUsers.add(user.uid);
  }
  if (req.body.eventId) {
    const event = await db.collection('Events').doc(req.body.eventId).get();
    if (!event.exists || !ownedUsers.has(event.get('customerUid'))) return res.sendStatus(400);
    ownedEvents.add(event.id);
    if (req.body.seedLegacyDoorQuestion === true) await event.ref.collection('EventQuestions').doc('legacy-door').set({
      id: 'legacy-door', questionTitle: 'Door access code', required: true});
  }
  manifest(); res.json({tracked: true});
});
app.post('/__event-window', async (req, res) => {
  if (!ownedEvents.has(req.body.eventId) || !/^[A-Za-z0-9 .:_-]{1,100}$/.test(req.body.operation || '') ||
      !['before', 'failure'].includes(req.body.phase)) return res.sendStatus(400);
  const snapshot = await db.collection('Events').doc(req.body.eventId).get();
  if (!snapshot.exists) return res.sendStatus(404);
  const event = snapshot.data(), attendance = backend('./attendance/v2');
  const policy = attendance.normalizePolicy(event), window = attendance.policyWindow(event, policy);
  const observation = {runId: owner.runId, eventId: snapshot.id, operation: req.body.operation,
    phase: req.body.phase, serverNow: new Date().toISOString(),
    clientNow: Number.isFinite(Date.parse(req.body.clientNow)) ? new Date(req.body.clientNow).toISOString() : null,
    startsAt: new Date(attendance.eventDateMillis(event)).toISOString(),
    opensAt: new Date(window.opensAtMs).toISOString(), closesAt: new Date(window.closesAtMs).toISOString(),
    opensBeforeMinutes: policy.opensBeforeMinutes, closesAfterMinutes: policy.closesAfterMinutes,
    openingMode: policy.openingMode, eventRevision: event.eventRevision, status: event.status};
  fs.appendFileSync(path.join(process.env.ATTENDUS_BROWSER_EVIDENCE, 'event-window-observations.jsonl'), JSON.stringify(observation) + '\n');
  res.json(observation);
});
app.post('/__fixtures/:id', async (req, res) => {
  const id = req.params.id;
  if (!owner.ownsId(id)) return res.sendStatus(400);
  ownedEvents.add(id); manifest();
  await setConfig('publicWeb', {publicPagesEnabled: true,
    inlineRegistrationEnabled: true, accountlessRegistrationEnabled: true,
    paidTicketCheckoutEnabled: false});
  await db.collection('Events').doc(id).set({customerUid: 'browser-organizer',
    id, groupName: 'Fixture Community', imageUrl: '',
    title: 'Browser fixture event', description: 'Accessible community registration.',
    private: req.body.private === true, isHidden: req.body.hidden === true, deleted: req.body.deleted === true,
    status: req.body.cancelled ? 'cancelled' : 'active',
    selectedDateTime: new Date(Date.now() + 86400000), eventDurationMinutes: 90,
    eventTimeZone: 'America/New_York', location: 'Test Hall', eventRevision: 1,
    ticketsEnabled: true, ticketPrice: req.body.paid ? 10 : 0, maxTickets: 5,
    confirmedRegistrationCount: 0, issuedTickets: 0, reservedTickets: 0,
    registrationPolicy: {mode: 'free_ticket', capacity: 5, waitlistEnabled: true}});
  await db.collection('Events').doc(id).collection('EventQuestions').doc('access').set({
    id: 'access', timing: 'registration', prompt: 'Accessibility needs',
    type: 'short_text', required: true});
  res.json({eventId: id});
});
app.get('/__fixtures/:id', async (req, res) => {
  if (!ownedEvents.has(req.params.id)) return res.sendStatus(400);
  const event = await db.collection('Events').doc(req.params.id).get();
  const registrations = await db.collection('RegisterAttendance').where('eventId', '==', req.params.id).get();
  const deliveries = await db.collection('EmulatorOutboundDeliveries').where('eventId', '==', req.params.id).get();
  res.json({confirmed: event.get('confirmedRegistrationCount'), registrations: registrations.size,
    capturedDeliveries: deliveries.size});
});
app.post('/__cleanup', async (_req, res) => {
  const deleted = new Set();
  const deletedObjects = [];
  for (const eventId of ownedEvents) {
    const jobs = await db.collection('EventExportJobs').where('eventId', '==', eventId).get();
    for (const job of jobs.docs) {
      if (!job.get('path')) continue;
      assert.match(process.env.FIREBASE_STORAGE_EMULATOR_HOST || '', /^127\.0\.0\.1:\d+$/);
      assert.equal(admin.getApp().options.storageBucket, 'demo-attendus-admin.appspot.com');
      assert.ok(job.get('path').startsWith(`private-event-exports/${job.id}/`));
      await admin.storage().bucket().file(job.get('path')).delete({ignoreNotFound: true});
      deletedObjects.push(job.get('path'));
    }
  }
  const collections = await db.listCollections();
  for (const collection of collections) {
    for (const [field, values] of [['eventId', [...ownedEvents]], ['ownerUid', [...ownedUsers]],
      ['customerUid', [...ownedUsers]], ['userId', [...ownedUsers]], ['actorUid', [...ownedUsers]],
      ['uid', [...ownedUsers]], ['targetId', [...ownedEvents]]]) {
      for (let offset = 0; offset < values.length; offset += 10) {
        const matches = await collection.where(field, 'in', values.slice(offset, offset + 10)).get();
        for (const doc of matches.docs) { await db.recursiveDelete(doc.ref); deleted.add(doc.ref.path); }
      }
    }
  }
  for (const id of ownedEvents) { await db.recursiveDelete(db.collection('Events').doc(id)); deleted.add(`Events/${id}`); }
  for (const uid of ownedUsers) {
    await db.recursiveDelete(db.collection('Customers').doc(uid));
    // Settings can exist below a missing users document. Delete the explicitly
    // owned fixture subtree, not only top-level records matched by uid fields.
    await db.recursiveDelete(db.collection('users').doc(uid));
    deleted.add(`users/${uid}`);
    await admin.auth().deleteUser(uid).catch((error) => {if (error.code !== 'auth/user-not-found') throw error;});
    deleted.add(`Customers/${uid}`);
  }
  for (const [name, before] of configBefore) {
    const ref = db.collection('AppConfig').doc(name);
    if (before === null) await ref.delete(); else await ref.set(before);
  }
  const remainingEvents = (await Promise.all([...ownedEvents].map((id) => db.collection('Events').doc(id).get()))).filter((doc) => doc.exists).map((doc) => doc.id);
  const remainingProfiles = (await Promise.all([...ownedUsers].map((id) => db.collection('Customers').doc(id).get()))).filter((doc) => doc.exists).map((doc) => doc.id);
  const remainingUserSettings = [];
  for (const uid of ownedUsers) {
    const user = db.collection('users').doc(uid);
    if ((await user.get()).exists || (await user.listCollections()).length) remainingUserSettings.push(uid);
  }
  const remainingAccounts = [];
  for (const uid of ownedUsers) {
    try {await admin.auth().getUser(uid); remainingAccounts.push(uid);} catch (error) {if (error.code !== 'auth/user-not-found') throw error;}
  }
  res.json({runId: owner.runId, deletedPaths: [...deleted], deletedObjects, remainingEvents, remainingProfiles, remainingUserSettings, remainingAccounts,
    complete: remainingEvents.length === 0 && remainingProfiles.length === 0 && remainingUserSettings.length === 0 && remainingAccounts.length === 0});
});
app.use('/public-web', express.static(path.resolve(__dirname, '../../web/public-web')));
app.use('/icons', express.static(path.resolve(__dirname, '../../web/icons')));
const publicWeb = createPublicWeb(admin);
app.use((req, res) => publicWeb(req, res));
const server = app.listen(4173, '127.0.0.1');
async function close() { server.close(); await db.terminate(); process.exit(0); }
process.on('SIGTERM', close); process.on('SIGINT', close);
