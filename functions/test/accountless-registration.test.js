"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {decryptEmail, encryptEmail, maskedEmail, normalizeEmail, normalizeName,
  normalizeRegistrationIdentity, ticketQrSvg, validateEvent,
  validateRegistrationWindow} =
  require("../public-web/accountless");
const {calendarInvite, fallbackTemplate} = require("../communications/delivery");

test("normalizes and masks guest email", () => {
  assert.equal(normalizeEmail(" Person@Example.COM "), "person@example.com");
  assert.equal(maskedEmail("person@example.com"), "p***@example.com");
});

test("rejects malformed email", () => {
  assert.throws(() => normalizeEmail("missing-at.example"), /email/);
});

test("normalizes a single Unicode full name", () => {
  assert.equal(normalizeName("  María-José   O’Neil  "), "María-José O’Neil");
  assert.throws(() => normalizeName("<script>"), /full name/);
});

test("registration identity accepts only full name and email", () => {
  assert.deepEqual(normalizeRegistrationIdentity({
    fullName: "  Taylor   Rivera ", email: " Taylor@Example.com ",
  }), {fullName: "Taylor Rivera", greetingName: "Taylor", email: "taylor@example.com"});
  assert.throws(() => normalizeRegistrationIdentity({fullName: "Taylor Rivera",
    email: "taylor@example.com", contactType: "phone"}), /fullName and email/);
  assert.throws(() => normalizeRegistrationIdentity({firstName: "Taylor",
    lastName: "Rivera", email: "taylor@example.com"}), /fullName and email/);
});

test("encrypts and decrypts email in emulator mode", async () => {
  const previousEmulator = process.env.FUNCTIONS_EMULATOR;
  const previousKey = process.env.GUEST_CONTACT_KMS_KEY_NAME;
  process.env.FUNCTIONS_EMULATOR = "true";
  process.env.GUEST_CONTACT_KMS_KEY_NAME = "emulator";
  try {
    const encrypted = await encryptEmail("person@example.com");
    assert.equal(await decryptEmail(encrypted), "person@example.com");
  } finally {
    if (previousEmulator === undefined) delete process.env.FUNCTIONS_EMULATOR;
    else process.env.FUNCTIONS_EMULATOR = previousEmulator;
    if (previousKey === undefined) delete process.env.GUEST_CONTACT_KMS_KEY_NAME;
    else process.env.GUEST_CONTACT_KMS_KEY_NAME = previousKey;
  }
});

test("event eligibility is server authoritative", () => {
  const future = new Date(Date.now() + 3600000);
  assert.doesNotThrow(() => validateEvent({status: "active", private: false,
    selectedDateTime: future}));
  assert.throws(() => validateEvent({status: "active", private: true,
    selectedDateTime: future}), /Event not found/);
  assert.throws(() => validateEvent({status: "active", private: false,
    selectedDateTime: new Date(0)}), /ended/);
});

test("registration opening and closing times are enforced", () => {
  const now = new Date("2030-01-02T12:00:00Z");
  assert.doesNotThrow(() => validateRegistrationWindow({}, now));
  assert.doesNotThrow(() => validateRegistrationWindow({registrationPolicy: {
    opensAt: new Date("2030-01-01T12:00:00Z"),
    closesAt: new Date("2030-01-03T12:00:00Z"),
  }}, now));
  assert.throws(() => validateRegistrationWindow({registrationPolicy: {
    opensAt: new Date("2030-01-03T12:00:00Z"),
  }}, now), /not open/i);
  assert.throws(() => validateRegistrationWindow({registrationPolicy: {
    closesAt: new Date("2030-01-01T12:00:00Z"),
  }}, now), /closed/i);
});

test("calendar invitation uses a stable registration UID", () => {
  const invite = calendarInvite({registrationId: "registration-1", payload: {
    eventTitle: "Food, Fun & Friends", eventStart: new Date("2030-01-02T15:00:00Z"),
    eventDurationMinutes: 90, eventTimeZone: "America/New_York",
    eventLocation: "Main Hall; Suite 2", manageUrl: "https://attendus.app/manage/token",
  }});
  assert.match(invite, /UID:registration-1@attendus\.app/);
  assert.match(invite, /SUMMARY:Food\\, Fun & Friends/);
  assert.match(invite, /LOCATION:Main Hall\\; Suite 2/);
});

test("fallback email identifies Attendus", () => {
  const template = fallbackTemplate({registrationId: "r1", payload: {
    firstName: "Taylor", eventTitle: "Community Night", kind: "rsvp",
    manageUrl: "https://attendus.app/manage/token",
  }});
  assert.match(template.subject, /Community Night/);
  assert.deepEqual(Object.keys(template).sort(), ["html", "subject", "text"]);
  assert.match(template.html, /support@attendus\.app/);
});

test("ticket QR output is an accessible-size SVG without external resources", async () => {
  const svg = await ticketQrSvg("A1B2C3D4");
  assert.match(svg, /^<svg/);
  assert.match(svg, /viewBox=/);
  assert.doesNotMatch(svg, /<script|href=|xlink:/i);
});

// Buffered transactions reject reads after writes and discard failed writes.
// These factory-level tests exercise the real callable without cloud access.
function registrationFixture() {
  // The Admin SDK is fully replaced below; this selects only generated URLs.
  process.env.GCLOUD_PROJECT = "demo-attendus-admin";
  process.env.GOOGLE_CLOUD_PROJECT = "demo-attendus-admin";
  process.env.FUNCTIONS_EMULATOR = "true";
  const {digest, createClaimPublicRegistrationV1, createResendPublicRegistrationConfirmationV1} = require("../public-web/accountless");
  const token = "a".repeat(40);
  const data = new Map([
    ["Events/event", {title: "Event", selectedDateTime: new Date("2030-01-01"), eventDurationMinutes: 60}],
    ["RegisterAttendance/registration", {customerUid: "owner", guestId: "guest", eventId: "event", status: "confirmed"}],
    ["GuestAttendees/guest", {ownerUid: "owner", fullName: "Guest Name", greetingName: "Guest", encryptedEmail: "encrypted", maskedEmail: "g***@example.test"}],
    [`GuestManageTokens/${digest(token)}`, {ownerUid: "owner", guestId: "guest", registrationId: "registration", status: "active", expiresAt: {toDate: () => new Date(Date.now() + 600000)}}],
  ]);
  const snapshot = (path) => { const row = data.get(path); return {id: path.split("/").at(-1), ref: ref(path), exists: Boolean(row), get: (field) => row?.[field], data: () => row}; };
  const ref = (path) => ({path, id: path.split("/").at(-1), get: async () => snapshot(path)});
  const collection = (path, filters = []) => ({path, filters, doc: (id) => ref(`${path}/${id}`),
    where: (field, operator, value) => { assert.equal(operator, "=="); return collection(path, [...filters, [field, value]]); }});
  const db = {collection, runTransaction: async (work) => {
    const writes = [];
    const result = await work({get: async (target) => {
      assert.equal(writes.length, 0, "Firestore forbids reads after writes");
      if (!target.filters) return snapshot(target.path);
      return {docs: [...data.entries()].filter(([path, row]) => path.startsWith(target.path + "/") && target.filters.every(([field, value]) => row[field] === value)).map(([path]) => snapshot(path))};
    }, set: (target, patch, options) => writes.push([target.path, patch, options?.merge]),
    create: (target, patch) => { assert.equal(data.has(target.path), false); writes.push([target.path, patch, false]); },
    update: (target, patch) => { assert.equal(data.has(target.path), true); writes.push([target.path, patch, true]); }});
    for (const [path, patch, merge] of writes) data.set(path, {...(merge ? data.get(path) : {}), ...patch});
    return result;
  }};
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => "fixture-server-time"};
  const admin = {firestore};
  const request = (uid, values) => ({auth: {uid, token: {email: "owner@example.test", firebase: {sign_in_provider: "password"}}}, app: {}, data: values});
  return {data, claim: (uid = "owner") => createClaimPublicRegistrationV1(admin).run(request(uid, {registrationId: "registration", claimToken: token})),
    resend: (idempotencyKey = "resend-fixture") => createResendPublicRegistrationConfirmationV1(admin).run(request("owner", {registrationId: "registration", idempotencyKey}))};
}

test("claiming a registration preserves an existing profile and safely replays", async () => {
  const f = registrationFixture();
  const profile = {name: "Existing Name", username: "existing-handle", email: "verified@example.test", isDiscoverable: true, createdAt: "original-date", biography: "Keep me"};
  f.data.set("Customers/owner", {...profile});
  assert.deepEqual(await f.claim(), {status: "claimed"});
  assert.deepEqual(f.data.get("Customers/owner"), profile);
  assert.deepEqual(await f.claim(), {status: "claimed"});
  assert.deepEqual(f.data.get("Customers/owner"), profile);
  await assert.rejects(f.claim("outsider"), {code: "permission-denied"});
});

test("claiming into a new account still initializes the profile", async () => {
  const f = registrationFixture();
  await f.claim("new-owner");
  assert.equal(f.data.get("Customers/new-owner").name, "Guest Name");
  assert.equal(f.data.get("Customers/new-owner").profileCompletionRequired, true);
  assert.equal(f.data.get("Customers/new-owner").eventsCreated, 0);
  assert.equal(f.data.get("Customers/new-owner").groupsCreated, 0);
  assert.equal(f.data.get("RegisterAttendance/registration").customerUid, "new-owner");
});

test("confirmation resend retries reuse one message and one manage token", async () => {
  const f = registrationFixture();
  const first = await f.resend();
  assert.deepEqual(await f.resend(), first);
  assert.equal([...f.data.keys()].filter((path) => path.startsWith("OutboundMessages/")).length, 1);
  assert.equal([...f.data.keys()].filter((path) => path.startsWith("GuestManageTokens/")).length, 2);
  await f.resend("another-request");
  assert.equal([...f.data.keys()].filter((path) => path.startsWith("OutboundMessages/")).length, 2);
});

test("resends describe pending, waitlisted, declined and cancelled admissions truthfully", async () => {
  for (const [status, templateId] of [["pending", "guest_registration_pending"], ["waitlisted", "guest_registration_waitlisted"], ["declined", "guest_registration_declined"], ["cancelled", "guest_registration_cancelled"]]) {
    const f = registrationFixture(); f.data.get("RegisterAttendance/registration").status = status;
    await f.resend();
    const message = [...f.data.entries()].find(([path]) => path.startsWith("OutboundMessages/"))[1];
    assert.equal(message.templateId, templateId);
  }
});

test("business links stay within the selected runtime environment", () => {
  const {publicOrigin} = require("../public-web/origin");
  assert.equal(publicOrigin({GCLOUD_PROJECT: "orgami-66nxok"}), "https://attendus.app");
  assert.equal(publicOrigin({GCLOUD_PROJECT: "attendus-staging"}), "https://attendus-staging.web.app");
  assert.equal(publicOrigin({GCLOUD_PROJECT: "demo-attendus-admin", FUNCTIONS_EMULATOR: "true"}), "http://127.0.0.1:4173");
  assert.equal(publicOrigin({GCLOUD_PROJECT: "demo-attendus-admin", FUNCTIONS_EMULATOR: "true", ATTENDUS_EMULATOR_PUBLIC_ORIGIN: "http://localhost:5000"}), "http://localhost:5000");
  for (const env of [{}, {GCLOUD_PROJECT: "unknown"}, {GCLOUD_PROJECT: "demo-attendus-admin"},
    {GCLOUD_PROJECT: "attendus-staging", GOOGLE_CLOUD_PROJECT: "orgami-66nxok"},
    ...["https://attendus.app", "http://localhost:4173/path", "http://user:password@localhost:4173", "http://localhost:4173?redirect=prod"].map((origin) => ({GCLOUD_PROJECT: "demo-attendus-admin", FUNCTIONS_EMULATOR: "true", ATTENDUS_EMULATOR_PUBLIC_ORIGIN: origin}))]) {
    assert.throws(() => publicOrigin(env));
  }
});
