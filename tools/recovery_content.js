"use strict";
const crypto = require("node:crypto");
const RECOVERY_PROJECT = "attendus-recovery-20261004";
const HEARTBEATS = ["EventOperationScans/EventAnnouncements", "EventOperationScans/EventExportJobs", "EventOperationScans/rosterCleanup"];
const canonical = (value) => Array.isArray(value) ? `[${value.map(canonical).join(",")}]` : value && typeof value === "object" ?
  `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}` : JSON.stringify(value);
const digest = (value) => crypto.createHash("sha256").update(canonical(value)).digest("hex");

async function inventoryRestoredContent(client, {readTime = new Date(Date.now() - 5000).toISOString(), maxDocuments = 100000, maxRequests = 150000} = {}) {
  const base = `https://firestore.googleapis.com/v1/projects/${RECOVERY_PROJECT}/databases/(default)/documents`;
  const queue = [""], records = Object.create(null), collectionCounts = Object.create(null), heartbeatFields = Object.create(null);
  let requests = 0, active = 0;
  async function api(suffix, method = "GET", data) {
    if (++requests > maxRequests) throw Error("Recovery inventory exceeds its reviewed request budget");
    return (await client.request({url: `${base}${suffix}`, method, ...(data ? {data} : {})})).data;
  }
  async function children(parent) {
    const collections = []; let pageToken;
    do {
      const value = await api(`${parent}:listCollectionIds`, "POST", {pageSize: 1000, readTime, ...(pageToken ? {pageToken} : {})});
      collections.push(...(value.collectionIds || [])); pageToken = value.nextPageToken;
    } while (pageToken);
    for (const collection of collections) {
      let next;
      do {
        const params = new URLSearchParams({pageSize: "1000", showMissing: "true", readTime, ...(next ? {pageToken: next} : {})});
        const value = await api(`${parent}/${encodeURIComponent(collection)}?${params}`);
        for (const document of value.documents || []) {
          if (!document.name?.startsWith(`projects/${RECOVERY_PROJECT}/databases/(default)/documents/`)) throw Error("Recovery document provenance differs");
          const relative = document.name.split("/documents/")[1];
          queue.push(`/${relative.split("/").map(encodeURIComponent).join("/")}`);
          if (!document.createTime) continue; // Traverse missing ancestors too.
          if (Object.keys(records).length >= maxDocuments) throw Error("Recovery inventory exceeds its reviewed document budget");
          records[digest(relative)] = digest(document.fields || {});
          const group = relative.split("/").at(-2); collectionCounts[group] = (collectionCounts[group] || 0) + 1;
          if (HEARTBEATS.includes(relative)) heartbeatFields[relative] = {fields: Object.fromEntries(Object.entries(document.fields || {}).map(([name, value]) => [name, {type: Object.keys(value)[0], sha256: digest(value)}]))};
        }
        next = value.nextPageToken;
      } while (next);
    }
  }
  await new Promise((resolve, reject) => {
    let failed = false;
    function work() {
      if (failed) return;
      if (!queue.length && !active) return resolve();
      while (queue.length && active < 8) {
        const item = queue.shift(); active++;
        children(item).then(() => { active--; work(); }, (error) => { failed = true; reject(error); });
      }
    }
    work();
  });
  return {project: RECOVERY_PROJECT, readTime, capturedAt: new Date().toISOString(), documents: Object.keys(records).length,
    requests, collectionCounts, contentSha256: digest(records), records, heartbeatFields};
}
function compareRecoveryContent(source, restored, sourceHeartbeatFields = {}) {
  if (!source || !["orgami-66nxok", "attendus-staging"].includes(source.project) || restored.project !== RECOVERY_PROJECT ||
      !source.records || !restored.records || source.contentSha256 !== digest(source.records) || restored.contentSha256 !== digest(restored.records) ||
      source.documents !== Object.keys(source.records).length || restored.documents !== Object.keys(restored.records).length) throw Error("Recovery content manifests are incomplete or inconsistent");
  const changedPaths = Object.keys(source.records).filter((key) => restored.records[key] && restored.records[key] !== source.records[key]).sort();
  const missingPaths = Object.keys(source.records).filter((key) => !restored.records[key]).sort();
  const extraPaths = Object.keys(restored.records).filter((key) => !source.records[key]).sort();
  const explainedHeartbeatPaths = [];
  for (const relative of HEARTBEATS) {
    const key = digest(relative);
    if (!changedPaths.includes(key)) continue;
    const left = sourceHeartbeatFields[relative]?.fields, right = restored.heartbeatFields?.[relative]?.fields;
    if (!left || !right || left.updatedAt?.type !== "timestampValue" || right.updatedAt?.type !== "timestampValue") continue;
    const remaining = (fields) => Object.fromEntries(Object.entries(fields).filter(([name]) => name !== "updatedAt"));
    if (canonical(remaining(left)) === canonical(remaining(right))) explainedHeartbeatPaths.push(key);
  }
  return {schemaVersion: 1, source: {project: source.project, documents: source.documents, contentSha256: source.contentSha256},
    restored: {project: restored.project, documents: restored.documents, contentSha256: restored.contentSha256, readTime: restored.readTime},
    exactIdentical: !changedPaths.length && !missingPaths.length && !extraPaths.length,
    differences: {changedPaths, missingPaths, extraPaths}, explainedHeartbeatPaths: explainedHeartbeatPaths.sort(),
    businessContentEquivalent: !missingPaths.length && !extraPaths.length && changedPaths.every((key) => explainedHeartbeatPaths.includes(key))};
}
module.exports = {inventoryRestoredContent, compareRecoveryContent, canonical, digest, HEARTBEATS};
