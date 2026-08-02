'use strict';

const {execSync} = require('node:child_process');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');

const root = join(__dirname, '..');
const source = readFileSync(join(root, 'functions', 'index.js'), 'utf8');
const ignored = new Set(['helloWorld']);
const expected = new Set();

for (const match of source.matchAll(/exports\.([A-Za-z0-9_]+)\s*=/g)) {
  if (!ignored.has(match[1])) expected.add(match[1]);
}

let payload;
try {
  payload = JSON.parse(execSync('firebase functions:list --json', {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'inherit'],
  }));
} catch (error) {
  console.error('Unable to read the deployed Firebase function inventory.');
  process.exit(error.status || 1);
}

const deployed = new Set((payload.result || []).map((entry) => entry.id));
const liveOnly = [...deployed].filter((name) => !expected.has(name)).sort();
const sourceOnly = [...expected].filter((name) => !deployed.has(name)).sort();

if (liveOnly.length || sourceOnly.length) {
  console.error('Firebase function deployment drift detected.');
  if (liveOnly.length) console.error(`Live only: ${liveOnly.join(', ')}`);
  if (sourceOnly.length) console.error(`Source only: ${sourceOnly.join(', ')}`);
  process.exit(1);
}

console.log(`Function manifest matches (${deployed.size} deployed functions).`);
