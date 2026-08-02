"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  DELETE_QUERIES,
  PAYMENT_COLLECTIONS,
  ROOT_DOCUMENTS,
  STORAGE_PREFIXES,
  accountHash,
} = require("../account/deletion");

test("account deletion contract covers sensitive user data", () => {
  const deletedCollections = new Set(DELETE_QUERIES.map(([name]) => name));
  for (const required of [
    "Attendance",
    "Conversations",
    "FaceEnrollments",
    "Messages",
    "RegisterAttendance",
    "Tickets",
  ]) {
    assert.equal(deletedCollections.has(required), true, `${required} is covered`);
  }
  assert.equal(ROOT_DOCUMENTS.includes("users"), true);
  assert.equal(ROOT_DOCUMENTS.includes("Customers"), true);
  assert.equal(PAYMENT_COLLECTIONS.includes("TicketPayments"), true);
  assert.equal(STORAGE_PREFIXES.some((prefix) => prefix.startsWith("profile_")), true);
});

test("deleted account hashes are stable and do not expose the uid", () => {
  const uid = "user-sensitive-123";
  const hash = accountHash(uid);
  assert.equal(hash, accountHash(uid));
  assert.equal(hash.length, 64);
  assert.equal(hash.includes(uid), false);
  assert.notEqual(hash, accountHash("different-user"));
});
