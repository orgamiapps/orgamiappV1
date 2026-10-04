"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {memoryAdmin} = require("./helpers/community-memory");
const {anonymizeExpiredGuestContacts} = require("../public-web/guest-retention");
const now = Date.parse("2026-10-03T12:00:00Z");
const expired = {retentionAt: new Date(now - 86400000), fullName: "Guest", encryptedEmail: "cipher", maskedEmail: "g@example.test", emailHash: "hash"};

test("retention progresses beyond 200 terminal records and repeats without changing claimed contact data", async () => {
  const initial = Object.fromEntries(Array.from({length: 205}, (_, index) => [`GuestAttendees/claimed-${String(index).padStart(3, "0")}`, {...expired, claimedByUid: "member"}]));
  initial["GuestAttendees/target"] = {...expired};
  const admin = memoryAdmin(initial);
  const result = await anonymizeExpiredGuestContacts(admin, now);
  assert.deepEqual(result, {scanned: 206, anonymized: 1, retired: 205});
  assert.equal(admin.db.values.get("GuestAttendees/target").fullName, "Former attendee");
  assert.equal(admin.db.values.get("GuestAttendees/target").encryptedEmail, null);
  assert.equal(admin.db.values.get("GuestAttendees/claimed-000").encryptedEmail, "cipher");
  assert.equal(admin.db.values.get("GuestAttendees/claimed-000").retentionAt, undefined);
  assert.deepEqual(await anonymizeExpiredGuestContacts(admin, now), {scanned: 0, anonymized: 0, retired: 0});
});

test("retention rechecks a concurrent claim and never overwrites current claimed contact", async () => {
  const admin = memoryAdmin({"GuestAttendees/target": {...expired}});
  const run = admin.db.runTransaction;
  admin.db.runTransaction = (work) => {
    admin.db.values.set("GuestAttendees/target", {...expired, claimedByUid: "member", fullName: "Claimed account name", encryptedEmail: "new-cipher"});
    return run(work);
  };
  const result = await anonymizeExpiredGuestContacts(admin, now);
  assert.equal(result.anonymized, 0); assert.equal(result.retired, 1);
  assert.equal(admin.db.values.get("GuestAttendees/target").encryptedEmail, "new-cipher");
  assert.equal(admin.db.values.get("GuestAttendees/target").fullName, "Claimed account name");
});

test("retention skips current deletion, renewed retention and removed documents without resurrection", async () => {
  const admin = memoryAdmin({"GuestAttendees/deleting": {...expired, ownerUid: "deleting"}, "account_deletion_jobs/deleting": {status: "running"},
    "GuestAttendees/removed": {...expired}, "GuestAttendees/renewed": {...expired}});
  const run = admin.db.runTransaction;
  let first = true;
  admin.db.runTransaction = (work) => {
    if (first) {
      first = false;
      admin.db.values.delete("GuestAttendees/removed");
      admin.db.values.get("GuestAttendees/renewed").retentionAt = new Date(now + 86400000);
    }
    return run(work);
  };
  const result = await anonymizeExpiredGuestContacts(admin, now);
  assert.equal(result.anonymized, 0);
  assert.equal(admin.db.values.has("GuestAttendees/removed"), false);
  assert.equal(admin.db.values.get("GuestAttendees/deleting").encryptedEmail, "cipher");
  assert.equal(admin.db.values.get("GuestAttendees/renewed").encryptedEmail, "cipher");
});
