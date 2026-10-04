'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {fixtureOwner} = require('./fixture-ownership.cjs');
const env = {GCLOUD_PROJECT: 'demo-attendus-admin', ATTENDUS_BROWSER_RUN_ID: 'browser-0123456789abcdef', ATTENDUS_FIXTURE_TOKEN: 'a'.repeat(64)};
test('fixture authority rejects cloud and missing run secrets', () => {
  assert.throws(() => fixtureOwner({...env, GCLOUD_PROJECT: 'attendus-staging'}));
  assert.throws(() => fixtureOwner({...env, ATTENDUS_FIXTURE_TOKEN: ''}));
});
test('fixture cleanup can identify only owned IDs and controlled mailboxes', () => {
  const owner = fixtureOwner(env);
  assert.equal(owner.ownsId(env.ATTENDUS_BROWSER_RUN_ID + '-event'), true);
  assert.equal(owner.ownsId('browser-other-event'), false);
  assert.equal(owner.ownsId(env.ATTENDUS_BROWSER_RUN_ID + '-../real-event'), false);
  assert.equal(owner.ownsEmail(env.ATTENDUS_BROWSER_RUN_ID + '-owner@example.test'), true);
  assert.equal(owner.ownsEmail(env.ATTENDUS_BROWSER_RUN_ID + '-owner@realmail.test'), false);
  assert.equal(owner.authorizes('wrong-token'), false);
});
