'use strict';

const crypto = require('node:crypto');

function sanitize(value) {
  if (!value || typeof value !== 'object') return value;
  const hidden = new Set(['authorization', 'token', 'password', 'secret', 'clientSecret']);
  return Object.fromEntries(Object.entries(value).filter(([key]) => !hidden.has(key)).map(([key, item]) => [key, sanitize(item)]));
}

async function writeAudit(db, adminSdk, {actor, action, targetType, targetId, reason, requestId, before, after, metadata}) {
  const ref = db.collection('admin_audit_logs').doc();
  await ref.create({
    actorUid: actor.uid,
    actorEmail: actor.email,
    actorRoles: actor.roles,
    action,
    targetType,
    targetId,
    reason,
    requestId,
    before: sanitize(before || null),
    after: sanitize(after || null),
    metadata: sanitize(metadata || {}),
    createdAt: adminSdk.firestore.FieldValue.serverTimestamp(),
    integrityKey: crypto.createHash('sha256').update(`${requestId}:${actor.uid}:${action}:${targetId}`).digest('hex'),
  });
  return ref.id;
}

module.exports = {writeAudit, sanitize};
