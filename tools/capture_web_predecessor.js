"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {googleClient, pages, captureState} = require("./web_release_state");
const {sha256, digest, relativeFile} = require("./web_release_contract");
async function capture({state, output, client}) {
  if (state.projectId !== "attendus-staging" || !state.hostingVersion?.startsWith("sites/attendus-staging/versions/")) throw Error("Predecessor archive is restricted to the captured staging version");
  client ||= await googleClient();
  const before = await captureState(state.projectId, client);
  if (digest(before.state) !== digest(state)) throw Error("Staging changed before predecessor capture");
  const inventory = await pages(client, `https://firebasehosting.googleapis.com/v1beta1/${state.hostingVersion}/files`, "files");
  if (!inventory.length || inventory.length > 20000) throw Error("Unexpected predecessor file count");
  const names = inventory.map((entry) => relativeFile(entry.path.replace(/^\//, "")));
  if (new Set(names).size !== names.length || !names.includes("index.html")) throw Error("Invalid predecessor file inventory");
  const files = Object.create(null); const queue = [...names]; let total = 0;
  await Promise.all(Array.from({length: 4}, async () => {
    while (queue.length) {
      const name = queue.shift();
      const response = await fetch(`https://attendus-staging.web.app/${name.split("/").map(encodeURIComponent).join("/")}`, {signal: AbortSignal.timeout(60000), cache: "no-store", redirect: "error"});
      if (!response.ok) throw Error(`Predecessor HTTP ${response.status}: ${name}`);
      const bytes = Buffer.from(await response.arrayBuffer()); total += bytes.length;
      if (bytes.length > 64 * 1024 * 1024 || total > 1024 * 1024 * 1024) throw Error("Predecessor exceeds bounded archive budget");
      const target = path.join(output, "web", name); fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, bytes); files[name] = sha256(bytes);
    }
  }));
  const after = await captureState(state.projectId, client);
  if (after.stateSha256 !== before.stateSha256) throw Error("Staging changed during predecessor capture");
  const manifest = {schemaVersion: 1, projectId: state.projectId, hostingVersion: state.hostingVersion,
    capturedAt: after.capturedAt, deploymentStateSha256: after.stateSha256, files, filesSha256: digest(files), hostingFileInventory: inventory};
  fs.writeFileSync(path.join(output, "predecessor.json"), JSON.stringify(manifest, null, 2) + "\n");
  return manifest;
}
module.exports = {capture};
