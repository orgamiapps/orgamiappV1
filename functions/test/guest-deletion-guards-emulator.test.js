"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw Error("Local Firestore emulator required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
process.env.GUEST_CONTACT_KMS_KEY_NAME = "emulator";
process.env.GUEST_CONTACT_HMAC_KEY = "guard-fixture-only";
const admin = require("../firebase-admin-compat");
const db = admin.firestore();
const accountless = require("../public-web/accountless");
const renderer = require("../public-web/renderer");
const {anonymizeExpiredGuestContacts} = require("../public-web/guest-retention");
const request = (uid, data) => ({auth: {uid, token: {email: "fixture@example.test", firebase: {sign_in_provider: "password"}}}, data});

test("guest retention passes 200 terminal records without starving expired unclaimed contact", async () => {
  const prefix = `retention-${randomUUID()}`;
  const batch = db.batch();
  for (let index = 0; index < 205; index++) batch.set(db.collection("GuestAttendees").doc(`${prefix}-claimed-${index}`), {
    claimedByUid: `${prefix}-owner`, fullName: "Claimed fixture", encryptedEmail: "preserved", retentionAt: new Date(1),
  });
  const expired = db.collection("GuestAttendees").doc(`${prefix}-expired`);
  batch.set(expired, {fullName: "Expired fixture", encryptedEmail: "remove", emailHash: "remove", retentionAt: new Date(2)});
  await batch.commit();
  await anonymizeExpiredGuestContacts(admin, Date.now());
  assert.equal((await expired.get()).get("encryptedEmail"), null);
  assert.equal((await expired.get()).get("retentionAt"), undefined);
  const claimed = await db.collection("GuestAttendees").doc(`${prefix}-claimed-0`).get();
  assert.equal(claimed.get("encryptedEmail"), "preserved"); assert.equal(claimed.get("retentionAt"), undefined);
});

async function fixture() {
  const uid = `guard-${randomUUID()}`;
  const eventId = `event-${uid}`;
  const registrationId = `registration-${uid}`;
  const guestId = `guest-${uid}`;
  const token = randomUUID().replaceAll("-", "") + "fixture";
  await db.collection("Events").doc(eventId).set({customerUid: uid, title: "Fixture", selectedDateTime: new Date(Date.now() + 86400000), private: false});
  await db.collection("GuestAttendees").doc(guestId).set({ownerUid: uid, fullName: "Fixture", emailHash: "old", encryptedEmail: "fixture", claimedByUid: null});
  await db.collection("RegisterAttendance").doc(registrationId).set({customerUid: uid, guestId, eventId, status: "confirmed"});
  await db.collection("GuestManageTokens").doc(accountless.digest(token)).set({ownerUid: uid, guestId, registrationId, status: "active", expiresAt: new Date(Date.now() + 600000)});
  return {uid, eventId, registrationId, guestId, token};
}

test("resend and email updates cannot recreate contact data for deleting subject", async () => {
  const f = await fixture();
  await db.collection("account_deletion_jobs").doc(f.uid).set({status: "running"});
  const requestData = {registrationId: f.registrationId, idempotencyKey: "fixture-request", email: "changed@example.test"};
  for (const create of [accountless.createResendPublicRegistrationConfirmationV1, accountless.createUpdatePublicRegistrationEmailV1]) {
    await assert.rejects(create(admin).run(request(f.uid, requestData)), /deletion is in progress/);
  }
  assert.equal((await db.collection("GuestAttendees").doc(f.guestId).get()).get("emailHash"), "old");
  assert.equal((await db.collection("OutboundMessages").where("guestId", "==", f.guestId).get()).empty, true);
});

test("claims fence both deleting caller and deleting original subject", async () => {
  for (const deletingCaller of [true, false]) {
    const f = await fixture(); const caller = `caller-${randomUUID()}`;
    await db.collection("account_deletion_jobs").doc(deletingCaller ? caller : f.uid).set({status: "running"});
    await assert.rejects(accountless.createClaimPublicRegistrationV1(admin).run(request(caller,
        {registrationId: f.registrationId, claimToken: f.token})), /deletion is in progress/);
    assert.equal((await db.collection("Customers").doc(caller).get()).exists, false);
    assert.equal((await db.collection("GuestAttendees").doc(f.guestId).get()).get("ownerUid"), f.uid);
  }
});

test("follow does not recreate a deleting organizer's nested profile data", async () => {
  const f = await fixture(); const caller = `follower-${randomUUID()}`;
  await db.collection("account_deletion_jobs").doc(f.uid).set({status: "running"});
  await assert.rejects(accountless.createFollowPublicEventOrganizerV1(admin).run(request(caller, {eventId: f.eventId})), /deletion is in progress/);
  assert.equal((await db.collection("Customers").doc(f.uid).collection("followers").doc(caller).get()).exists, false);
});

test("manage token exchange cannot recreate a removed guest or issue session during deletion", async () => {
  for (const removed of [false, true]) {
    const f = await fixture();
    if (removed) await db.collection("GuestAttendees").doc(f.guestId).delete();
    else await db.collection("account_deletion_jobs").doc(f.uid).set({status: "running"});
    await assert.rejects(renderer.exchangeManageToken(db, {}, {}, f.token, "fixture"), removed ? /Registration not found/ : /deletion is in progress/);
    assert.equal((await db.collection("GuestManageSessions").where("guestId", "==", f.guestId).get()).empty, true);
    assert.equal((await db.collection("GuestManageTokens").doc(accountless.digest(f.token)).get()).get("status"), "active");
  }
});

test("manage email action rechecks session and deletion before all token/contact writes", async () => {
  const f = await fixture(); const raw = randomUUID().replaceAll("-", "") + "session";
  const csrf = "fixture-csrf";
  await db.collection("GuestManageSessions").doc(accountless.digest(raw)).set({status: "active", registrationId: f.registrationId,
    guestId: f.guestId, csrfToken: csrf, expiresAt: new Date(Date.now() + 600000)});
  await db.collection("account_deletion_jobs").doc(f.uid).set({status: "running"});
  const req = {get: () => `attendus_guest_manage=${raw}`, body: {csrf, action: "update_email", email: "changed@example.test"}};
  const res = {set() { return this; }, status() { return this; }, send() { return this; }, type() { return this; }};
  await renderer.manageAction(db, req, res, "fixture");
  assert.equal((await db.collection("GuestAttendees").doc(f.guestId).get()).get("emailHash"), "old");
  assert.equal((await db.collection("OutboundMessages").where("guestId", "==", f.guestId).get()).empty, true);
  assert.equal((await db.collection("GuestManageTokens").where("guestId", "==", f.guestId).get()).size, 1);
});

test("active owned registration can resend and update email through guarded transactions", async () => {
  const f = await fixture();
  const data = {registrationId: f.registrationId, idempotencyKey: "fixture-active", email: "active@example.test"};
  assert.equal((await accountless.createResendPublicRegistrationConfirmationV1(admin).run(request(f.uid, data))).status, "pending");
  assert.equal((await db.collection("OutboundMessages").where("guestId", "==", f.guestId).get()).size, 1);
  assert.equal((await accountless.createUpdatePublicRegistrationEmailV1(admin).run(request(f.uid, data))).status, "updated");
  assert.equal((await db.collection("GuestAttendees").doc(f.guestId).get()).get("emailHash"), accountless.emailHash(data.email));
});

test("claim transfers explicit multiple admissions and rejects incomplete legacy linkage", async () => {
  const f = await fixture(); const caller = `active-claim-${randomUUID()}`;
  for (const index of [1, 2]) await db.collection("Tickets").doc(`${f.guestId}-${index}`).set({guestId: f.guestId,
    eventId: f.eventId, registrationId: f.registrationId, customerUid: f.uid});
  assert.equal((await accountless.createClaimPublicRegistrationV1(admin).run(request(caller,
      {registrationId: f.registrationId, claimToken: f.token}))).status, "claimed");
  for (const index of [1, 2]) assert.equal((await db.collection("Tickets").doc(`${f.guestId}-${index}`).get()).get("customerUid"), caller);
  const legacy = await fixture();
  await db.collection("Tickets").doc(legacy.guestId).set({guestId: legacy.guestId, eventId: legacy.eventId, customerUid: legacy.uid});
  await assert.rejects(accountless.createClaimPublicRegistrationV1(admin).run(request(caller,
      {registrationId: legacy.registrationId, claimToken: legacy.token})), /linkage requires review/);
  assert.equal((await db.collection("GuestAttendees").doc(legacy.guestId).get()).get("ownerUid"), legacy.uid);
});

test("claim preserves an established profile and replays only for the same owner", async () => {
  const f = await fixture(); const caller = `established-${randomUUID()}`;
  const profile = {name: "Established Name", username: "established", email: "existing@example.test", isDiscoverable: true, createdAt: "original"};
  await db.collection("Customers").doc(caller).set(profile);
  const claim = accountless.createClaimPublicRegistrationV1(admin);
  const input = {registrationId: f.registrationId, claimToken: f.token};
  assert.equal((await claim.run(request(caller, input))).status, "claimed");
  assert.equal((await claim.run(request(caller, input))).status, "claimed");
  assert.deepEqual((await db.collection("Customers").doc(caller).get()).data(), profile);
  await assert.rejects(claim.run(request(`outsider-${randomUUID()}`, input)), {code: "permission-denied"});
});

test("concurrent confirmation resend retries create one status-correct message", async () => {
  const f = await fixture();
  await db.collection("RegisterAttendance").doc(f.registrationId).update({status: "pending"});
  const resend = accountless.createResendPublicRegistrationConfirmationV1(admin);
  const input = request(f.uid, {registrationId: f.registrationId, idempotencyKey: "resend-concurrent-request"});
  await Promise.all([resend.run(input), resend.run(input)]);
  const messages = await db.collection("OutboundMessages").where("guestId", "==", f.guestId).get();
  assert.equal(messages.size, 1);
  assert.equal(messages.docs[0].get("templateId"), "guest_registration_pending");
  assert.equal((await db.collection("GuestManageTokens").where("guestId", "==", f.guestId).get()).size, 2);
});
