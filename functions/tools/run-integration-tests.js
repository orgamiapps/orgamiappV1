"use strict";

const {mkdtempSync, rmSync, writeFileSync, readFileSync, existsSync, unlinkSync} = require("node:fs");
const {generateKeyPairSync} = require("node:crypto");
const {tmpdir} = require("node:os");
const {join} = require("node:path");
const {spawnSync} = require("node:child_process");
const {emulatorEnvironment, sanitizeEmulatorLog} = require("./emulator-environment");

const requiredProject = "demo-attendus-admin";
const emulatorConfig = require("../../firebase.test.json").emulators;
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
const recoveryRoot = join(__dirname, "../../build", `migration-recovery-${Date.now()}`);

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

const allSuites = [
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
  {
    name: "community",
    emulators: "firestore",
    file: "test/community-emulator.test.js test/live-quiz-emulator.test.js test/notification-boundaries-emulator.test.js test/staff-profile-lookup-emulator.test.js test/analytics-trigger-transition-emulator.test.js test/qualification-isolation-emulator.test.js",
  },
  {
    name: "migration-recovery-seed",
    emulators: "firestore",
    command: "node test/migration-recovery-emulator.js seed",
  },
  {
    name: "migration-recovery-restore",
    emulators: "firestore",
    command: "node test/migration-recovery-emulator.js restore",
    restore: true,
  },
  {
    name: "public-browser",
    emulators: "auth,firestore,functions",
    command: "node ../tests/browser/run.cjs",
    optional: true,
  },
  {
    name: "flutter-browser",
    emulators: "auth,firestore,storage,functions",
    command: "python ../tools/run_flutter_integration.py",
    optional: true,
  },
];
const requestedSuite = argumentValue("--suite");
const suites = requestedSuite ? allSuites.filter((suite) => suite.name === requestedSuite ||
  requestedSuite === "migration-recovery" && suite.name.startsWith("migration-recovery-")) : allSuites.filter((suite) => !suite.optional);
if (!suites.length) fail(`Unknown integration suite: ${requestedSuite}`);

// The emulator otherwise asks Secret Manager for bound secrets even under a
// demo project. Keep both Wallet providers absent, and use only local fixtures.
const secretPath = join(__dirname, "..", ".secret.local");
const previousSecrets = existsSync(secretPath) ? readFileSync(secretPath) : null;
const signingPair = generateKeyPairSync("ed25519");
const fixtureSecrets = [
  "GUEST_CONTACT_KMS_KEY_NAME=emulator", "GUEST_CONTACT_HMAC_KEY=emulator-only-contact-hmac-key-32-bytes",
  "STRIPE_SECRET_KEY=sk_test_emulator_unconfigured", "STRIPE_WEBHOOK_SECRET=whsec_emulator_unconfigured",
  "GOOGLE_PLACES_API_KEY=emulator-unconfigured", "MICROSOFT_TENANT_ID=emulator-unconfigured",
  "MICROSOFT_CLIENT_ID=emulator-unconfigured", "MICROSOFT_CERT_THUMBPRINT=emulator-unconfigured",
  "MICROSOFT_PRIVATE_KEY=emulator-unconfigured",
  `ATTENDANCE_PASS_SIGNING_KEY='${JSON.stringify({kid: "emulator", privateKey: signingPair.privateKey.export({format: "pem", type: "pkcs8"})})}'`,
].join("\n") + "\n";
writeFileSync(secretPath, fixtureSecrets);
process.once("exit", () => {
  if (previousSecrets) writeFileSync(secretPath, previousSecrets);
  else if (existsSync(secretPath)) unlinkSync(secretPath);
});
process.once("SIGINT", () => process.exit(130));
process.once("SIGTERM", () => process.exit(143));

for (let pass = 1; pass <= repeat; pass += 1) {
  for (const suite of suites) {
    const isolatedCloudConfig = mkdtempSync(join(tmpdir(), "attendus-emulator-"));
    const childEnv = emulatorEnvironment(process.env);
    // Point ADC at an ephemeral, deliberately nonexistent demo identity. Merely
    // unsetting ADC allows the SDK to discover the owner's gcloud credentials.
    const dummyCredential = join(isolatedCloudConfig, "emulator-only.json");
    const pair = generateKeyPairSync("rsa", {modulusLength: 2048});
    writeFileSync(dummyCredential, JSON.stringify({type: "service_account", project_id: projectId,
      private_key: pair.privateKey.export({format: "pem", type: "pkcs8"}),
      client_email: `emulator-only@${projectId}.iam.gserviceaccount.com`, token_uri: "http://127.0.0.1:1/token"}));
    childEnv.GOOGLE_APPLICATION_CREDENTIALS = dummyCredential;
    childEnv.CLOUDSDK_CONFIG = isolatedCloudConfig;
    childEnv.GCLOUD_PROJECT = projectId;
    childEnv.GOOGLE_CLOUD_PROJECT = projectId;
    childEnv.FUNCTIONS_EMULATOR = "true";
    childEnv.FUNCTIONS_DISCOVERY_TIMEOUT = "120";
    // Pinned CLI/SDK support one-shot manifest discovery. On Windows this
    // avoids local HTTP discovery and its leftover server after startup errors.
    if (process.platform === "win32") childEnv.FIREBASE_FUNCTIONS_DISCOVERY_OUTPUT_PATH = "true";
    childEnv.FIREBASE_FUNCTIONS_EMULATOR_HOST = `127.0.0.1:${emulatorConfig.functions.port}`;
    childEnv.ATTENDUS_EMULATOR_PUBLIC_ORIGIN = "http://127.0.0.1:4173";
    childEnv.ATTENDUS_RECOVERY_DIRECTORY = `${recoveryRoot}-pass${pass}`;

    process.stdout.write(
        `\nIntegration pass ${pass}/${repeat}: ${suite.name}\n`,
    );
    const command = suite.command ||
      `node --test --test-concurrency=1 ${suite.file}`;
    const result = spawnSync(process.execPath, [
      firebaseEntry,
      "emulators:exec",
      "--config",
      "../firebase.test.json",
      "--project",
      projectId,
      "--only",
      suite.emulators,
      ...(suite.restore ? ["--import", join(childEnv.ATTENDUS_RECOVERY_DIRECTORY, "export")] : []),
      command,
    ], {
      cwd: join(__dirname, ".."),
      env: childEnv,
      stdio: "inherit",
      windowsHide: true,
    });
    const debugLog = join(__dirname, "..", "firebase-debug.log");
    if (existsSync(debugLog)) writeFileSync(debugLog, sanitizeEmulatorLog(readFileSync(debugLog, "utf8")));
    rmSync(isolatedCloudConfig, {recursive: true, force: true});
    if (result.status !== 0) process.exit(result.status || 1);
  }
}

process.stdout.write(
    `\nAll ${suites.length} integration suites passed ${repeat} time(s).\n`,
);
