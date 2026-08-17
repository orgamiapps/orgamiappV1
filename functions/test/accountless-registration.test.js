"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {normalizeContact, normalizeName, maskedContact, ticketQrSvg, validateEvent} =
  require("../public-web/accountless");
const {calendarInvite, fallbackTemplate} = require("../communications/delivery");

test("normalizes email and U.S. phone contacts", () => {
  assert.deepEqual(normalizeContact("email", " Person@Example.COM "), {
    type: "email", value: "person@example.com", display: "person@example.com",
  });
  assert.deepEqual(normalizeContact("phone", "(239) 555-0123"), {
    type: "phone", value: "+12395550123", display: "(239) 555-0123",
  });
  assert.equal(maskedContact(normalizeContact("phone", "+1 239 555 0123")),
      "(***) ***-0123");
});

test("rejects non-U.S. and malformed contacts", () => {
  assert.throws(() => normalizeContact("phone", "+44 20 7946 0958"), /U.S. mobile/);
  assert.throws(() => normalizeContact("email", "missing-at.example"), /email/);
});

test("requires a real first and last name value", () => {
  assert.equal(normalizeName("  María-José  ", "first name"), "María-José");
  assert.throws(() => normalizeName("<script>", "first name"), /first name/);
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

test("calendar invitation uses a stable registration UID", () => {
  const invite = calendarInvite({registrationId: "registration-1", payload: {
    eventTitle: "Food, Fun & Friends", eventStart: new Date("2030-01-02T15:00:00Z"),
    eventLocation: "Main Hall; Suite 2", manageUrl: "https://attendus.app/manage/token",
  }});
  assert.match(invite, /UID:registration-1@attendus\.app/);
  assert.match(invite, /SUMMARY:Food\\, Fun & Friends/);
  assert.match(invite, /LOCATION:Main Hall\\; Suite 2/);
});

test("fallback messages identify Attendus and provide opt-out copy", () => {
  const template = fallbackTemplate({registrationId: "r1", payload: {
    firstName: "Taylor", eventTitle: "Community Night", kind: "rsvp",
    manageUrl: "https://attendus.app/manage/token",
  }});
  assert.match(template.subject, /Community Night/);
  assert.match(template.sms, /^Attendus:/);
  assert.match(template.sms, /Reply STOP/);
  assert.match(template.html, /support@attendus\.app/);
});

test("ticket QR output is an accessible-size SVG without external resources", async () => {
  const svg = await ticketQrSvg("A1B2C3D4");
  assert.match(svg, /^<svg/);
  assert.match(svg, /viewBox=/);
  assert.doesNotMatch(svg, /<script|href=|xlink:/i);
});
