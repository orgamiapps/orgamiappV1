'use strict';

const crypto = require('node:crypto');
const {fail} = require('./errors');

function documentId(uid, key) { return crypto.createHash('sha256').update(`${uid}:${key}`).digest('hex'); }

async function runIdempotent(db, adminSdk, uid, key, operation) {
  if (typeof key !== 'string' || key.length < 12 || key.length > 200) fail(400, 'IDEMPOTENCY_KEY_REQUIRED', 'A unique Idempotency-Key of at least 12 characters is required.');
  const ref = db.collection('admin_idempotency').doc(documentId(uid, key));
  const existing = await ref.get();
  if (existing.exists) {
    const data = existing.data();
    if (data.state === 'complete') return data.response;
    fail(409, 'REQUEST_IN_PROGRESS', 'An operation with this idempotency key is in progress.');
  }
  await ref.create({uid, state: 'started', createdAt: adminSdk.firestore.FieldValue.serverTimestamp()});
  try {
    const response = await operation();
    await ref.update({state: 'complete', response, completedAt: adminSdk.firestore.FieldValue.serverTimestamp()});
    return response;
  } catch (error) {
    await ref.update({state: 'failed', errorCode: error.code || 'INTERNAL', failedAt: adminSdk.firestore.FieldValue.serverTimestamp()});
    throw error;
  }
}

module.exports = {runIdempotent};
