'use strict';
const assert = require('node:assert/strict');
function fixtureOwner(env) {
  assert.equal(env.GCLOUD_PROJECT, 'demo-attendus-admin');
  assert.match(env.ATTENDUS_BROWSER_RUN_ID || '', /^browser-[a-f0-9]{16}$/);
  assert.match(env.ATTENDUS_FIXTURE_TOKEN || '', /^[a-f0-9]{64}$/);
  return {
    runId: env.ATTENDUS_BROWSER_RUN_ID,
    ownsId: (id) => typeof id === 'string' && id.startsWith(env.ATTENDUS_BROWSER_RUN_ID + '-') && /^[a-z0-9-]+$/.test(id),
    ownsEmail: (email) => typeof email === 'string' && email.startsWith(env.ATTENDUS_BROWSER_RUN_ID + '-') && email.endsWith('@example.test'),
    authorizes: (token) => token === env.ATTENDUS_FIXTURE_TOKEN,
  };
}
module.exports = {fixtureOwner};
