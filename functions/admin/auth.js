'use strict';

const {ROLE_PERMISSIONS, ROLES} = require('./constants');
const {fail} = require('./errors');

async function authorize(req, adminSdk, db, permission) {
  const header = req.get('authorization') || '';
  if (!header.startsWith('Bearer ')) fail(401, 'UNAUTHENTICATED', 'A Firebase ID token is required.');
  let token;
  try { token = await adminSdk.auth().verifyIdToken(header.slice(7), true); } catch (_) { fail(401, 'INVALID_TOKEN', 'The Firebase ID token is invalid or revoked.'); }
  if (token.admin !== true) fail(403, 'ADMIN_CLAIM_REQUIRED', 'Administrator access is not enabled.');
  const roleSnap = await db.collection('admin_roles').doc(token.uid).get();
  const roleData = roleSnap.data() || {};
  const roles = Array.isArray(roleData.roles) ? roleData.roles.filter((role) => ROLES.includes(role)) : [];
  if (!roleSnap.exists || roleData.active !== true || roles.length === 0) fail(403, 'ADMIN_ROLE_REQUIRED', 'No active administrator role is assigned.');
  const permitted = roles.some((role) => ROLE_PERMISSIONS[role].includes('*') || ROLE_PERMISSIONS[role].includes(permission));
  if (!permitted) fail(403, 'PERMISSION_DENIED', 'Your role does not permit this action.', {permission});
  return {uid: token.uid, email: token.email || null, roles, permission};
}

module.exports = {authorize};
