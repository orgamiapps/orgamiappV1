"use strict";

const {spawnSync} = require("node:child_process");
const {readdirSync, readFileSync, statSync} = require("node:fs");
const {join} = require("node:path");

const allowedProjects = new Set(["attendus-staging", "orgami-66nxok"]);
const functionsRoot = join(__dirname, "..", "functions");

function javascriptFiles(directory) {
  const files = [];
  for (const entry of readdirSync(directory)) {
    if (["node_modules", "test", "tools"].includes(entry)) continue;
    const path = join(directory, entry);
    if (statSync(path).isDirectory()) files.push(...javascriptFiles(path));
    else if (entry.endsWith(".js")) files.push(path);
  }
  return files;
}

function main() {
  const projectId = process.argv[2];
  if (!projectId || !allowedProjects.has(projectId)) {
    throw new Error(
        "Usage: node tools/check_function_secrets.js " +
        "<attendus-staging|orgami-66nxok>",
    );
  }
  const secrets = new Set();
  for (const file of javascriptFiles(functionsRoot)) {
    const source = readFileSync(file, "utf8");
    for (const match of source.matchAll(/defineSecret\(\s*["']([^"']+)["']/g)) {
      secrets.add(match[1]);
    }
  }
  const missing = [];
  const gcloudCommand = process.platform === "win32" ? "gcloud.cmd" : "gcloud";
  for (const secret of [...secrets].sort()) {
    try {
      const result = spawnSync(gcloudCommand, [
        "secrets",
        "describe",
        secret,
        "--project",
        projectId,
        "--format=value(name)",
      ], {stdio: "ignore", shell: process.platform === "win32"});
      if (result.status !== 0) missing.push(secret);
    } catch (_error) {
      missing.push(secret);
    }
  }
  if (missing.length) {
    throw new Error(
        `Missing required secrets in ${projectId}: ${missing.join(", ")}`,
    );
  }
  process.stdout.write(
      `Verified ${secrets.size} function secrets in ${projectId}.\n`,
  );
}

try {
  main();
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
}
