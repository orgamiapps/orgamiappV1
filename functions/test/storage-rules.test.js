'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');

let env;
const token = {firebase: {sign_in_provider: 'password'}};

test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-attendus-admin',
    firestore: {host: '127.0.0.1', port: 8080},
    storage: {
      host: '127.0.0.1',
      port: 9199,
      rules: fs.readFileSync(path.join(__dirname, '../../storage.rules'), 'utf8'),
    },
  });
});
test.beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
});
test.after(async () => env?.cleanup());

const storageFor = (uid) => env.authenticatedContext(uid, token).storage();
const png = Buffer.from('89504e470d0a1a0a', 'hex');

test('users can upload only their own bounded profile image', async () => {
  await assertSucceeds(storageFor('user-a').ref('profile_pictures/user-a.jpg').put(png, {contentType: 'image/png'}));
  await assertFails(storageFor('user-a').ref('profile_pictures/user-b.jpg').put(png, {contentType: 'image/png'}));
  await assertFails(storageFor('user-a').ref('profile_pictures/user-a.jpg').put(Buffer.from('text'), {contentType: 'text/plain'}));
});

test('organization uploads require an approved administrator', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('Organizations').doc('org-a').set({createdBy: 'owner'});
    await db.collection('Organizations').doc('org-a').collection('Members').doc('owner').set({
      role: 'owner', status: 'approved', userId: 'owner',
    });
    await db.collection('Organizations').doc('org-a').collection('Members').doc('member').set({
      role: 'member', status: 'approved', userId: 'member',
    });
  });
  await assertSucceeds(storageFor('owner').ref('organizations/org-a/logo.png').put(png, {contentType: 'image/png'}));
  await assertFails(storageFor('member').ref('organizations/org-a/logo-2.png').put(png, {contentType: 'image/png'}));
  await assertFails(storageFor('stranger').ref('organizations/org-a/logo-3.png').put(png, {contentType: 'image/png'}));
});

test('unknown storage paths are denied', async () => {
  await assertFails(storageFor('user-a').ref('unreviewed/user-a/file.png').put(png, {contentType: 'image/png'}));
});
