"use strict";

const {mkdtempSync, rmSync} = require("node:fs");
const {tmpdir} = require("node:os");
const {join} = require("node:path");
const {spawnSync} = require("node:child_process");

const requiredProject = "demo-attendus-admin";
const args = process.argv.slice(2);

function argumentValue(name, fallback) {
  const index = args.indexOf(name);
  return index === -1 ? fallback : args[index + 1];
}

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

const nodeMajor = Number(process.versions.node.split(".")[0]);
if (nodeMajor !== 22) {
  fail(`Integration tests require Node 22; found ${process.version}.`);
}

const projectId = argumentValue("--project");
if (!projectId) fail("Integration tests require an explicit --project.");
if (projectId !== requiredProject) {
  fail(`Integration tests only allow the demo project ${requiredProject}.`);
}

const repeat = Number(argumentValue("--repeat", "1"));
if (!Number.isInteger(repeat) || repeat < 1 || repeat > 10) {
  fail("--repeat must be an integer from 1 through 10.");
}

const java = spawnSync("java", ["-version"], {
  encoding: "utf8",
  shell: false,
  windowsHide: true,
});
const javaVersionOutput = `${java.stdout || ""}\n${java.stderr || ""}`;
const javaMajor = Number(javaVersionOutput.match(/version "(\d+)/)?.[1]);
if (java.status !== 0 || javaMajor !== 21) {
  fail(`Integration tests require Java 21; found ${javaVersionOutput.trim()}.`);
}

let firebaseEntry;
try {
  firebaseEntry = require.resolve("firebase-tools/lib/bin/firebase");
} catch (_error) {
  fail("firebase-tools is not installed; run npm ci in functions first.");
}

const suites = [
  {
    name: "admin/account/ticket",
    emulators: "auth,firestore,storage,functions",
    file: "test/admin-emulator.test.js",
  },
  {
    name: "analytics-v2",
    emulators: "auth,firestore,functions",
    file: "test/analytics-emulator.test.js",
  },
  {
    name: "scheduled-reminders",
    emulators: "firestore,functions",
    file: "test/scheduled-reminders-emulator.test.js",
  },
];

for (let pass = 1; pass <= repeat; pass += 1) {
  for (const suite of suites) {
    const isolatedCloudConfig = mkdtempSync(join(tmpdir(), "attendus-emulator-"));
    const childEnv = {...process.env};
    delete childEnv.GOOGLE_APPLICATION_CREDENTIALS;
    delete childEnv.CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE;
    delete childEnv.GOOGLE_CLOUD_QUOTA_PROJECT;
    childEnv.CLOUDSDK_CONFIG = isolatedCloudConfig;
    childEnv.GCLOUD_PROJECT = projectId;
    childEnv.GOOGLE_CLOUD_PROJECT = projectId;

    process.stdout.write(
        `\nIntegration pass ${pass}/${repeat}: ${suite.name}\n`,
    );
    const command =
      `node --test --test-concurrency=1 ${suite.file}`;
    const result = spawnSync(process.execPath, [
      firebaseEntry,
      "emulators:exec",
      "--config",
      "../firebase.json",
      "--project",
      projectId,
      "--only",
      suite.emulators,
      command,
    ], {
      cwd: join(__dirname, ".."),
      env: childEnv,
      stdio: "inherit",
      windowsHide: true,
    });
    rmSync(isolatedCloudConfig, {recursive: true, force: true});
    if (result.status !== 0) process.exit(result.status || 1);
  }
}

process.stdout.write(
    `\nAll ${suites.length} integration suites passed ${repeat} time(s).\n`,
);
