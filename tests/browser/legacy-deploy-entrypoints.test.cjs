'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const scripts = [
  'deploy_web.sh',
  'deploy_firestore_rules.sh',
  'deploy_guest_mode_fix.sh',
  'DEPLOY_JOIN_APPROVAL_NOTIFICATIONS.sh',
  'setup_google_wallet.sh',
];
const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : '/bin/bash';
const shellPath = value => process.platform === 'win32'
  ? value.replace(/\\/g, '/').replace(/^([A-Za-z]):/, (_, drive) => '/' + drive.toLowerCase())
  : value;

function fixture(t, filename) {
  const parent = fs.realpathSync(os.tmpdir());
  const directory = fs.mkdtempSync(path.join(parent, 'attendus-legacy-deploy-test-'));
  const owned = fs.realpathSync(directory);
  t.after(() => {
    assert.equal(path.resolve(directory), owned);
    assert.equal(fs.realpathSync(directory), owned);
    assert.equal(path.dirname(owned), parent);
    assert.ok(path.basename(owned).startsWith('attendus-legacy-deploy-test-'));
    fs.rmSync(owned, {recursive: true, force: false});
  });
  const bin = path.join(directory, 'bin');
  fs.mkdirSync(bin);
  fs.mkdirSync(path.join(directory, 'functions'));
  fs.mkdirSync(path.join(directory, 'web'));
  fs.mkdirSync(path.join(directory, 'build', 'web'), {recursive: true});
  fs.writeFileSync(path.join(directory, 'web', 'flutter_service_worker_retirement.js'), '// isolated fixture\n');
  fs.writeFileSync(path.join(directory, 'pubspec.yaml'), 'name: isolated_no_network_fixture\n');
  // Match the Linux checkout's shell text on Windows too. These are copied
  // entrypoints in an owned temp directory, never scripts in the repository.
  fs.writeFileSync(path.join(directory, 'entry.sh'), fs.readFileSync(path.join(root, filename), 'utf8').replace(/\r\n/g, '\n'));
  const log = path.join(directory, 'commands.log');
  for (const command of ['firebase', 'flutter', 'dart', 'npm', 'cp', 'gcloud', 'gh', 'curl', 'wget']) {
    fs.writeFileSync(path.join(bin, command), '#!/bin/bash\n' +
      `printf '%s' '${command}' >> "$COMMAND_LOG"\n` +
      'printf " <%s>" "$@" >> "$COMMAND_LOG"\nprintf "\\n" >> "$COMMAND_LOG"\nexit 0\n', {mode: 0o700});
  }
  return {directory, log, env: {
    ...(process.platform === 'win32' ? {SystemRoot: process.env.SystemRoot, WINDIR: process.env.WINDIR} : {}),
    PATH: shellPath(bin), HOME: shellPath(directory), USERPROFILE: directory,
    TMP: directory, TEMP: directory, TMPDIR: directory,
    COMMAND_LOG: shellPath(log), GOOGLE_MAPS_WEB_API_KEY: 'synthetic-local-test-only',
    CI: 'true', FIREBASE_CONFIG: '{"projectId":"synthetic-default-production"}',
  }};
}

for (const filename of scripts) {
  for (const requestedOverride of [false, true]) {
    test(`${filename} blocks before any command${requestedOverride ? ' despite force arguments and environment' : ''}`, t => {
      assert.ok(fs.existsSync(bash), 'Bash is required; this guard must not silently skip');
      const f = fixture(t, filename);
      const stdinFile = path.join(f.directory, 'stdin.txt');
      fs.writeFileSync(stdinFile, 'synthetic-local-issuer\n');
      // An immediate exit can close a pipe before spawnSync writes its input.
      // Keep the same available input without a parent-to-child pipe write.
      const stdin = fs.openSync(stdinFile, 'r');
      let result;
      try {
        result = spawnSync(bash, ['--noprofile', '--norc', './entry.sh', ...(requestedOverride ? ['--force', '--project', 'orgami-66nxok'] : [])], {
          cwd: f.directory,
          env: {...f.env, ...(requestedOverride ? {ALLOW_DEPLOY: '1', FORCE_DEPLOY: 'true'} : {})},
          stdio: [stdin, 'pipe', 'pipe'], encoding: 'utf8', timeout: 5000, maxBuffer: 16384,
        });
      } finally {
        fs.closeSync(stdin);
      }
      assert.equal(result.error, undefined);
      const commands = fs.existsSync(f.log) ? fs.readFileSync(f.log, 'utf8').trim().split('\n') : [];
      assert.deepEqual(commands, [], 'No login, build, dependency install, deployment, provider setup or dispatch may run');
      assert.equal(result.status, 1);
      assert.match(result.stderr, /BLOCKED: legacy/);
      assert.match(result.stderr, /candidate.*qualif.*promot/i);
      assert.match(result.stderr, /\.github\/workflows\/firebase-release\.yml/);
      assert.equal(result.stdout, '');
    });
  }
}

test('existing recurring web-quality suite executes these guards', () => {
  const workflow = fs.readFileSync(path.join(root, '.github/workflows/web-quality.yml'), 'utf8');
  assert.match(workflow, /node --test[\s\S]*\.\.\/tests\/browser\/\*\.test\.cjs/);
});
