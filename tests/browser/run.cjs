'use strict';
const {spawnSync} = require('node:child_process');
const path = require('node:path');
const crypto = require('node:crypto');
if (process.env.GCLOUD_PROJECT !== 'demo-attendus-admin' ||
    !/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || '')) {
  throw new Error('Browser verification requires the isolated demo emulator runner.');
}
process.env.ATTENDUS_BROWSER_RUN_ID = 'browser-' + crypto.randomBytes(8).toString('hex');
process.env.ATTENDUS_FIXTURE_TOKEN = crypto.randomBytes(32).toString('hex');
process.env.ATTENDUS_BROWSER_EVIDENCE = path.resolve(__dirname, 'test-results');
const readiness = spawnSync(process.env.PYTHON || 'python', ['-c',
  'from tools.run_flutter_integration import wait_for_functions; print(wait_for_functions())'],
{cwd: path.resolve(__dirname, '../..'), env: process.env, stdio: 'inherit', windowsHide: true});
if (readiness.status !== 0 || readiness.error) throw new Error('Functions metadata readiness failed; no browser tests started.');
const result = spawnSync(process.execPath, [require.resolve('@playwright/test/cli'), 'test',
  ...(process.env.ATTENDUS_BROWSER_PROJECT ? ['--project', process.env.ATTENDUS_BROWSER_PROJECT] : [])],
{cwd: __dirname, env: process.env, stdio: 'inherit', windowsHide: true});
process.exitCode = result.status || (result.error ? 1 : 0);
