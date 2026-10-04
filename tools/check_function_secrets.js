"use strict";

const {spawnSync} = require("node:child_process");
const {join} = require("node:path");

const allowedProjects = new Set(["attendus-staging", "orgami-66nxok"]);
const functionsRoot = join(__dirname, "..", "functions");

function boundSecrets(functions) {
  const secrets = new Set();
  for (const fn of Object.values(functions)) {
    for (const binding of fn?.__endpoint?.secretEnvironmentVariables || []) {
      const name = typeof binding === "string" ? binding : binding.key;
      if (!name) throw new Error("Invalid function secret binding.");
      secrets.add(name);
    }
  }
  return secrets;
}

function deploymentSecrets(functions, declaredParams = []) {
  const secrets = boundSecrets(functions);
  for (const parameter of declaredParams) {
    const specification = typeof parameter.toSpec === "function" ? parameter.toSpec() : parameter;
    if (specification.type === "secret") secrets.add(specification.name);
  }
  return secrets;
}

function main() {
  const projectId = process.argv[2];
  if (!projectId || !allowedProjects.has(projectId)) {
    throw new Error(
        "Usage: node tools/check_function_secrets.js " +
        "<attendus-staging|orgami-66nxok>",
    );
  }
  // Firebase resolves declared secret parameters even when no endpoint binds
  // them, so inspect both the parameter specs and endpoint bindings.
  const functions = require(join(functionsRoot, "index.js"));
  const {declaredParams} = require(require.resolve("firebase-functions/params", {paths: [functionsRoot]}));
  const secrets = deploymentSecrets(functions, declaredParams);
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

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exit(1);
  }
}

module.exports = {boundSecrets, deploymentSecrets};
