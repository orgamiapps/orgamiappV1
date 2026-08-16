"use strict";

const crypto = require("node:crypto");
const jwt = require("jsonwebtoken");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {FieldValue, Timestamp} = require("firebase-admin/firestore");

const PROFILES = new Set(["self_check_in", "staff_entry", "hybrid"]);
const ELIGIBILITY = new Set(["open", "registered_only", "ticket_required"]);
const CREDENTIAL_TYPES = new Set([
  "venue_token",
  "personal_pass",
  "staff_roster",
  "staff_guest",
  "checkout",
]);
const VENUE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
const VENUE_TOKEN_TTL_MS = 45 * 1000;
const VENUE_CODE_TTL_MS = 70 * 1000;
const OFFLINE_GRACE_MS = 24 * 60 * 60 * 1000;
const RATE_WINDOW_MS = 60 * 1000;
const RATE_LIMIT = 40;
const STAFF_RATE_LIMIT = 1200;
const NAME_PATTERN = /^[\p{L}\p{M}][\p{L}\p{M}\s.'-]*$/u;
const GOOGLE_WALLET_SERVICE_ACCOUNT = defineSecret(
    "GOOGLE_WALLET_SERVICE_ACCOUNT_JSON",
);

function hash(value, bytes = 32) {
  return crypto.createHash("sha256").update(String(value))
      .digest("hex").slice(0, bytes * 2);
}

function boundedInteger(value, fallback, minimum, maximum) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) return fallback;
  return Math.max(minimum, Math.min(maximum, parsed));
}

function normalizePolicy(event) {
  const supplied = event?.checkInPolicy;
  if (supplied && typeof supplied === "object") {
    return {
      version: 2,
      profile: PROFILES.has(supplied.profile) ? supplied.profile : "hybrid",
      eligibility: ELIGIBILITY.has(supplied.eligibility) ?
        supplied.eligibility : "open",
      opensBeforeMinutes: boundedInteger(
          supplied.opensBeforeMinutes, 60, 0, 1440,
      ),
      closesAfterMinutes: boundedInteger(
          supplied.closesAfterMinutes, 60, 0, 1440,
      ),
      allowReentry: supplied.allowReentry === true,
      checkoutEnabled: supplied.checkoutEnabled === true,
      proximityAssist: supplied.proximityAssist === true,
      staffFallback: supplied.staffFallback !== false,
      passLockEnabled: supplied.passLockEnabled === true,
      needsOrganizerReview: supplied.needsOrganizerReview === true,
    };
  }
  const tier = event?.signInSecurityTier || "regular";
  if (tier === "most_secure" || tier === "geofence_only") {
    return {
      version: 2,
      profile: "hybrid",
      eligibility: "open",
      opensBeforeMinutes: 60,
      closesAfterMinutes: 60,
      allowReentry: false,
      checkoutEnabled: false,
      proximityAssist: false,
      staffFallback: true,
      passLockEnabled: false,
      needsOrganizerReview: true,
    };
  }
  return {
    version: 2,
    profile: tier === "all" ? "hybrid" : "self_check_in",
    eligibility: "open",
    opensBeforeMinutes: 60,
    closesAfterMinutes: 60,
    allowReentry: false,
    checkoutEnabled: false,
    proximityAssist: false,
    staffFallback: true,
    passLockEnabled: false,
    needsOrganizerReview: false,
  };
}

function eventDateMillis(event) {
  const value = event?.selectedDateTime;
  if (value?.toMillis) return value.toMillis();
  const parsed = new Date(value).getTime();
  if (!Number.isFinite(parsed)) {
    throw new HttpsError("failed-precondition", "The event date is missing.");
  }
  return parsed;
}

function policyWindow(event, policy) {
  const start = eventDateMillis(event);
  const durationHours = boundedInteger(event?.eventDuration, 2, 1, 168);
  return {
    opensAtMs: start - (policy.opensBeforeMinutes * 60 * 1000),
    closesAtMs: start + (durationHours * 60 * 60 * 1000) +
      (policy.closesAfterMinutes * 60 * 1000),
  };
}

function isManager(event, uid) {
  return Boolean(uid) && (event?.customerUid === uid ||
    (Array.isArray(event?.coHosts) && event.coHosts.includes(uid)) ||
    (Array.isArray(event?.checkInStaff) && event.checkInStaff.includes(uid)));
}

function isAnonymous(request) {
  return request.auth?.token?.firebase?.sign_in_provider === "anonymous";
}

function requireAuth(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign-in is required.");
  return uid;
}

function requireFullAccount(request) {
  const uid = requireAuth(request);
  if (isAnonymous(request)) {
    throw new HttpsError("unauthenticated", "A full account is required.");
  }
  return uid;
}

function cleanString(value, maximum = 500) {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, maximum);
}

function cleanName(value) {
  const name = cleanString(value, 100);
  if (name.length < 2 || !NAME_PATTERN.test(name)) {
    throw new HttpsError("invalid-argument", "Enter a valid full name.");
  }
  return name;
}

function validateAnswers(value) {
  const answers = Array.isArray(value) ? value : [];
  if (answers.length > 25 || answers.some((answer) =>
    typeof answer !== "string" || answer.length > 500)) {
    throw new HttpsError("invalid-argument", "Invalid event-question answers.");
  }
  return answers;
}

function parseObservedAt(value, nowMs = Date.now()) {
  if (typeof value !== "string") return nowMs;
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed) || Math.abs(nowMs - parsed) > OFFLINE_GRACE_MS) {
    return nowMs;
  }
  return parsed;
}

function encodeSigned(payload, secret) {
  const encoded = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = crypto.createHmac("sha256", secret)
      .update(encoded).digest("base64url");
  return `${encoded}.${signature}`;
}

function decodeSigned(token, secret, expectedType, atMs = Date.now()) {
  const parts = cleanString(token, 4096).split(".");
  if (parts.length !== 2) {
    throw new HttpsError("invalid-argument", "Invalid check-in credential.");
  }
  const expected = crypto.createHmac("sha256", secret)
      .update(parts[0]).digest();
  let supplied;
  try {
    supplied = Buffer.from(parts[1], "base64url");
  } catch (_) {
    throw new HttpsError("invalid-argument", "Invalid check-in credential.");
  }
  if (expected.length !== supplied.length ||
      !crypto.timingSafeEqual(expected, supplied)) {
    throw new HttpsError("permission-denied", "Invalid check-in credential.");
  }
  let payload;
  try {
    payload = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
  } catch (_) {
    throw new HttpsError("invalid-argument", "Invalid check-in credential.");
  }
  if (payload.v !== 1 || payload.t !== expectedType ||
      !Number.isFinite(payload.exp) || payload.exp < atMs) {
    throw new HttpsError("failed-precondition", "This credential has expired.");
  }
  return payload;
}

function venueCode(secret, bucket = Math.floor(Date.now() / 60000)) {
  const bytes = crypto.createHmac("sha256", secret)
      .update(`code:${bucket}`).digest();
  let result = "";
  for (let index = 0; index < 6; index += 1) {
    result += VENUE_ALPHABET[bytes[index] % VENUE_ALPHABET.length];
  }
  return result;
}

function venueToken(eventId, sessionId, secret, nowMs = Date.now()) {
  return encodeSigned({
    v: 1,
    t: "venue",
    e: eventId,
    s: sessionId,
    exp: nowMs + VENUE_TOKEN_TTL_MS,
  }, secret);
}

function personalPassToken({eventId, sessionId, uid, ticketId, expiresAtMs,
  privateKey}) {
  const payload = Buffer.from(JSON.stringify({
    v: 1,
    t: "pass",
    e: eventId,
    s: sessionId,
    u: uid,
    k: ticketId || null,
    exp: expiresAtMs,
  })).toString("base64url");
  const signature = crypto.sign(null, Buffer.from(payload), privateKey)
      .toString("base64url");
  return `${payload}.${signature}`;
}

function walletLinks({event, eventId, sessionId, uid, attendeeName,
  walletCredential}) {
  let googleWalletUrl = null;
  let appleWalletUrl = null;
  const googleIssuerId = cleanString(process.env.GOOGLE_WALLET_ISSUER_ID, 100);
  const googleClassId = cleanString(process.env.GOOGLE_WALLET_CLASS_ID, 300);
  const googleAccountValue = process.env.GOOGLE_WALLET_SERVICE_ACCOUNT_JSON;
  if (googleIssuerId && googleClassId && googleAccountValue) {
    try {
      const account = JSON.parse(googleAccountValue);
      if (account.client_email && account.private_key) {
        const objectId = `${googleIssuerId}.${hash(
            `${eventId}:${sessionId}:${uid}`, 16,
        )}`;
        const claims = {
          iss: account.client_email,
          aud: "google",
          typ: "savetowallet",
          payload: {
            eventTicketObjects: [{
              id: objectId,
              classId: googleClassId,
              state: "ACTIVE",
              ticketHolderName: attendeeName,
              ticketNumber: hash(`${eventId}:${uid}`, 8).toUpperCase(),
              barcode: {
                type: "QR_CODE",
                value: `attendus_pass:v1:${walletCredential}`,
                alternateText: "Attendus event pass",
              },
              textModulesData: [{
                id: "entry",
                header: "Entry",
                body: cleanString(event.title || "Event", 300),
              }],
            }],
          },
        };
        const token = jwt.sign(claims, account.private_key, {
          algorithm: "RS256",
        });
        googleWalletUrl = `https://pay.google.com/gp/v/save/${token}`;
      }
    } catch (_) {
      googleWalletUrl = null;
    }
  }
  const applePassService = cleanString(
      process.env.APPLE_WALLET_PASS_URL, 1000,
  );
  if (applePassService) {
    try {
      const url = new URL(applePassService);
      url.searchParams.set("eventId", eventId);
      url.searchParams.set("sessionId", sessionId);
      url.searchParams.set(
          "credential", `attendus_pass:v1:${walletCredential}`,
      );
      appleWalletUrl = url.toString();
    } catch (_) {
      appleWalletUrl = null;
    }
  }
  return {appleWalletUrl, googleWalletUrl};
}

function decodePersonalPass(token, publicKeyValue, atMs = Date.now()) {
  const parts = cleanString(token, 4096).split(".");
  if (parts.length !== 2 || !publicKeyValue) {
    throw new HttpsError("invalid-argument", "Invalid personal pass.");
  }
  let publicKey;
  let valid = false;
  try {
    publicKey = crypto.createPublicKey({
      key: {kty: "OKP", crv: "Ed25519", x: publicKeyValue},
      format: "jwk",
    });
    valid = crypto.verify(
        null,
        Buffer.from(parts[0]),
        publicKey,
        Buffer.from(parts[1], "base64url"),
    );
  } catch (_) {
    valid = false;
  }
  if (!valid) {
    throw new HttpsError("permission-denied", "Invalid personal pass.");
  }
  let payload;
  try {
    payload = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
  } catch (_) {
    throw new HttpsError("invalid-argument", "Invalid personal pass.");
  }
  if (payload.v !== 1 || payload.t !== "pass" ||
      !Number.isFinite(payload.exp) || payload.exp < atMs) {
    throw new HttpsError("failed-precondition", "This personal pass expired.");
  }
  return payload;
}

function rateLimitForActor(isManager) {
  return isManager ? STAFF_RATE_LIMIT : RATE_LIMIT;
}

async function enforceRateLimit(
    db,
    uid,
    service,
    nowMs = Date.now(),
    maximum = RATE_LIMIT,
) {
  const key = hash(`${service}:${uid}`, 16);
  const ref = db.collection("service_rate_limits").doc(`${service}_${key}`);
  let allowed = false;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.exists ? snapshot.data() : {};
    const started = Number(data.windowStartedAtMs || 0);
    const inWindow = nowMs - started < RATE_WINDOW_MS;
    const count = inWindow ? Number(data.count || 0) : 0;
    if (count >= maximum) return;
    allowed = true;
    transaction.set(ref, {
      service,
      count: count + 1,
      windowStartedAtMs: inWindow ? started : nowMs,
      expiresAt: Timestamp.fromMillis(nowMs + (2 * RATE_WINDOW_MS)),
    }, {merge: true});
  });
  if (!allowed) {
    throw new HttpsError("resource-exhausted", "Too many check-in attempts.");
  }
}

async function validateRequiredQuestions(db, eventId, answers) {
  const supplied = new Map(answers.map((answer) => {
    const parts = answer.split("--ans--");
    return [parts.shift(), parts.join("--ans--").trim()];
  }));
  const snapshot = await db.collection("Events").doc(eventId)
      .collection("EventQuestions").get();
  for (const doc of snapshot.docs) {
    const question = doc.data();
    const title = String(question.questionTitle || "");
    if (question.required === true && !supplied.get(title)) {
      throw new HttpsError(
          "failed-precondition",
          "Answer all required event questions before checking in.",
      );
    }
  }
}

async function getEvent(db, eventId) {
  const snapshot = await db.collection("Events").doc(eventId).get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Event not found.");
  return {ref: snapshot.ref, data: {...snapshot.data(), id: snapshot.id}};
}

async function getSessionBundle(db, sessionId) {
  const sessionRef = db.collection("CheckInSessions").doc(sessionId);
  const secretRef = db.collection("check_in_session_secrets").doc(sessionId);
  const [sessionSnapshot, secretSnapshot] = await Promise.all([
    sessionRef.get(),
    secretRef.get(),
  ]);
  if (!sessionSnapshot.exists || !secretSnapshot.exists) {
    throw new HttpsError("not-found", "Check-in session not found.");
  }
  return {
    sessionRef,
    session: sessionSnapshot.data(),
    secret: String(secretSnapshot.data().secret || ""),
    passPrivateKey: String(secretSnapshot.data().passPrivateKey || ""),
  };
}

async function accessAllowed(db, event, uid) {
  if (event.private !== true || isManager(event, uid)) return true;
  if (Array.isArray(event.accessList) && event.accessList.includes(uid)) {
    return true;
  }
  const attendee = await db.collection("Events").doc(event.id)
      .collection("Attendees").doc(uid).get();
  return attendee.exists;
}

async function registrationFor(db, eventId, uid) {
  const snapshot = await db.collection("RegisterAttendance")
      .where("eventId", "==", eventId)
      .where("customerUid", "==", uid).limit(1).get();
  return snapshot.empty ? null : snapshot.docs[0];
}

async function ticketFor(db, eventId, uid) {
  const snapshot = await db.collection("Tickets")
      .where("eventId", "==", eventId)
      .where("customerUid", "==", uid).limit(1).get();
  return snapshot.empty ? null : snapshot.docs[0];
}

async function enforceEligibility(db, eventId, policy, uid, options = {}) {
  if (options.staffOverride) return {registration: null, ticket: null};
  if (!uid || options.anonymous) {
    if (policy.eligibility !== "open") {
      throw new HttpsError(
          "permission-denied",
          "This event requires a registered attendee credential.",
      );
    }
    return {registration: null, ticket: null};
  }
  if (policy.eligibility === "registered_only") {
    const registration = await registrationFor(db, eventId, uid);
    if (!registration) {
      throw new HttpsError("permission-denied", "Registration is required.");
    }
    return {registration, ticket: null};
  }
  if (policy.eligibility === "ticket_required") {
    const ticket = await ticketFor(db, eventId, uid);
    if (!ticket) {
      throw new HttpsError("permission-denied", "A valid ticket is required.");
    }
    return {registration: null, ticket};
  }
  return {registration: null, ticket: null};
}

async function customerName(db, uid) {
  const customer = await db.collection("Customers").doc(uid).get();
  const data = customer.data() || {};
  return cleanString(data.name || data.username || "Attendee", 200) ||
    "Attendee";
}

async function writeAudit(db, values) {
  await db.collection("CheckInAudit").add({
    ...values,
    createdAt: FieldValue.serverTimestamp(),
  });
}

function callableOptions() {
  return {
    region: "us-central1",
    enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
    maxInstances: 40,
  };
}

function createStartCheckInSession(adminSdk) {
  const db = adminSdk.firestore();
  return onCall(callableOptions(), async (request) => {
    const uid = requireFullAccount(request);
    await enforceRateLimit(db, uid, "checkin_session_start");
    const eventId = cleanString(request.data?.eventId, 500);
    if (!eventId || eventId.includes("/")) {
      throw new HttpsError("invalid-argument", "A valid eventId is required.");
    }
    const {data: event} = await getEvent(db, eventId);
    if (!isManager(event, uid)) {
      throw new HttpsError("permission-denied", "Event staff access is required.");
    }
    const policy = normalizePolicy(event);
    if (policy.needsOrganizerReview) {
      throw new HttpsError(
          "failed-precondition",
          "Review this event's arrival profile before starting check-in.",
      );
    }
    const sessionRef = db.collection("CheckInSessions").doc();
    const secretRef = db.collection("check_in_session_secrets").doc(sessionRef.id);
    const stateRef = db.collection("check_in_event_state").doc(eventId);
    const secret = crypto.randomBytes(32).toString("base64url");
    const passKeys = crypto.generateKeyPairSync("ed25519");
    const passPublicKey = passKeys.publicKey.export({format: "jwk"}).x;
    const passPrivateKey = passKeys.privateKey.export({
      format: "pem",
      type: "pkcs8",
    });
    const window = policyWindow(event, policy);
    const nowMs = Date.now();
    const code = venueCode(secret);
    let existingSessionId = null;
    await db.runTransaction(async (transaction) => {
      const state = await transaction.get(stateRef);
      const activeSessionId = cleanString(state.data()?.activeSessionId, 500);
      let activeSession = null;
      if (activeSessionId) {
        activeSession = await transaction.get(
            db.collection("CheckInSessions").doc(activeSessionId),
        );
      }
      if (activeSession?.exists && activeSession.data().status === "active") {
        existingSessionId = activeSession.id;
        return;
      }
      transaction.create(sessionRef, {
        id: sessionRef.id,
        eventId,
        status: "active",
        opensAt: Timestamp.fromMillis(window.opensAtMs),
        closesAt: Timestamp.fromMillis(window.closesAtMs),
        startedAt: FieldValue.serverTimestamp(),
        startedBy: uid,
        tokenVersion: 1,
        passPublicKey,
        venueCode: code,
        venueCodeExpiresAt: Timestamp.fromMillis(nowMs + VENUE_CODE_TTL_MS),
      });
      transaction.create(secretRef, {
        sessionId: sessionRef.id,
        eventId,
        secret,
        passPrivateKey,
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.set(stateRef, {
        eventId,
        activeSessionId: sessionRef.id,
        status: "active",
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    if (existingSessionId) {
      return {sessionId: existingSessionId, created: false};
    }
    await writeAudit(db, {
      action: "session_started",
      eventId,
      sessionId: sessionRef.id,
      actorUid: uid,
    });
    return {sessionId: sessionRef.id, created: true};
  });
}

function createEndCheckInSession(adminSdk) {
  const db = adminSdk.firestore();
  return onCall(callableOptions(), async (request) => {
    const uid = requireFullAccount(request);
    await enforceRateLimit(db, uid, "checkin_session_end");
    const sessionId = cleanString(request.data?.sessionId, 500);
    const bundle = await getSessionBundle(db, sessionId);
    const {data: event} = await getEvent(db, bundle.session.eventId);
    if (!isManager(event, uid)) {
      throw new HttpsError("permission-denied", "Event staff access is required.");
    }
    const batch = db.batch();
    batch.update(bundle.sessionRef, {
      status: "closed",
      endedAt: FieldValue.serverTimestamp(),
      endedBy: uid,
      venueCode: FieldValue.delete(),
      venueCodeExpiresAt: FieldValue.delete(),
    });
    batch.set(
        db.collection("check_in_event_state").doc(bundle.session.eventId),
        {
          eventId: bundle.session.eventId,
          activeSessionId: null,
          status: "closed",
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
    );
    await batch.commit();
    await writeAudit(db, {
      action: "session_ended",
      eventId: bundle.session.eventId,
      sessionId,
      actorUid: uid,
    });
    return {sessionId, status: "closed"};
  });
}

function createMintVenueCredential(adminSdk) {
  const db = adminSdk.firestore();
  return onCall(callableOptions(), async (request) => {
    const uid = requireFullAccount(request);
    await enforceRateLimit(db, uid, "venue_credential_mint");
    const sessionId = cleanString(request.data?.sessionId, 500);
    const bundle = await getSessionBundle(db, sessionId);
    const {data: event} = await getEvent(db, bundle.session.eventId);
    if (!isManager(event, uid) || bundle.session.status !== "active") {
      throw new HttpsError("permission-denied", "Active event staff access is required.");
    }
    const nowMs = Date.now();
    const code = venueCode(bundle.secret);
    const codeExpiresAtMs = nowMs + VENUE_CODE_TTL_MS;
    await bundle.sessionRef.update({
      venueCode: code,
      venueCodeExpiresAt: Timestamp.fromMillis(codeExpiresAtMs),
      credentialRefreshedAt: FieldValue.serverTimestamp(),
    });
    const token = venueToken(
        bundle.session.eventId, sessionId, bundle.secret, nowMs,
    );
    return {
      eventId: bundle.session.eventId,
      sessionId,
      code,
      codeExpiresAt: new Date(codeExpiresAtMs).toISOString(),
      token,
      qrData: `attendus_checkin:v1:${token}`,
      tokenExpiresAt: new Date(nowMs + VENUE_TOKEN_TTL_MS).toISOString(),
    };
  });
}

async function resolveVenueValue(db, value, atMs = Date.now()) {
  const cleaned = cleanString(value, 4096);
  if (/^[A-Z0-9]{6}$/i.test(cleaned)) {
    const snapshot = await db.collection("CheckInSessions")
        .where("venueCode", "==", cleaned.toUpperCase())
        .where("status", "==", "active").limit(2).get();
    if (snapshot.empty) {
      throw new HttpsError("not-found", "That check-in code is not active.");
    }
    const matching = snapshot.docs.filter((doc) => {
      const expiry = doc.data().venueCodeExpiresAt;
      return expiry?.toMillis && expiry.toMillis() >= atMs;
    });
    if (matching.length === 0) {
      throw new HttpsError("failed-precondition", "That check-in code expired.");
    }
    if (matching.length !== 1) {
      throw new HttpsError(
          "failed-precondition", "That code is ambiguous; scan the venue QR.",
      );
    }
    return {
      sessionId: matching[0].id,
      session: matching[0].data(),
      token: null,
    };
  }
  const token = cleaned.startsWith("attendus_checkin:v1:") ?
    cleaned.substring("attendus_checkin:v1:".length) : cleaned;
  let untrusted;
  try {
    untrusted = JSON.parse(Buffer.from(token.split(".")[0], "base64url")
        .toString("utf8"));
  } catch (_) {
    throw new HttpsError("invalid-argument", "Invalid check-in credential.");
  }
  const bundle = await getSessionBundle(db, cleanString(untrusted.s, 500));
  const payload = decodeSigned(token, bundle.secret, "venue", atMs);
  if (payload.e !== bundle.session.eventId || payload.s !== untrusted.s) {
    throw new HttpsError("permission-denied", "Credential event mismatch.");
  }
  return {
    sessionId: untrusted.s,
    session: bundle.session,
    token,
    payload,
  };
}

function createResolveCheckInCredential(adminSdk) {
  const db = adminSdk.firestore();
  return onCall(callableOptions(), async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(db, uid, "checkin_resolve");
    const resolved = await resolveVenueValue(db, request.data?.value);
    const {data: event} = await getEvent(db, resolved.session.eventId);
    const policy = normalizePolicy(event);
    if (event.private === true && !(await accessAllowed(db, event, uid))) {
      throw new HttpsError("permission-denied", "This event is private.");
    }
    if (resolved.session.status !== "active") {
      throw new HttpsError("failed-precondition", "Check-in is closed.");
    }
    return {
      eventId: resolved.session.eventId,
      sessionId: resolved.sessionId,
      title: cleanString(event.title || "Event", 300),
      location: cleanString(event.locationName || event.location || "", 500),
      selectedDateTime: event.selectedDateTime?.toDate ?
        event.selectedDateTime.toDate().toISOString() : event.selectedDateTime,
      policy,
      normalizedCredential: resolved.token || cleanString(request.data?.value, 20)
          .toUpperCase(),
    };
  });
}

async function resolvePersonalPass(db, credential, eventId, sessionId,
    actorIsManager, atMs) {
  if (!actorIsManager) {
    throw new HttpsError("permission-denied", "Event staff must scan this pass.");
  }
  const tokenValue = cleanString(credential.token || credential.value, 4096)
      .replace(/^attendus_pass:v1:/, "");
  if (tokenValue) {
    const bundle = await getSessionBundle(db, sessionId);
    const payload = decodePersonalPass(
        tokenValue, bundle.session.passPublicKey, atMs,
    );
    if (payload.e !== eventId || payload.s !== sessionId || !payload.u) {
      throw new HttpsError("permission-denied", "Personal pass event mismatch.");
    }
    const ticket = payload.k ? await db.collection("Tickets").doc(payload.k).get() :
      null;
    if (ticket?.exists &&
        (ticket.data().eventId !== eventId ||
         ticket.data().customerUid !== payload.u)) {
      throw new HttpsError("permission-denied", "Personal pass ticket mismatch.");
    }
    return {uid: payload.u, ticket: ticket?.exists ? ticket : null};
  }
  const ticketCode = cleanString(credential.ticketCode, 100);
  if (!ticketCode) {
    throw new HttpsError("invalid-argument", "A personal pass is required.");
  }
  const snapshot = await db.collection("Tickets")
      .where("ticketCode", "==", ticketCode).limit(2).get();
  if (snapshot.empty) throw new HttpsError("not-found", "Ticket not found.");
  if (snapshot.size !== 1) {
    throw new HttpsError("failed-precondition", "Ticket code is ambiguous.");
  }
  const ticket = snapshot.docs[0];
  const data = ticket.data();
  if (data.eventId !== eventId) {
    throw new HttpsError("permission-denied", "This ticket is for another event.");
  }
  return {uid: data.customerUid, ticket};
}

function validateSubmitInput(data) {
  const eventId = cleanString(data?.eventId, 500);
  const sessionId = cleanString(data?.sessionId, 500);
  const idempotencyKey = cleanString(data?.idempotencyKey, 200);
  const credential = data?.credential && typeof data.credential === "object" ?
    data.credential : {};
  const type = cleanString(credential.type, 50);
  if (!eventId || !sessionId || !idempotencyKey ||
      eventId.includes("/") || sessionId.includes("/") ||
      !CREDENTIAL_TYPES.has(type)) {
    throw new HttpsError("invalid-argument", "Invalid check-in request.");
  }
  return {
    eventId,
    sessionId,
    idempotencyKey,
    credential: {...credential, type},
    answers: validateAnswers(data?.answers),
    observedAtMs: parseObservedAt(data?.observedAt),
  };
}

function createSubmitCheckIn(adminSdk) {
  const db = adminSdk.firestore();
  return onCall(callableOptions(), async (request) => {
    const actorUid = requireAuth(request);
    try {
    const input = validateSubmitInput(request.data);
    const {data: event} = await getEvent(db, input.eventId);
    const policy = normalizePolicy(event);
    if (policy.needsOrganizerReview) {
      throw new HttpsError(
          "failed-precondition",
          "The organizer must choose a current arrival profile.",
      );
    }
    const actorIsManager = isManager(event, actorUid);
    await enforceRateLimit(
        db,
        actorUid,
        "attendance_v2",
        Date.now(),
        rateLimitForActor(actorIsManager),
    );
    const bundle = await getSessionBundle(db, input.sessionId);
    if (bundle.session.eventId !== input.eventId) {
      throw new HttpsError("permission-denied", "Session event mismatch.");
    }
    const offlineStaff = actorIsManager &&
      input.observedAtMs < Date.now() - VENUE_CODE_TTL_MS;
    const effectiveAtMs = offlineStaff ? input.observedAtMs : Date.now();
    const opensAtMs = bundle.session.opensAt.toMillis();
    const closesAtMs = bundle.session.closesAt.toMillis();
    if (effectiveAtMs < opensAtMs || effectiveAtMs > closesAtMs) {
      throw new HttpsError("failed-precondition", "Check-in is outside its window.");
    }
    if (!offlineStaff && bundle.session.status !== "active") {
      throw new HttpsError("failed-precondition", "Check-in is closed.");
    }

    const type = input.credential.type;
    if (type === "checkout") {
      return checkoutAttendance({
        db,
        policy,
        bundle,
        actorUid,
        actorIsManager,
        input,
        anonymous: isAnonymous(request),
      });
    }

    let subjectUid = actorUid;
    let subjectKey = isAnonymous(request) ?
      `guest:${actorUid}` : `user:${actorUid}`;
    let displayName;
    let ticket = null;
    let verificationLevel = "session_presence";
    let source = type;
    let overrideReason = "";

    if (type === "venue_token") {
      if (policy.profile === "staff_entry") {
        throw new HttpsError("permission-denied", "Self check-in is not enabled.");
      }
      await resolveVenueValue(
          db,
          input.credential.token || input.credential.code ||
            input.credential.value,
          Date.now(),
      ).then((resolved) => {
        if (resolved.sessionId !== input.sessionId) {
          throw new HttpsError("permission-denied", "Credential session mismatch.");
        }
      });
      if (!(await accessAllowed(db, event, actorUid))) {
        throw new HttpsError("permission-denied", "Event access is required.");
      }
      const eligible = await enforceEligibility(db, input.eventId, policy, actorUid, {
        anonymous: isAnonymous(request),
      });
      ticket = eligible.ticket;
      if (ticket?.data()?.isUsed === true && !policy.allowReentry) {
        throw new HttpsError("already-exists", "This ticket was already used.");
      }
      displayName = isAnonymous(request) ?
        cleanName(input.credential.fullName) : await customerName(db, actorUid);
    } else if (type === "personal_pass") {
      if (policy.profile === "self_check_in" && !policy.staffFallback) {
        throw new HttpsError("permission-denied", "Staff entry is not enabled.");
      }
      const resolved = await resolvePersonalPass(
          db, input.credential, input.eventId, input.sessionId,
          actorIsManager, effectiveAtMs,
      );
      subjectUid = resolved.uid;
      subjectKey = `user:${subjectUid}`;
      ticket = resolved.ticket;
      if (ticket?.data()?.isUsed === true && !policy.allowReentry) {
        throw new HttpsError("already-exists", "This ticket was already used.");
      }
      displayName = ticket?.data()?.customerName ||
        await customerName(db, subjectUid);
      verificationLevel = "signed_personal_pass";
    } else if (type === "staff_roster") {
      if (!actorIsManager) {
        throw new HttpsError("permission-denied", "Event staff access is required.");
      }
      subjectUid = cleanString(input.credential.attendeeId, 500);
      if (!subjectUid || subjectUid.includes("/")) {
        throw new HttpsError("invalid-argument", "Select an attendee.");
      }
      subjectKey = `user:${subjectUid}`;
      overrideReason = cleanString(input.credential.overrideReason, 300);
      const eligible = await enforceEligibility(db, input.eventId, policy, subjectUid, {
        staffOverride: Boolean(overrideReason),
      });
      ticket = eligible.ticket;
      if (ticket?.data()?.isUsed === true && !policy.allowReentry) {
        throw new HttpsError("already-exists", "This ticket was already used.");
      }
      displayName = cleanString(input.credential.displayName, 200) ||
        await customerName(db, subjectUid);
      verificationLevel = overrideReason ? "staff_override" : "staff_roster";
    } else if (type === "staff_guest") {
      if (!actorIsManager) {
        throw new HttpsError("permission-denied", "Event staff access is required.");
      }
      overrideReason = cleanString(input.credential.overrideReason, 300);
      if (policy.eligibility !== "open" && !overrideReason) {
        throw new HttpsError(
            "failed-precondition",
            "A reason is required to add an unregistered guest.",
        );
      }
      displayName = cleanName(input.credential.fullName);
      subjectUid = "without_login";
      subjectKey = `staff_guest:${hash(
          `${input.sessionId}:${displayName.toLocaleLowerCase("en-US")}`, 20,
      )}`;
      verificationLevel = overrideReason ? "staff_override" : "staff_guest";
    }

    await validateRequiredQuestions(db, input.eventId, input.answers);
    const attendanceId = `v2_${hash(
        `${input.eventId}:${input.sessionId}:${subjectKey}`, 20,
    )}`;
    const attendanceRef = db.collection("Attendance").doc(attendanceId);
    const idempotencyRef = db.collection("check_in_idempotency")
        .doc(hash(`${actorUid}:${input.idempotencyKey}`, 20));
    const now = Timestamp.now();
    const observedAt = Timestamp.fromMillis(input.observedAtMs);

    const result = await db.runTransaction(async (transaction) => {
      const [existing, idempotency] = await Promise.all([
        transaction.get(attendanceRef),
        transaction.get(idempotencyRef),
      ]);
      if (idempotency.exists) {
        return {attendanceId: idempotency.data().attendanceId, created: false};
      }
      if (existing.exists && existing.data().status === "checked_in" &&
          !policy.allowReentry) {
        throw new HttpsError("already-exists", "This attendee is already checked in.");
      }
      const reentryCount = existing.exists ?
        Number(existing.data().reentryCount || 0) + 1 : 0;
      transaction.set(attendanceRef, {
        id: attendanceId,
        eventId: input.eventId,
        sessionId: input.sessionId,
        subjectKey,
        customerUid: subjectUid,
        guestSessionId: isAnonymous(request) ? actorUid : null,
        userName: displayName,
        realName: displayName,
        attendanceDateTime: now,
        checkedInAt: now,
        observedAt,
        answers: input.answers,
        isAnonymous: subjectKey.startsWith("guest:") ||
          subjectKey.startsWith("staff_guest:"),
        signInMethod: type,
        source,
        verificationLevel,
        actorUid,
        status: "checked_in",
        reentryCount,
        overrideReason: overrideReason || null,
        offlineReconciled: offlineStaff,
        updatedAt: now,
      }, {merge: existing.exists});
      transaction.create(idempotencyRef, {
        actorUid,
        eventId: input.eventId,
        sessionId: input.sessionId,
        attendanceId,
        createdAt: now,
        expiresAt: Timestamp.fromMillis(Date.now() + OFFLINE_GRACE_MS),
      });
      if (ticket?.exists && ticket.data().isUsed !== true) {
        transaction.update(ticket.ref, {
          isUsed: true,
          usedDateTime: now,
          usedBy: actorUid,
        });
      }
      return {attendanceId, created: !existing.exists, reentryCount};
    });
    await writeAudit(db, {
      action: result.created ? "checked_in" : "check_in_replayed",
      eventId: input.eventId,
      sessionId: input.sessionId,
      attendanceId: result.attendanceId,
      actorUid,
      subjectHash: hash(subjectKey, 16),
      source,
      verificationLevel,
      offlineReconciled: offlineStaff,
      overrideReason: overrideReason || null,
    });
    return {
      ...result,
      eventId: input.eventId,
      sessionId: input.sessionId,
      attendeeName: displayName,
      status: "checked_in",
      checkedInAt: now.toDate().toISOString(),
    };
    } catch (error) {
      await writeAudit(db, {
        action: "check_in_rejected",
        eventId: cleanString(request.data?.eventId, 500) || null,
        sessionId: cleanString(request.data?.sessionId, 500) || null,
        actorUid,
        credentialType: cleanString(request.data?.credential?.type, 50) || null,
        attemptHash: hash(
            `${actorUid}:${cleanString(request.data?.idempotencyKey, 200)}`,
            16,
        ),
        reasonCode: error instanceof HttpsError ? error.code : "internal",
      });
      throw error;
    }
  });
}

async function checkoutAttendance({db, policy, bundle, actorUid,
  actorIsManager, input, anonymous}) {
  if (!policy.checkoutEnabled) {
    throw new HttpsError("failed-precondition", "Checkout is not enabled.");
  }
  let attendanceRef;
  const explicitId = cleanString(input.credential.attendanceId, 500);
  if (explicitId) {
    if (!actorIsManager) {
      throw new HttpsError("permission-denied", "Event staff access is required.");
    }
    attendanceRef = db.collection("Attendance").doc(explicitId);
  } else {
    const subjectKey = anonymous ? `guest:${actorUid}` : `user:${actorUid}`;
    const id = `v2_${hash(
        `${input.eventId}:${input.sessionId}:${subjectKey}`, 20,
    )}`;
    attendanceRef = db.collection("Attendance").doc(id);
  }
  const snapshot = await attendanceRef.get();
  if (!snapshot.exists || snapshot.data().eventId !== input.eventId ||
      snapshot.data().sessionId !== bundle.session.id) {
    throw new HttpsError("not-found", "Attendance record not found.");
  }
  const now = Timestamp.now();
  await attendanceRef.update({
    status: "checked_out",
    checkedOutAt: now,
    checkoutActorUid: actorUid,
    updatedAt: now,
  });
  await writeAudit(db, {
    action: "checked_out",
    eventId: input.eventId,
    sessionId: input.sessionId,
    attendanceId: attendanceRef.id,
    actorUid,
  });
  return {
    attendanceId: attendanceRef.id,
    eventId: input.eventId,
    sessionId: input.sessionId,
    status: "checked_out",
    checkedOutAt: now.toDate().toISOString(),
  };
}

function createVoidAttendance(adminSdk) {
  const db = adminSdk.firestore();
  return onCall(callableOptions(), async (request) => {
    const uid = requireFullAccount(request);
    await enforceRateLimit(db, uid, "attendance_void");
    const attendanceId = cleanString(request.data?.attendanceId, 500);
    const reason = cleanString(request.data?.reason, 300);
    if (!attendanceId || !reason) {
      throw new HttpsError("invalid-argument", "Attendance and reason are required.");
    }
    const ref = db.collection("Attendance").doc(attendanceId);
    const snapshot = await ref.get();
    if (!snapshot.exists) throw new HttpsError("not-found", "Attendance not found.");
    const attendance = snapshot.data();
    const {data: event} = await getEvent(db, attendance.eventId);
    if (!isManager(event, uid)) {
      throw new HttpsError("permission-denied", "Event staff access is required.");
    }
    await ref.update({
      status: "voided",
      voidedAt: FieldValue.serverTimestamp(),
      voidedBy: uid,
      voidReason: reason,
      updatedAt: FieldValue.serverTimestamp(),
    });
    await writeAudit(db, {
      action: "attendance_voided",
      eventId: attendance.eventId,
      sessionId: attendance.sessionId || null,
      attendanceId,
      actorUid: uid,
      reason,
    });
    return {attendanceId, status: "voided"};
  });
}

function createGetPersonalPass(adminSdk) {
  const db = adminSdk.firestore();
  return onCall({
    ...callableOptions(),
    secrets: [GOOGLE_WALLET_SERVICE_ACCOUNT],
  }, async (request) => {
    const uid = requireFullAccount(request);
    await enforceRateLimit(db, uid, "personal_pass_issue");
    const eventId = cleanString(request.data?.eventId, 500);
    let sessionId = cleanString(request.data?.sessionId, 500);
    const {data: event} = await getEvent(db, eventId);
    const policy = normalizePolicy(event);
    if (!sessionId) {
      const active = await db.collection("CheckInSessions")
          .where("eventId", "==", eventId)
          .where("status", "==", "active").limit(1).get();
      if (active.empty) {
        throw new HttpsError("failed-precondition", "Check-in is not open yet.");
      }
      sessionId = active.docs[0].id;
    }
    const bundle = await getSessionBundle(db, sessionId);
    if (bundle.session.eventId !== eventId || bundle.session.status !== "active") {
      throw new HttpsError("failed-precondition", "An active session is required.");
    }
    if (!bundle.passPrivateKey || !bundle.session.passPublicKey) {
      throw new HttpsError(
          "failed-precondition",
          "Restart this legacy check-in session to enable signed passes.",
      );
    }
    if (!(await accessAllowed(db, event, uid))) {
      throw new HttpsError("permission-denied", "Event access is required.");
    }
    const eligible = await enforceEligibility(db, eventId, policy, uid);
    const ticket = eligible.ticket || await ticketFor(db, eventId, uid);
    const passExpiresAtMs = Math.min(
        bundle.session.closesAt.toMillis(),
        Date.now() + (policy.passLockEnabled ? 2 : 15) * 60 * 1000,
    );
    const attendeeName = await customerName(db, uid);
    const token = personalPassToken({
      eventId,
      sessionId,
      uid,
      ticketId: ticket?.id,
      expiresAtMs: passExpiresAtMs,
      privateKey: bundle.passPrivateKey,
    });
    const walletCredential = personalPassToken({
      eventId,
      sessionId,
      uid,
      ticketId: ticket?.id,
      expiresAtMs: bundle.session.closesAt.toMillis(),
      privateKey: bundle.passPrivateKey,
    });
    const wallet = walletLinks({
      event,
      eventId,
      sessionId,
      uid,
      attendeeName,
      walletCredential,
    });
    return {
      eventId,
      sessionId,
      attendeeName,
      token,
      qrData: `attendus_pass:v1:${token}`,
      expiresAt: new Date(passExpiresAtMs).toISOString(),
      passLockRequired: policy.passLockEnabled,
      appleWalletUrl: wallet.appleWalletUrl,
      googleWalletUrl: wallet.googleWalletUrl,
      walletStatus: wallet.appleWalletUrl || wallet.googleWalletUrl ?
        "available" : "configuration_required",
    };
  });
}

module.exports = {
  createEndCheckInSession,
  createGetPersonalPass,
  createMintVenueCredential,
  createResolveCheckInCredential,
  createStartCheckInSession,
  createSubmitCheckIn,
  createVoidAttendance,
  decodePersonalPass,
  decodeSigned,
  encodeSigned,
  normalizePolicy,
  personalPassToken,
  policyWindow,
  rateLimitForActor,
  validateSubmitInput,
  venueCode,
  venueToken,
};
