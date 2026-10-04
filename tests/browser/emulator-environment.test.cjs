'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {emulatorEnvironment, sanitizeEmulatorLog} = require('../../functions/tools/emulator-environment');
test('emulator process receives runtime paths but no inherited credentials or cloud target', () => {
  const source = {Path: 'node;java', SystemRoot: 'Windows', CHROME_EXECUTABLE: 'chrome',
    GOOGLE_APPLICATION_CREDENTIALS: 'real.json', GOOGLE_CLOUD_PROJECT: 'production',
    API_SERVER_KEY: 'private', CLOUDFLARE_API_TOKEN: 'private', NODE_OPTIONS: '--require=arbitrary.js',
    ATTENDUS_FIXTURE_TOKEN: 'private', ATTENDUS_TEST_EDGE: '1'};
  assert.deepEqual(emulatorEnvironment(source), {Path: 'node;java', SystemRoot: 'Windows',
    CHROME_EXECUTABLE: 'chrome', ATTENDUS_TEST_EDGE: '1'});
});
test('retained diagnostics remove environment dumps and authorization tokens', () => {
  const input = '[debug] Running python test with environment {"API_SERVER_KEY":"private"}\n' +
    'request Bearer opaque-token\nfixture eyJhbGci.eyJ1aWQi.signature\nError: metadata not loaded';
  const output = sanitizeEmulatorLog(input);
  assert.equal(output.includes('private'), false);
  assert.equal(output.includes('opaque-token'), false);
  assert.equal(output.includes('eyJ'), false);
  assert.equal(output.includes('Error: metadata not loaded'), true);
});
