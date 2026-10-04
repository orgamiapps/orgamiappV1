"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createHash, createHmac} = require("node:crypto");
const {issueRosterCursor, verifyRosterCursor, ROSTER_CURSOR_TTL_MS} = require("../events/roster-cursor");
const secret = "fixture-roster-signing-key-only";
const now = 1800000000000;
const filterKey = createHash("sha256").update("all filters").digest("hex");
const payload = {eventId: "event:1", actorUid: "owner", generation: "generation-1", filterKey,
  id: "row-1", issuedAt: now, expiresAt: now + ROSTER_CURSOR_TTL_MS};
const expected = {eventId: payload.eventId, actorUid: payload.actorUid, filterKey};

test("signed cursor round trips and later pages preserve the original expiry", () => {
  const token = issueRosterCursor(payload, secret, now);
  assert.deepEqual(verifyRosterCursor(token, expected, secret, now), payload);
  const verified = verifyRosterCursor(token, expected, secret, now + 60000);
  const next = issueRosterCursor({...verified, id: "row-2"}, secret, now + 60000);
  assert.equal(verifyRosterCursor(next, expected, secret, now + 60000).expiresAt, payload.expiresAt);
});
test("wrong actor, event, filter or signing key cannot replay a cursor", () => {
  const token = issueRosterCursor(payload, secret, now);
  for (const changed of [{actorUid: "other"}, {eventId: "other"}, {filterKey: "0".repeat(64)}]) {
    assert.throws(() => verifyRosterCursor(token, {...expected, ...changed}, secret, now), {code: "invalid-argument"});
  }
  assert.throws(() => verifyRosterCursor(token, expected, "different-key", now), {code: "invalid-argument"});
});
test("payload edits including retention extension or generation swapping break the signature", () => {
  const parts = issueRosterCursor(payload, secret, now).split(".");
  for (const changed of [{expiresAt: payload.expiresAt + 1}, {generation: "other"}, {id: "row-99"}]) {
    const encoded = Buffer.from(JSON.stringify({...payload, ...changed})).toString("base64url");
    assert.throws(() => verifyRosterCursor(`${parts[0]}.${encoded}.${parts[2]}`, expected, secret, now), {code: "invalid-argument"});
  }
});
test("cursor expires at the exact expiry instant and cannot be issued beyond 15 minutes", () => {
  const token = issueRosterCursor(payload, secret, now);
  assert.throws(() => verifyRosterCursor(token, expected, secret, payload.expiresAt), {code: "aborted"});
  assert.throws(() => issueRosterCursor({...payload, expiresAt: payload.expiresAt + 1}, secret, now), {code: "invalid-argument"});
  assert.throws(() => issueRosterCursor({...payload, issuedAt: now + 1}, secret, now), {code: "invalid-argument"});
});
test("missing keys and malformed or oversized cursor inputs fail closed", () => {
  for (const key of [undefined, null, "", "   ", Buffer.alloc(0), 42]) {
    assert.throws(() => issueRosterCursor(payload, key, now), {code: "failed-precondition"});
    assert.throws(() => verifyRosterCursor("token", expected, key, now), {code: "failed-precondition"});
  }
  for (const token of [null, {}, "", "a".repeat(4097), "v2.abc.def", "v1.abc.a", "v1.a!." + "a".repeat(43)]) {
    assert.throws(() => verifyRosterCursor(token, expected, secret, now), {code: "invalid-argument"});
  }
});
test("payload field types and path inputs are validated even with a valid signature", () => {
  for (const changes of [{id: "../other"}, {actorUid: "x/other"}, {generation: []}, {eventId: "x".repeat(501)},
    {filterKey: "not-a-hash"}, {issuedAt: String(now)}, {expiresAt: Infinity}, {extra: true}]) {
    const encoded = Buffer.from(JSON.stringify({...payload, ...changes})).toString("base64url");
    const message = `v1.${encoded}`;
    const tag = createHmac("sha256", secret).update("attendus/roster-cursor/v1\0").update(message).digest("base64url");
    assert.throws(() => verifyRosterCursor(`${message}.${tag}`, expected, secret, now), {code: "invalid-argument"});
  }
});
test("unrelated HMAC use cannot produce roster cursor signatures", () => {
  const encoded = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const message = `v1.${encoded}`;
  const tag = createHmac("sha256", secret).update(message).digest("base64url");
  assert.throws(() => verifyRosterCursor(`${message}.${tag}`, expected, secret, now), {code: "invalid-argument"});
});
