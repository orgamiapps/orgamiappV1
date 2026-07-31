'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {authorize} = require('../admin/auth');
const validate = require('../admin/validation');
const {writeAudit} = require('../admin/audit');
const {canAssignRoles} = require('../admin/rbac');
const {planForPrice, tierForPlan} = require('../admin/subscriptions');

function roleDb(data) { return {collection: () => ({doc: () => ({get: async () => ({exists: Boolean(data), data: () => data})})})}; }
function sdk(token) { return {auth: () => ({verifyIdToken: async () => token}), firestore: {FieldValue: {serverTimestamp: () => 'SERVER_TIME'}}}; }
const req = {get: () => 'Bearer valid'};

test('non-admin ID token cannot call an admin endpoint', async () => {
  await assert.rejects(authorize(req, sdk({uid: 'user', admin: false}), roleDb({active: true, roles: ['support']}), 'accounts.read'), (error) => error.code === 'ADMIN_CLAIM_REQUIRED');
});
test('coarse claim without active role is rejected', async () => {
  await assert.rejects(authorize(req, sdk({uid: 'user', admin: true}), roleDb({active: false, roles: ['support']}), 'accounts.read'), (error) => error.code === 'ADMIN_ROLE_REQUIRED');
});
test('billing role cannot grant super-admin access', () => {
  assert.equal(canAssignRoles(['billing_admin'], ['super_admin']), false);
  assert.equal(canAssignRoles(['super_admin'], ['support']), true);
});
test('destructive validation requires confirmation and meaningful reason', () => {
  assert.throws(() => validate.mutation({reason: 'too short', confirmed: true}, true));
  assert.throws(() => validate.mutation({reason: 'A sufficiently clear reason', confirmed: false}, true));
  assert.equal(validate.mutation({reason: 'A sufficiently clear reason', confirmed: true}, true), 'A sufficiently clear reason');
});
test('audit logging uses create and sanitizes secrets', async () => {
  let written; const db = {collection: () => ({doc: () => ({id: 'audit-1', create: async (data) => { written = data; }})})};
  const id = await writeAudit(db, sdk({}), {actor: {uid: 'admin-1', email: 'a@example.com', roles: ['support']}, action: 'account.disable', targetType: 'account', targetId: 'u1', reason: 'Confirmed support request', requestId: 'r1', metadata: {token: 'hidden', caseId: 'c1'}});
  assert.equal(id, 'audit-1'); assert.equal(written.metadata.token, undefined); assert.equal(written.metadata.caseId, 'c1');
});
test('subscription entitlements derive only from configured Stripe price', () => {
  const env = {STRIPE_PRICE_PREMIUM_MONTHLY: 'price_premium'};
  assert.equal(planForPrice('price_premium', env), 'premium_monthly'); assert.equal(tierForPlan('premium_monthly'), 'premium'); assert.equal(tierForPlan('arbitrary'), 'free');
});
