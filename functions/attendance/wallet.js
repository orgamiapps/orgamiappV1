"use strict";

const crypto = require("node:crypto");
const http2 = require("node:http2");
const {defineSecret} = require("firebase-functions/params");
const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {Timestamp} = require("firebase-admin/firestore");
const {GoogleAuth} = require("google-auth-library");
const jwt = require("jsonwebtoken");
const core = require("./arrival-core");

// Deployment switches are deliberately false by default: absent issuers never
// become a secret dependency of any deployed endpoint. Runtime rollout is separate.
const appleDeployed = () => process.env.ATTENDANCE_APPLE_DELIVERY_ENABLED === "true";
const googleDeployed = () => process.env.ATTENDANCE_GOOGLE_DELIVERY_ENABLED === "true";
// Even an unbound SecretParam enters the Firebase deployment parameter spec.
// Do not register deferred providers at all; local adapters can read fixtures
// directly from their test environment without registering deployment secrets.
const APPLE = appleDeployed() ? defineSecret("APPLE_WALLET_SIGNING") : null;
const GOOGLE = googleDeployed() ? defineSecret("GOOGLE_WALLET_SERVICE_ACCOUNT_JSON") : null;
const providerSecrets = () => [APPLE, GOOGLE].filter(Boolean);
const appleSigning = () => JSON.parse(APPLE ? APPLE.value() : process.env.APPLE_WALLET_SIGNING || "{}");
const googleAccount = () => JSON.parse(GOOGLE ? GOOGLE.value() : process.env.GOOGLE_WALLET_SERVICE_ACCOUNT_JSON || "{}");
const SECRETS = providerSecrets();
const origin = () => String(process.env.ATTENDANCE_WALLET_ORIGIN || "").replace(/\/$/, "");
const appleType = () => process.env.APPLE_WALLET_PASS_TYPE_ID;
const appleReady = () => Boolean(origin().startsWith("https://") && appleType() &&
  process.env.APPLE_WALLET_TEAM_ID && process.env.APPLE_WALLET_SIGNING);
const googleReady = () => Boolean(process.env.GOOGLE_WALLET_ISSUER_ID && process.env.GOOGLE_WALLET_SERVICE_ACCOUNT_JSON);
const localized = (value) => ({defaultValue: {language: "en-US", value: String(value || "Attendus")}});

async function googlePass(record, dependencies = {}) {
  const issuer = process.env.GOOGLE_WALLET_ISSUER_ID;
  const account = dependencies.account || googleAccount();
  const client = dependencies.client || await new GoogleAuth({credentials: account,
    scopes: ["https://www.googleapis.com/auth/wallet_object.issuer"]}).getClient();
  const event = record.kind === "event";
  const classId = `${issuer}.${event ? "event_" + core.digest(record.eventId).slice(0, 32) : "attendus_identity_v2"}`;
  const objectId = `${issuer}.attendance_${record.id}`;
  const classType = event ? "eventTicketClass" : "genericClass";
  const objectType = event ? "eventTicketObject" : "genericObject";
  const classBody = event ? {id: classId, issuerName: "Attendus", reviewStatus: "UNDER_REVIEW",
    eventName: localized(record.title), venue: {name: localized(record.location || "See event details"), address: localized(record.location || "See event details")},
    dateTime: {start: record.startsAt}} : {id: classId};
  const objectBody = {id: objectId, classId,
    state: record.status === "active" ? "ACTIVE" : "INACTIVE",
    barcode: {type: "QR_CODE", value: record.qrData, alternateText: "Show to event staff"},
    validTimeInterval: {end: {date: new Date(record.expiresAtMs).toISOString()}},
    hexBackgroundColor: "#14253D",
    ...(event ? {ticketHolderName: record.attendeeName, ticketNumber: record.id.slice(0, 12).toUpperCase()} : {
      genericType: "GENERIC_OTHER", cardTitle: localized("Attendus"),
      header: localized(record.attendeeName), subheader: localized("Personal attendance pass"),
    }),
    textModulesData: [{id: "entry", header: "Entry", body: event ?
      "Event staff verify your current registration when scanned." : "Staff verify eligibility for each event. This pass does not grant admission on its own."}],
  };
  async function upsert(type, body) {
    const root = `https://walletobjects.googleapis.com/walletobjects/v1/${type}`;
    try {
      await client.request({url: `${root}/${body.id}`, method: "PATCH", data: body, timeout: 15000});
    } catch (error) {
      if (error.response?.status !== 404) throw error;
      try { await client.request({url: root, method: "POST", data: body, timeout: 15000}); } catch (insertError) {
        if (insertError.response?.status !== 409) throw insertError;
        await client.request({url: `${root}/${body.id}`, method: "PATCH", data: body, timeout: 15000});
      }
    }
  }
  await upsert(classType, classBody);
  await upsert(objectType, objectBody);
  const signed = jwt.sign({iss: account.client_email, aud: "google", typ: "savetowallet",
    payload: {[event ? "eventTicketObjects" : "genericObjects"]: [{id: objectId}]}}, account.private_key, {algorithm: "RS256"});
  return `https://pay.google.com/gp/v/save/${signed}`;
}

async function providerEnabled(db, provider, record) {
  if (!(provider === "apple" ? appleDeployed() : googleDeployed())) return false;
  return require("./arrival").rollout(db, `${provider}Delivery`, record.eventId, record.ownerUid);
}

// Core issuance only reads cached delivery state; provider failures can never
// block a signed in-app pass or require provider credentials on this endpoint.
async function deliveryLinks(db, record) {
  let appleWalletUrl = null;
  let googleWalletUrl = null;
  if (origin().startsWith("https://") && await providerEnabled(db, "apple", record)) {
    const token = crypto.randomBytes(32).toString("hex");
    await db.collection("AttendanceWalletDownloads").doc(core.digest(token)).set({passId: record.id,
      expiresAt: Timestamp.fromMillis(Date.now() + 5 * 60000)});
    appleWalletUrl = `${origin()}/api/wallet/download/${token}.pkpass`;
  }
  if (await providerEnabled(db, "google", record)) {
    const cached = (await db.collection("AttendanceWalletDelivery").doc(record.id).get()).data();
    if (cached?.credentialVersion === record.credentialVersion) googleWalletUrl = cached.googleWalletUrl || null;
  }
  return {appleWalletUrl, googleWalletUrl,
    appleWalletStatus: appleWalletUrl ? "available" : "disabled",
    googleWalletStatus: googleWalletUrl ? "available" : "disabled",
    walletStatus: appleWalletUrl || googleWalletUrl ? "available" : "disabled"};
}

async function buildApplePass(record) {
  const signing = appleSigning();
  const style = {primaryFields: [{key: "title", label: record.kind === "event" ? "EVENT" : "ATTENDUS", value: record.title}],
    secondaryFields: [{key: "attendee", label: "ATTENDEE", value: record.attendeeName}],
    auxiliaryFields: record.startsAt ? [{key: "date", label: "DATE", value: record.startsAt, dateStyle: "PKDateStyleMedium", timeStyle: "PKDateStyleShort"}] : [],
    backFields: [{key: "entry", label: "Attendance", value: "Show this pass to event staff. Current event eligibility is checked when scanned."},
      {key: "location", label: "Venue", value: record.location || "See event details"}]};
  const pass = {formatVersion: 1, passTypeIdentifier: appleType(), serialNumber: record.id,
    teamIdentifier: process.env.APPLE_WALLET_TEAM_ID, organizationName: "Attendus",
    description: record.title, logoText: "Attendus", foregroundColor: "rgb(255,255,255)",
    backgroundColor: "rgb(20,37,61)", labelColor: "rgb(195,211,232)",
    authenticationToken: record.appleAuthenticationToken,
    webServiceURL: `${origin()}/api/wallet`,
    expirationDate: new Date(record.expiresAtMs).toISOString(), voided: record.status !== "active",
    barcodes: [{format: "PKBarcodeFormatQR", message: record.qrData, messageEncoding: "iso-8859-1"}],
    ...(record.startsAt ? {relevantDate: record.startsAt} : {}),
    [record.kind === "event" ? "eventTicket" : "generic"]: style};
  const fs = require("node:fs");
  const path = require("node:path");
  const icon = fs.readFileSync(path.join(__dirname, "assets", "icon.png"));
  const entries = {"pass.json": Buffer.from(JSON.stringify(pass)), "icon.png": icon, "icon@2x.png": icon};
  const manifest = Object.fromEntries(Object.entries(entries).map(([key, bytes]) =>
    [key, crypto.createHash("sha1").update(bytes).digest("hex")]));
  entries["manifest.json"] = Buffer.from(JSON.stringify(manifest));
  entries.signature = await require("./cms-signing").signDetached(entries["manifest.json"], signing);
  const {ZipArchive} = await import("archiver");
  const archive = new ZipArchive({zlib: {level: 9}});
  const chunks = [];
  const completed = new Promise((resolve, reject) => {
    archive.on("data", (chunk) => chunks.push(chunk));
    archive.on("end", () => resolve(Buffer.concat(chunks)));
    archive.on("error", reject);
  });
  for (const [filename, bytes] of Object.entries(entries)) archive.append(bytes, {name: filename});
  await archive.finalize();
  return completed;
}

function authorizedApple(req, record) {
  const supplied = Buffer.from(String(req.get("authorization") || ""));
  const expected = Buffer.from(`ApplePass ${record.appleAuthenticationToken}`);
  return supplied.length === expected.length && crypto.timingSafeEqual(supplied, expected);
}

async function appleHandler(db, req, res) {
  res.set("Cache-Control", "private, no-store");
  res.set("X-Robots-Tag", "noindex, nofollow");
  if (!appleDeployed() || !appleReady()) return res.status(503).send("Wallet delivery is not configured.");
  const path = req.path.replace(/^\/api\/wallet/, "");
  const download = /^\/download\/([a-f0-9]{64})\.pkpass$/.exec(path);
  if (download && req.method === "GET") {
    const grant = await db.collection("AttendanceWalletDownloads").doc(core.digest(download[1])).get();
    if (!grant.exists || core.millis(grant.data().expiresAt) <= Date.now()) return res.sendStatus(404);
    const pass = (await db.collection("AttendancePasses").doc(grant.data().passId).get()).data();
    if (!pass || pass.status !== "active" || !(await providerEnabled(db, "apple", pass))) return res.sendStatus(404);
    res.set("Content-Disposition", "attachment; filename=attendus.pkpass");
    return res.type("application/vnd.apple.pkpass").send(await buildApplePass(pass));
  }
  const registration = /^\/v1\/devices\/([^/]{1,200})\/registrations\/([^/]{1,200})(?:\/([a-f0-9]{64}))?$/.exec(path);
  if (registration) {
    const [, device, type, serial] = registration;
    if (type !== appleType()) return res.sendStatus(404);
    if (!serial && req.method === "GET") {
      const docs = await db.collection("AttendanceWalletDevices").where("device", "==", device).get();
      const since = Number(req.query.passesUpdatedSince || 0);
      const passes = await Promise.all(docs.docs.map((d) => db.collection("AttendancePasses").doc(d.data().passId).get()));
      const changed = passes.filter((d) => d.exists && core.millis(d.data().updatedAt) > since);
      if (!changed.length) return res.sendStatus(204);
      return res.json({serialNumbers: changed.map((d) => d.id), lastUpdated: String(Math.max(...changed.map((d) => core.millis(d.data().updatedAt))))});
    }
    if (!serial) return res.sendStatus(404);
    const pass = (await db.collection("AttendancePasses").doc(serial).get()).data();
    if (!pass || !(await providerEnabled(db, "apple", pass)) || !authorizedApple(req, pass)) return res.sendStatus(401);
    const ref = db.collection("AttendanceWalletDevices").doc(core.digest(`${device}:${serial}`));
    if (req.method === "DELETE") { await ref.delete(); return res.sendStatus(200); }
    if (req.method === "POST" && typeof req.body?.pushToken === "string" && req.body.pushToken.length <= 512) {
      const existed = (await ref.get()).exists;
      await ref.set({device, passId: serial, pushToken: req.body.pushToken, updatedAt: Timestamp.now()});
      return res.sendStatus(existed ? 200 : 201);
    }
    return res.sendStatus(400);
  }
  const getPass = /^\/v1\/passes\/([^/]+)\/([a-f0-9]{64})$/.exec(path);
  if (getPass && req.method === "GET" && getPass[1] === appleType()) {
    const pass = (await db.collection("AttendancePasses").doc(getPass[2]).get()).data();
    if (!pass || !(await providerEnabled(db, "apple", pass)) || !authorizedApple(req, pass)) return res.sendStatus(401);
    res.set("Last-Modified", new Date(core.millis(pass.updatedAt)).toUTCString());
    return res.type("application/vnd.apple.pkpass").send(await buildApplePass(pass));
  }
  if (path === "/v1/log" && req.method === "POST") return res.sendStatus(200);
  return res.sendStatus(404);
}

async function pushApple(db, record) {
  const devices = await db.collection("AttendanceWalletDevices").where("passId", "==", record.id).get();
  if (devices.empty) return;
  const signing = appleSigning();
  const client = http2.connect("https://api.push.apple.com", {cert: signing.certificate, key: signing.privateKey});
  try {
    await new Promise((resolve, reject) => {client.once("connect", resolve); client.once("error", reject); client.setTimeout(15000, () => client.destroy(Error("APNs timeout")));});
    for (const device of devices.docs) {
      await new Promise((resolve, reject) => {
        const request = client.request({":method": "POST", ":path": `/3/device/${device.data().pushToken}`, "apns-topic": appleType(), "apns-push-type": "background", "apns-priority": "5"});
        request.setTimeout(15000, () => request.destroy(Error("APNs timeout")));
        request.on("error", reject);
        request.on("response", (headers) => {
          const status = headers[":status"];
          if (status === 410) device.ref.delete().then(resolve, reject);
          else if (status === 200) resolve(); else reject(Error("APNs update rejected"));
        });
        request.resume(); request.end("{}");
      });
    }
  } finally { client.close(); client.destroy(); }
}

async function refreshRecord(db, initial) {
  const arrival = require("./arrival");
  const material = JSON.parse(arrival.SIGNING_KEY.value());
  return db.runTransaction(async (tx) => {
    const ref = db.collection("AttendancePasses").doc(initial.id);
    const existing = await tx.get(ref);
    if (!existing.exists) return null;
    const pass = existing.data();
    // Explicit revocation is sticky; routine source refresh or renewal cannot
    // restore a credential invalidated by an administrator.
    if (pass.status === "revoked" && pass.revocationReason !== "eligibility") return pass;
    const keyRef = db.collection("AttendanceSigningKeys").doc(material.kid);
    const key = await tx.get(keyRef);
    if (key.data()?.revoked) core.fail("Signing key is revoked.");
    let valid = true;
    let event;
    let eligible;
    let ownerUid = pass.ownerUid;
    try {
      if (pass.eventId) {
        event = await arrival.readEvent(tx, db, pass.eventId);
        const linked = await tx.get(pass.registrationId ? db.collection("RegisterAttendance").doc(pass.registrationId) : db.collection("Tickets").doc(pass.ticketId));
        if (!linked.exists) core.fail("Admission no longer exists.");
        ownerUid = linked.data().customerUid;
        eligible = await arrival.entitlement(tx, db, event, ownerUid, pass, true);
      } else if (!(await tx.get(db.collection("Customers").doc(ownerUid))).exists) valid = false;
    } catch (error) {
      if (!["permission-denied", "failed-precondition", "not-found"].includes(error.code)) throw error;
      valid = false;
    }
    const next = {...pass, ownerUid, status: valid ? "active" : "revoked",
      revocationReason: valid ? null : "eligibility"};
    if (event && eligible) {
      next.title = event.title; next.location = event.location || "";
      next.startsAt = new Date(require("./v2").eventDateMillis(event)).toISOString();
      next.attendeeName = eligible.name || pass.attendeeName;
      next.expiresAtMs = require("./v2").policyWindow(event, require("./v2").normalizePolicy(event)).closesAtMs + core.DAY;
    } else if (!pass.eventId && valid && pass.expiresAtMs < Date.now() + 30 * core.DAY) next.expiresAtMs = Date.now() + 365 * core.DAY;
    if (next.status !== pass.status || next.expiresAtMs !== pass.expiresAtMs) next.credentialVersion += 1;
    next.kid = material.kid;
    next.qrData = core.signPass(next, material);
    next.updatedAt = Timestamp.now();
    tx.set(keyRef, {publicKey: crypto.createPublicKey(material.privateKey).export({format: "jwk"}).x, revoked: false}, {merge: true});
    tx.set(ref, next);
    return next;
  });
}

function createWalletFunctions(admin) {
  const db = admin.firestore();
  const arrival = require("./arrival");
  const secrets = [arrival.SIGNING_KEY];
  async function enqueue(query) {
    const docs = await query.get();
    for (const doc of docs.docs) await db.collection("AttendanceWalletJobs").doc(doc.id).set({passId: doc.id, status: "pending", attempts: 0, nextAttemptAtMs: 0, updatedAt: Timestamp.now()});
  }
  const trigger = (document, field, param) => onDocumentWritten({document, region: "us-central1", retry: true},
      (event) => enqueue(db.collection("AttendancePasses").where(field, "==", event.params[param])));
  return {
    queueAttendanceWalletDelivery: onDocumentWritten({document: "AttendancePasses/{passId}", region: "us-central1", retry: true}, async (change) => {
      const pass = change.data?.after.data();
      if (!pass) return;
      if (!(await providerEnabled(db, "apple", pass)) && !(await providerEnabled(db, "google", pass))) return;
      await db.collection("AttendanceWalletDeliveryJobs").doc(change.params.passId).set({passId: change.params.passId,
        nextAttemptAtMs: 0, attempts: 0, updatedAt: Timestamp.now()});
    }),
    deliverAttendanceWallets: onSchedule({schedule: "every 15 minutes", region: "us-central1",
      secrets: providerSecrets(), timeoutSeconds: 540, maxInstances: 1}, async () => {
      if (!appleDeployed() && !googleDeployed()) return;
      const jobs = await db.collection("AttendanceWalletDeliveryJobs").where("nextAttemptAtMs", "<=", Date.now()).limit(50).get();
      for (const job of jobs.docs) {
        const pass = (await db.collection("AttendancePasses").doc(job.id).get()).data();
        if (!pass) { await job.ref.delete(); continue; }
        const apple = await providerEnabled(db, "apple", pass);
        const google = await providerEnabled(db, "google", pass);
        try {
          if (apple && appleReady()) await pushApple(db, pass);
          if (google && googleReady()) {
            const googleWalletUrl = await googlePass(pass);
            await db.collection("AttendanceWalletDelivery").doc(pass.id).set({googleWalletUrl,
              credentialVersion: pass.credentialVersion, updatedAt: Timestamp.now()});
          }
          await db.runTransaction(async (tx) => {
            const fresh = await tx.get(job.ref);
            if (fresh.updateTime?.isEqual(job.updateTime)) tx.delete(job.ref);
          });
        } catch (_) {
          await db.runTransaction(async (tx) => {
            const fresh = await tx.get(job.ref);
            if (!fresh.updateTime?.isEqual(job.updateTime)) return;
            tx.update(job.ref, {attempts: (job.data().attempts || 0) + 1, lastError: "provider_update_failed",
              nextAttemptAtMs: Date.now() + Math.min(6 * 3600000, 900000 * 2 ** Math.min(job.data().attempts || 0, 5))});
          });
        }
      }
    }),
    attendanceWallet: onRequest({region: "us-central1", secrets: appleDeployed() ? [APPLE] : [], maxInstances: 20}, async (req, res) => {
      try { await appleHandler(db, req, res); } catch (_) { if (!res.headersSent) res.status(503).send("Wallet is temporarily unavailable."); }
    }),
    reconcileAttendanceEventPasses: onDocumentWritten({document: "Events/{eventId}", region: "us-central1", retry: true}, async (change) => {
      const fields = (data) => data && [data.title, data.location, data.selectedDateTime, data.eventDuration, data.eventDurationMinutes, data.eventTimeZone,
        data.status, data.cancelled, data.deleted, data.isDeleted, data.checkInPolicy];
      if (JSON.stringify(fields(change.data?.before.data())) === JSON.stringify(fields(change.data?.after.data()))) return;
      const eventId = change.params.eventId;
      if (change.data?.after.exists) {
        await db.runTransaction(async (tx) => {
          const fresh = await tx.get(db.collection("Events").doc(eventId));
          const stateRef = db.collection("check_in_event_state").doc(eventId);
          const state = await tx.get(stateRef);
          const activeId = state.data()?.activeSessionId;
          const session = activeId ? await tx.get(db.collection("CheckInSessions").doc(activeId)) : null;
          if (!fresh.exists || !session?.exists) return;
          const window = require("./v2").policyWindow(fresh.data(), require("./v2").normalizePolicy(fresh.data()));
          tx.update(session.ref, {opensAt: Timestamp.fromMillis(window.opensAtMs), closesAt: Timestamp.fromMillis(window.closesAtMs)});
          tx.set(stateRef, {scheduleRevision: core.windowRevision(fresh.data(), window)}, {merge: true});
        });
      }
      await enqueue(db.collection("AttendancePasses").where("eventId", "==", eventId));
    }),
    reconcileAttendanceRegistrationPasses: trigger("RegisterAttendance/{registrationId}", "registrationId", "registrationId"),
    reconcileAttendanceTicketPasses: trigger("Tickets/{ticketId}", "ticketId", "ticketId"),
    reconcileAttendanceAccountPasses: trigger("Customers/{uid}", "ownerUid", "uid"),
    refreshAttendanceWallets: onSchedule({schedule: "every 15 minutes", region: "us-central1", secrets, timeoutSeconds: 540, maxInstances: 1}, async () => {
      const expiring = await db.collection("AttendancePasses").where("kind", "==", "identity")
          .where("status", "==", "active").where("expiresAtMs", "<", Date.now() + 30 * core.DAY).limit(100).get();
      for (const pass of expiring.docs) {
        const ref = db.collection("AttendanceWalletJobs").doc(pass.id);
        await db.runTransaction(async (tx) => {
          if (!(await tx.get(ref)).exists) tx.create(ref, {passId: pass.id, status: "pending", attempts: 0, nextAttemptAtMs: 0});
        });
      }
      const jobs = await db.collection("AttendanceWalletJobs").where("status", "==", "pending").where("nextAttemptAtMs", "<=", Date.now()).orderBy("nextAttemptAtMs").limit(50).get();
      for (const job of jobs.docs) {
        try {
          const pass = (await db.collection("AttendancePasses").doc(job.data().passId).get()).data();
          if (!pass) { await job.ref.delete(); continue; }
          const current = await refreshRecord(db, pass);
          if (!current) continue;
          // Lifecycle work is complete independently of provider delivery.
          // A pass-change trigger feeds a separate queue only for enabled providers.
          // Do not erase a newer source change that arrived while providers ran.
          await db.runTransaction(async (tx) => {
            const fresh = await tx.get(job.ref);
            if (fresh.updateTime?.isEqual(job.updateTime)) tx.delete(job.ref);
          });
        } catch (_) {
          await job.ref.set({attempts: (job.data().attempts || 0) + 1, lastError: "refresh_failed", lastAttemptAt: Timestamp.now(), nextAttemptAtMs: Date.now() + 900000}, {merge: true});
        }
      }
    }),
  };
}

module.exports = {providerSecrets, providerEnabled, appleDeployed, googleDeployed, SECRETS, APPLE, GOOGLE, appleReady, googleReady, googlePass, deliveryLinks,
  buildApplePass, authorizedApple, appleHandler, refreshRecord, createWalletFunctions};
