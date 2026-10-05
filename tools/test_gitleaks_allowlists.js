#!/usr/bin/env node
"use strict";

// Exercise the installed, checksum-pinned scanner rather than imitating its
// allowlist semantics. All generated values are local synthetic fixtures.
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const {spawnSync} = require("node:child_process");

function check(ok, message) {
  if (!ok) throw Error(message);
}

function run() {
  check(process.argv.length === 3, "Usage: node tools/test_gitleaks_allowlists.js <gitleaks-exe>");
  const executable = fs.realpathSync(process.argv[2]);
  const root = path.resolve(__dirname, "..");
  const config = path.join(root, ".gitleaks.toml");
  const version = spawnSync(executable, ["version"], {encoding: "utf8", timeout: 30000});
  check(!version.error && version.status === 0 && version.stdout.trim() === "8.30.1",
      "Expected the caller's checksum-pinned Gitleaks 8.30.1 executable");

  const allowedPaths = ["tests/browser/appcheck-browser.test.cjs", "tests/browser/appcheck-test-mode.test.cjs"];
  const fixtures = allowedPaths.map((file) => {
    const text = fs.readFileSync(path.join(root, file), "utf8");
    const match = text.match(/\bconst TOKEN = '([a-f0-9-]{36})';/);
    check(match && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(match[1]),
        "Expected the explicitly synthetic offline test fixture declaration");
    return match[1];
  });
  check(fixtures[0] === fixtures[1], "Both reviewed offline fixture values must agree");
  // Shuffle a balanced hexadecimal alphabet so the negative value comfortably
  // exceeds the scanner's entropy threshold without storing another UUID.
  const hex = "0123456789abcdef".repeat(2).split("");
  for (let i = hex.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [hex[i], hex[j]] = [hex[j], hex[i]];
  }
  hex[12] = "4";
  hex[16] = "8";
  const compact = hex.join("");
  const different = [compact.slice(0, 8), compact.slice(8, 12), compact.slice(12, 16),
    compact.slice(16, 20), compact.slice(20)].join("-");
  check(different !== fixtures[0], "Unexpected synthetic fixture collision");

  const cases = [
    ...allowedPaths.map((file, i) => ({name: `exact-fixture-control-${i + 1}`, file, value: fixtures[0], count: 0})),
    ...allowedPaths.map((file, i) => ({name: `different-value-same-path-${i + 1}`, file, value: different, count: 1})),
    {name: "same-value-other-test-path", file: "tests/browser/other.test.cjs", value: fixtures[0], count: 1},
    {name: "same-value-product-path", file: "lib/appcheck.js", value: fixtures[0], count: 1},
    {name: "historical-manifest-path-negative", file: "docs/launch-candidate-manifest-20260927.json", value: different, count: 1},
    {name: "historical-podfile-path-negative", file: "ios/Podfile.lock", value: different, count: 1},
    {name: "historical-vapid-path-negative", file: "lib/firebase/firebase_messaging_helper.dart", value: different, count: 1},
  ];
  const tempParent = fs.realpathSync(os.tmpdir());
  const directory = fs.mkdtempSync(path.join(tempParent, "attendus-gitleaks-allowlists-"));
  const results = [];
  try {
    for (const [index, entry] of cases.entries()) {
      const work = path.join(directory, String(index));
      const target = path.join(work, ...entry.file.split("/"));
      fs.mkdirSync(path.dirname(target), {recursive: true});
      fs.writeFileSync(target, `const token = '${entry.value}';\n`, {flag: "wx"});
      const report = path.join(directory, `report-${index}.json`);
      const result = spawnSync(executable, ["dir", "--redact", "--config", config,
        "--report-format", "json", "--report-path", report, "."],
      {cwd: work, encoding: "utf8", timeout: 30000, maxBuffer: 1024 * 1024});
      // Never print scanner output, fixture values, or raw findings.
      let findings;
      try {
        findings = JSON.parse(fs.readFileSync(report, "utf8"));
      } catch {
        findings = null;
      }
      const pass = !result.error && result.status === (entry.count ? 1 : 0) &&
        Array.isArray(findings) && findings.length === entry.count &&
        findings.every((finding) => finding.RuleID === "generic-api-key" &&
          finding.File.replaceAll("\\", "/") === entry.file);
      results.push({name: entry.name, path: entry.file, expectedFindings: entry.count,
        actualFindings: Array.isArray(findings) ? findings.length : null, pass});
    }
  } finally {
    // This is the one directory created by this invocation. Verify both its
    // resolved containment and identity before recursive cleanup on Windows.
    const resolved = fs.realpathSync(directory);
    check(resolved === directory && path.dirname(resolved) === tempParent &&
      path.basename(resolved).startsWith("attendus-gitleaks-allowlists-") &&
      !fs.lstatSync(directory).isSymbolicLink(), "Temporary cleanup target changed");
    fs.rmSync(resolved, {recursive: true, force: false});
  }
  for (const result of results) console.log(JSON.stringify(result));
  const failures = results.filter((result) => !result.pass).length;
  console.log(JSON.stringify({scanner: "gitleaks", version: "8.30.1", cases: results.length,
    passed: results.length - failures, failed: failures, syntheticOnly: true}));
  process.exitCode = failures ? 1 : 0;
}

try {
  run();
} catch (error) {
  // All thrown diagnostics are fixed local setup descriptions, not scanner data.
  console.error(error instanceof Error && !error.code ? error.message : "Gitleaks allowlist regression setup failed");
  process.exitCode = 1;
}
