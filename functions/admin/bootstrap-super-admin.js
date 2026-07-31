#!/usr/bin/env node
'use strict';

const admin = require('firebase-admin');

function arg(name) { const index = process.argv.indexOf(`--${name}`); return index >= 0 ? process.argv[index + 1] : null; }

async function main() {
  const projectId = arg('project');
  const email = arg('email');
  const confirm = arg('confirm');
  if (!projectId || !email || confirm !== `BOOTSTRAP:${email}`) {
    throw new Error('Usage: node admin/bootstrap-super-admin.js --project PROJECT_ID --email EMAIL --confirm "BOOTSTRAP:EMAIL"');
  }
  admin.initializeApp({projectId, credential: admin.credential.applicationDefault()});
  const user = await admin.auth().getUserByEmail(email);
  const claims = user.customClaims || {};
  await admin.auth().setCustomUserClaims(user.uid, {...claims, admin: true});
  const db = admin.firestore();
  await db.collection('admin_roles').doc(user.uid).set({roles: ['super_admin'], active: true, updatedBy: 'bootstrap-cli', updatedAt: admin.firestore.FieldValue.serverTimestamp()});
  await db.collection('admin_audit_logs').doc().create({actorUid: 'bootstrap-cli', actorEmail: null, actorRoles: ['bootstrap'], action: 'admin.bootstrap', targetType: 'account', targetId: user.uid, reason: 'Explicit first-super-admin bootstrap', requestId: `bootstrap-${Date.now()}`, before: null, after: {roles: ['super_admin'], active: true}, metadata: {projectId}, createdAt: admin.firestore.FieldValue.serverTimestamp()});
  console.log(`Bootstrapped super_admin for ${email} (${user.uid}) in ${projectId}. Re-authentication is required.`);
}

if (require.main === module) main().catch((error) => { console.error(error.message); process.exitCode = 1; });
module.exports = {main};
