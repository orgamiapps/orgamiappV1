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
