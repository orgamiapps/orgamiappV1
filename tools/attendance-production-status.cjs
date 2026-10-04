"use strict";
// Read-only production verification. Never accesses secret payloads.
const {createRequire} = require("node:module");
const req = createRequire(require("node:path").join(__dirname, "../functions/package.json"));
const {Agent, setGlobalDispatcher} = req("undici");
setGlobalDispatcher(new Agent({connect: {family: 4, timeout: 15000}}));
const auth = req("firebase-tools/lib/auth");
const {requireAuth} = req("firebase-tools/lib/requireAuth");
const {getSecretVersion} = req("firebase-tools/lib/gcp/secretManager");
const timer = setTimeout(() => {console.error("Production metadata verification timed out");process.exit(1);}, 45000);
(async () => {
  const account = auth.getGlobalDefaultAccount();
  await requireAuth({project: "orgami-66nxok", ...account});
  const version = await getSecretVersion("orgami-66nxok", "ATTENDANCE_PASS_SIGNING_KEY", "latest");
  console.log(JSON.stringify({projectId: "orgami-66nxok", secret: "ATTENDANCE_PASS_SIGNING_KEY", version: version.versionId, state: version.state, createTime: version.createTime}));
  const {Client} = req("firebase-tools/lib/apiv2");
  const firestore = new Client({urlPrefix: "https://firestore.googleapis.com", apiVersion: "v1"});
  try {
    const response = await firestore.get("projects/orgami-66nxok/databases/(default)/documents/AppConfig/attendance");
    const fields = response.body.fields || {};
    console.log(JSON.stringify({attendanceConfig: Object.fromEntries(
      ["smartArrival", "corePasses", "wallet", "appleDelivery", "googleDelivery"].map((name) => [name, fields[name] || null]))}));
  } catch (error) {
    if (error.status !== 404) throw error;
    console.log(JSON.stringify({attendanceConfig: "absent; disabled by default"}));
  }
  if (process.argv.includes("--functions")) {
    const client = new Client({urlPrefix: "https://cloudfunctions.googleapis.com", apiVersion: "v2"});
    const response = await client.get("projects/orgami-66nxok/locations/us-central1/functions", {queryParams: {pageSize: 1000}});
    if (response.body.nextPageToken) throw new Error("Inventory requires pagination");
    const functions = (response.body.functions || []).map((fn) => ({
      id: fn.name.split("/").pop(), state: fn.state, updateTime: fn.updateTime,
      revision: fn.serviceConfig?.revision, uri: fn.serviceConfig?.uri,
      source: fn.buildConfig?.source?.storageSource,
      secretBindings: (fn.serviceConfig?.secretEnvironmentVariables || []).map((item) => item.key),
      appleDelivery: fn.serviceConfig?.environmentVariables?.ATTENDANCE_APPLE_DELIVERY_ENABLED === "true",
      googleDelivery: fn.serviceConfig?.environmentVariables?.ATTENDANCE_GOOGLE_DELIVERY_ENABLED === "true",
    }));
    const expected = require("./check_function_manifest").expectedFunctions(require("node:fs").readFileSync(require("node:path").join(__dirname, "../functions/index.js"), "utf8"));
    const result = require("./check_function_manifest").verifyInventory(expected, functions);
    const output = {projectId: "orgami-66nxok", checkedAt: new Date().toISOString(), functions,
      sourceOnly: result.sourceOnly, liveOnly: result.liveOnly, inactive: result.inactive};
    const file = process.argv.includes("--before") ? "attendance-functions-before.json" : "attendance-functions-after.json";
    require("node:fs").writeFileSync(require("node:path").join(__dirname, "../build", file), JSON.stringify(output, null, 2));
    console.log(JSON.stringify({functions: functions.length, sourceOnly: result.sourceOnly, liveOnly: result.liveOnly,
      inactive: result.inactive, providerDeliveryEnabled: functions.some((fn) => fn.appleDelivery || fn.googleDelivery), inventory: file}));
  }
  clearTimeout(timer);
  process.exit(version.state === "ENABLED" ? 0 : 1);
})().catch((error) => {console.error(`Metadata verification failed: ${error.status || error.code || "unknown"}`);process.exit(1);});
