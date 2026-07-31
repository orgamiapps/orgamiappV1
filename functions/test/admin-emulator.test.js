'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

const projectId = process.env.GCLOUD_PROJECT || 'demo-attendus-admin';
const api = `http://127.0.0.1:5001/${projectId}/us-central1/adminApi`;
const authApi = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
async function auth(method, body) { const response = await fetch(`${authApi}/accounts:${method}?key=emulator-key`, {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify(body)}); assert.equal(response.ok, true, await response.text()); return response.json(); }

test('emulator rejects non-admin and audited mutation creates record', async () => {
  if (!admin.apps.length) admin.initializeApp({projectId});
  const email = `support-${Date.now()}@example.test`, password = 'ValidPassword123!';
  const created = await auth('signUp', {email, password, returnSecureToken: true});
  const denied = await fetch(`${api}/v1/accounts`, {headers: {authorization: `Bearer ${created.idToken}`}});
  assert.equal(denied.status, 403); assert.equal((await denied.json()).error.code, 'ADMIN_CLAIM_REQUIRED');

  await admin.auth().setCustomUserClaims(created.localId, {admin: true});
  await admin.firestore().collection('admin_roles').doc(created.localId).set({active: true, roles: ['support']});
  const signedIn = await auth('signInWithPassword', {email, password, returnSecureToken: true});
  const target = await auth('signUp', {email: `target-${Date.now()}@example.test`, password, returnSecureToken: true});
  const requestId = `integration-${Date.now()}`;
  const changed = await fetch(`${api}/v1/accounts/${target.localId}/disable`, {method: 'POST', headers: {authorization: `Bearer ${signedIn.idToken}`, 'content-type': 'application/json', 'idempotency-key': `integration-key-${Date.now()}`, 'x-request-id': requestId}, body: JSON.stringify({reason: 'Verified emulator support case', confirmed: true})});
  assert.equal(changed.status, 200, await changed.text());
  const audit = await admin.firestore().collection('admin_audit_logs').where('requestId', '==', requestId).get();
  assert.equal(audit.size, 1); assert.equal(audit.docs[0].get('action'), 'account.disable');
});
