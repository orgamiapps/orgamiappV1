"use strict";

const {execFileSync} = require("node:child_process");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");

const allowedProjects = new Set(["attendus-staging", "orgami-66nxok"]);
const root = join(__dirname, "..");

function expectedFunctions(source) {
  const ignored = new Set(["helloWorld"]);
  const expected = new Set();
  for (const match of source.matchAll(/exports\.([A-Za-z0-9_]+)\s*=/g)) {
    if (!ignored.has(match[1])) expected.add(match[1]);
  }
  return expected;
}

function verifyInventory(expected, entries) {
  const deployed = new Set(entries.map((entry) => entry.id));
  return {
    deployed,
    liveOnly: [...deployed].filter((name) => !expected.has(name)).sort(),
    sourceOnly: [...expected].filter((name) => !deployed.has(name)).sort(),
    inactive: entries.filter((entry) => entry.state !== "ACTIVE")
        .map((entry) => `${entry.id}:${entry.state || "UNKNOWN"}`).sort(),
  };
}

function main() {
  const projectId = process.argv[2];
  if (!projectId) {
    throw new Error("Usage: node tools/check_function_manifest.js <project-id>");
  }
  if (!allowedProjects.has(projectId)) {
    throw new Error(`Unsupported Firebase project: ${projectId}`);
  }

  const source = readFileSync(join(root, "functions", "index.js"), "utf8");
  const expected = expectedFunctions(source);
  let payload;
  try {
    const firebaseEntry = require.resolve("firebase-tools/lib/bin/firebase", {
      paths: [join(root, "functions")],
    });
    payload = JSON.parse(execFileSync(process.execPath, [firebaseEntry,
      "functions:list",
      "--project",
      projectId,
      "--json",
    ], {
      cwd: root,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "inherit"],
    }));
  } catch (error) {
    throw new Error(
        `Unable to read deployed function inventory for ${projectId}.`,
        {cause: error},
    );
  }

  const result = verifyInventory(expected, payload.result || []);
  if (result.liveOnly.length || result.sourceOnly.length ||
      result.inactive.length) {
    process.stderr.write(`Firebase function drift in ${projectId}.\n`);
    if (result.liveOnly.length) {
      process.stderr.write(`Live only: ${result.liveOnly.join(", ")}\n`);
    }
    if (result.sourceOnly.length) {
      process.stderr.write(`Source only: ${result.sourceOnly.join(", ")}\n`);
    }
    if (result.inactive.length) {
      process.stderr.write(`Not ACTIVE: ${result.inactive.join(", ")}\n`);
    }
    process.exit(1);
  }

  process.stdout.write(
      `Function manifest matches ${projectId} ` +
      `(${result.deployed.size} ACTIVE functions).\n`,
  );
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exit(1);
  }
}

module.exports = {expectedFunctions, verifyInventory};
