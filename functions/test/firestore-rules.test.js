'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');

let env;
test.before(async () => { env = await initializeTestEnvironment({projectId: 'attendus-admin-rules-test', firestore: {rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'), host: '127.0.0.1', port: 8080}}); });
test.after(async () => { await env?.cleanup(); });

for (const role of ['ordinary', 'super_admin', 'support', 'billing_admin', 'analyst', 'moderator']) {
  test(`${role} client cannot write server-only collections`, async () => {
    const token = role === 'ordinary' ? {} : {admin: true, role};
    const db = env.authenticatedContext(`${role}-uid`, token).firestore();
    for (const collection of ['admin_roles', 'admin_audit_logs', 'admin_metrics_daily', 'admin_metrics_current', 'admin_jobs', 'subscriptions']) await assertFails(db.collection(collection).doc('target').set({roles: ['super_admin'], tier: 'premium'}));
  });
}
test('ordinary user can read only their own subscription', async () => {
  await env.withSecurityRulesDisabled(async (context) => context.firestore().collection('subscriptions').doc('user-a').set({tier: 'basic'}));
  const db = env.authenticatedContext('user-a').firestore();
  await assertSucceeds(db.collection('subscriptions').doc('user-a').get());
  await assertFails(db.collection('subscriptions').doc('user-b').get());
});
