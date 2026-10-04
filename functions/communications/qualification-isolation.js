"use strict";
const crypto = require("node:crypto");
const MAX_LEASE_MS = 72 * 60 * 60 * 1000;
const hash = (value) => crypto.createHash("sha256").update(String(value)).digest("hex");
const bindingId = (kind, id) => `${kind}_${hash(id)}`;
const emailHash = (value) => hash(String(value || "").trim().toLowerCase());
const millis = (value) => value?.toMillis?.() ?? (value instanceof Date ? value.getTime() : NaN);
const list = (value, max) => Array.isArray(value) && value.length <= max && value.every((item) => typeof item === "string" && item.length > 0 && item.length <= 500);

function validScope(data, runId, project, now) {
  return /^[A-Za-z0-9_-]{8,100}$/.test(runId || "") && data?.schemaVersion === 1 && data.projectId === project &&
    data.status === "active" && data.mode === "capture" && Number.isFinite(millis(data.createdAt)) &&
    millis(data.createdAt) <= now && millis(data.expiresAt) > now && millis(data.expiresAt) - millis(data.createdAt) <= MAX_LEASE_MS &&
    list(data.actorUids, 20) && list(data.recipientUids, 20) && list(data.eventIds, 50) &&
    list(data.organizationIds, 10) && list(data.conversationIds, 10) && list(data.recipientEmailHashes, 20) &&
    data.recipientEmailHashes.every((item) => /^[a-f0-9]{64}$/.test(item));
}
function projectId(env) {
  const project = env.GCLOUD_PROJECT || env.GOOGLE_CLOUD_PROJECT || "";
  return env.GCLOUD_PROJECT && env.GOOGLE_CLOUD_PROJECT && env.GCLOUD_PROJECT !== env.GOOGLE_CLOUD_PROJECT ? "" : project;
}
function associations(context) {
  return [...new Map([
    ["account", context.actorUid], ["account", context.recipientUid],
    ...[context.eventId, ...(context.eventIds || [])].map((id) => ["event", id]),
    ["organization", context.organizationId], ["conversation", context.conversationId],
  ].filter(([, id]) => typeof id === "string" && id).map(([kind, id]) => [bindingId(kind, id), {kind, id}])).values()];
}
async function qualificationDecision(db, context, tx = null, {now = Date.now(), env = process.env} = {}) {
  const project = projectId(env);
  // The strict local emulator already has its own capture and injected-provider
  // test contracts; this gate is for deployed staging and live QA fixtures.
  if (project === "demo-attendus-admin" && env.FUNCTIONS_EMULATOR === "true" &&
      /^(127\.0\.0\.1|localhost):\d+$/.test(env.FIRESTORE_EMULATOR_HOST || "")) return {mode: "normal", reason: "local_emulator"};
  if (!["orgami-66nxok", "attendus-staging"].includes(project)) return {mode: "suppress", reason: "unsupported_delivery_project"};
  const read = (ref) => tx ? tx.get(ref) : ref.get();
  const linked = associations(context);
  if (linked.length > 35) return {mode: "suppress", reason: "scope_context_too_large"};
  const bindings = await Promise.all(linked.map(({kind, id}) => read(db.collection("QualificationBindings").doc(bindingId(kind, id)))));
  const marked = bindings.filter((binding) => binding.exists);
  if (!marked.length) return project === "orgami-66nxok" ? {mode: "normal", reason: "ordinary_production"} :
    {mode: "suppress", reason: "unscoped_staging_delivery"};
  const runId = marked[0].get("runId");
  if (marked.some((binding) => binding.get("schemaVersion") !== 1 || binding.get("projectId") !== project ||
      binding.get("state") !== "bound" || binding.get("runId") !== runId) || !/^[A-Za-z0-9_-]{8,100}$/.test(runId || "")) {
    return {mode: "suppress", reason: "invalid_or_retired_binding"};
  }
  const scope = await read(db.collection("QualificationScopes").doc(runId));
  const data = scope.data();
  if (!validScope(data, runId, project, now)) return {mode: "suppress", reason: "scope_unavailable", runId};
  const deleting = await Promise.all([...new Set([context.actorUid, context.recipientUid].filter(Boolean))]
      .map((uid) => read(db.collection("account_deletion_jobs").doc(uid))));
  if (deleting.some((document) => document.exists)) return {mode: "suppress", reason: "account_unavailable", runId};
  const eventIds = [...new Set([context.eventId, ...(context.eventIds || [])].filter(Boolean))];
  if (context.actorUid && !data.actorUids.includes(context.actorUid) || eventIds.some((id) => !data.eventIds.includes(id)) ||
      context.organizationId && !data.organizationIds.includes(context.organizationId) ||
      context.conversationId && !data.conversationIds.includes(context.conversationId)) return {mode: "suppress", reason: "source_outside_scope", runId};
  const allowedUid = context.recipientUid && data.recipientUids.includes(context.recipientUid);
  const allowedEmail = context.recipientEmail && data.recipientEmailHashes.includes(emailHash(context.recipientEmail));
  if (!allowedUid && !allowedEmail) {
    if (context.deferRecipientEmail === true && data.recipientEmailHashes.length) return {mode: "verify_email", runId};
    return {mode: "suppress", reason: "recipient_outside_scope", runId};
  }
  return {mode: "capture", runId, expiresAt: data.expiresAt};
}

async function captureQualification(db, tx, decision, context, sourceKey, payload, now = Date.now()) {
  if (decision.mode !== "capture") throw Error("A verified qualification capture decision is required");
  if (typeof sourceKey !== "string" || !sourceKey || sourceKey.length > 1000) throw Error("A bounded stable capture source is required");
  const serialized = JSON.stringify(payload);
  if (Buffer.byteLength(serialized || "") > 65536) throw Error("Qualification capture payload is too large");
  const id = hash(JSON.stringify([decision.runId, context.recipientUid || emailHash(context.recipientEmail), sourceKey]));
  const ref = db.collection("QualificationCaptures").doc(id);
  const previous = await tx.get(ref);
  const fingerprint = hash(serialized);
  if (previous.exists) {
    if (previous.get("fingerprint") !== fingerprint) throw Error("Qualification source was reused with different captured content");
    return id;
  }
  tx.create(ref, {schemaVersion: 1, runId: decision.runId, sourceKey, fingerprint, payload: JSON.parse(serialized),
    actorUid: context.actorUid || null, recipientUid: context.recipientUid || null,
    recipientEmailHash: context.recipientEmail ? emailHash(context.recipientEmail) : null,
    eventIds: [...new Set([context.eventId, ...(context.eventIds || [])].filter(Boolean))],
    capturedAt: new Date(now), expiresAt: decision.expiresAt, provider: "qualification_capture"});
  return id;
}

async function interceptQualification(db, context, sourceKey, payload, options) {
  return db.runTransaction(async (tx) => {
    const decision = await qualificationDecision(db, context, tx, options);
    if (decision.mode === "capture") return {...decision, captureId: await captureQualification(db, tx, decision, context, sourceKey, payload, options?.now)};
    return decision;
  });
}
module.exports = {MAX_LEASE_MS, bindingId, emailHash, validScope, qualificationDecision, captureQualification, interceptQualification};
