"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("../firebase-admin-compat");
const {runAccountDeletion} = require("../account/deletion");
const {
  fetchWithTimeout,
  uniqueId,
  emulatorOrigin,
} = require("./emulator-test-helpers");

const projectId = process.env.GCLOUD_PROJECT;
assert.equal(projectId, "demo-attendus-admin");
const functionsOrigin = emulatorOrigin("FIREBASE_FUNCTIONS_EMULATOR_HOST");
const api = `${functionsOrigin}/${projectId}/us-central1/adminApi`;
const freeTicketApi = `${functionsOrigin}/${projectId}/us-central1/issueFreeTicket`;
const authApi = `${emulatorOrigin("FIREBASE_AUTH_EMULATOR_HOST")}/identitytoolkit.googleapis.com/v1`;
async function auth(method, body) {
  const response = await fetchWithTimeout(
      `${authApi}/accounts:${method}?key=emulator-key`,
      {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify(body)},
  );
  const responseText = await response.text();
  assert.equal(response.ok, true, responseText);
  return JSON.parse(responseText);
}

test("emulator rejects non-admin and audited mutation creates record", async () => {
  const email = `${uniqueId("support")}@example.test`; const password = "ValidPassword123!";
  const created = await auth("signUp", {email, password, returnSecureToken: true});
  const denied = await fetchWithTimeout(`${api}/v1/accounts`, {headers: {authorization: `Bearer ${created.idToken}`}});
  assert.equal(denied.status, 403); assert.equal((await denied.json()).error.code, "ADMIN_CLAIM_REQUIRED");

  await admin.auth().setCustomUserClaims(created.localId, {admin: true});
  await admin.firestore().collection("admin_roles").doc(created.localId).set({active: true, roles: ["support"]});
  const signedIn = await auth("signInWithPassword", {email, password, returnSecureToken: true});
  const target = await auth("signUp", {email: `${uniqueId("target")}@example.test`, password, returnSecureToken: true});
  const requestId = uniqueId("integration");
  const changed = await fetchWithTimeout(`${api}/v1/accounts/${target.localId}/disable`, {method: "POST", headers: {"authorization": `Bearer ${signedIn.idToken}`, "content-type": "application/json", "idempotency-key": uniqueId("integration-key"), "x-request-id": requestId}, body: JSON.stringify({reason: "Verified emulator support case", confirmed: true})});
  assert.equal(changed.status, 200, await changed.text());
  const audit = await admin.firestore().collection("admin_audit_logs").where("requestId", "==", requestId).get();
  assert.equal(audit.size, 1); assert.equal(audit.docs[0].get("action"), "account.disable");
});

test("account erasure is complete, auditable, and idempotent", async () => {
  const email = `${uniqueId("erase")}@example.test`;
  const password = "ValidPassword123!";
  const created = await auth("signUp", {email, password, returnSecureToken: true});
  const uid = created.localId;
  const db = admin.firestore();
  const bucket = admin.storage().bucket(`${projectId}.appspot.com`);

  await db.collection("users").doc(uid).set({email});
  await db.collection("users").doc(uid).collection("notifications").doc("n1").set({seen: false});
  await db.collection("Customers").doc(uid).set({email});
  await db.collection("Attendance").doc(`attendance-${uid}`).set({userId: uid, eventId: `owned-fixture-${uid}`,
    checkedInAt: new Date("2026-09-01T12:00:00Z"), verificationSource: "staff_roster"});
  await db.collection("FaceEnrollments").doc(`face-${uid}`).set({userId: uid, faceFeatures: [0.1]});
  await db.collection("Messages").doc(`message-${uid}`).set({senderId: uid});
  await db.collection("TicketPayments").doc(`payment-${uid}`).set({
    customerUid: uid,
    customerEmail: email,
    amount: 1500,
    status: "completed",
  });
  await bucket.file(`profile_pictures/${uid}/avatar.jpg`).save(Buffer.from("avatar"), {
    contentType: "image/jpeg",
  });

  for (const path of [`user_banners/${uid}/banner.jpg`, `event-drafts/${uid}/draft/cover.jpg`]) {
    await bucket.file(path).save(Buffer.from("fixture"), {contentType: "image/jpeg"});
  }
  const first = await runAccountDeletion({
    uid,
    db,
    auth: admin.auth(),
    bucket,
  });
  assert.equal(first.status, "complete");
  assert.equal((await db.collection("users").doc(uid).get()).exists, false);
  assert.equal((await db.collection("Attendance").doc(`attendance-${uid}`).get()).exists, false);
  assert.equal((await db.collection("FaceEnrollments").doc(`face-${uid}`).get()).exists, false);
  assert.equal((await db.collection("Messages").doc(`message-${uid}`).get()).exists, false);
  assert.equal((await bucket.file(`profile_pictures/${uid}/avatar.jpg`).exists())[0], false);
  for (const path of [`user_banners/${uid}/banner.jpg`, `event-drafts/${uid}/draft/cover.jpg`]) {
    assert.equal((await bucket.file(path).exists())[0], false);
  }
  const archiveId = require("../events/roster").key(`attendance-${uid}`);
  assert.equal((await db.collection("HistoricalAttendance").doc(archiveId).get()).exists, true);

  const payment = await db.collection("TicketPayments").doc(`payment-${uid}`).get();
  assert.equal(payment.exists, true);
  assert.equal(payment.get("customerUid"), undefined);
  assert.equal(payment.get("customerEmail"), undefined);
  assert.equal(typeof payment.get("deletedAccountHash"), "string");
  await assert.rejects(admin.auth().getUser(uid), {code: "auth/user-not-found"});

  const second = await runAccountDeletion({uid, db, auth: admin.auth(), bucket});
  assert.deepEqual(second, first);
  const job = await db.collection("account_deletion_jobs").doc(uid).get();
  assert.equal(job.get("status"), "complete");
});

test("free ticket issuance is atomic and idempotent", async () => {
  const email = `${uniqueId("ticket")}@example.test`;
  const password = "ValidPassword123!";
  const created = await auth("signUp", {email, password, returnSecureToken: true});
  const uid = created.localId;
  const eventId = uniqueId("free-event");
  const db = admin.firestore();
  await db.collection("Customers").doc(uid).set({name: "Ticket Tester", email});
  await db.collection("Events").doc(eventId).set({
    customerUid: "organizer",
    title: "Free Event",
    imageUrl: "",
    location: "Test Hall",
    private: false,
    status: "active",
    ticketsEnabled: true,
    ticketPrice: 0,
    maxTickets: 2,
    issuedTickets: 0,
    selectedDateTime: admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 24 * 60 * 60 * 1000),
    ),
  });

  const call = (timeoutMs = 15000) => fetchWithTimeout(freeTicketApi, {
    method: "POST",
    headers: {
      authorization: `Bearer ${created.idToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({data: {eventId}}),
  }, timeoutMs);
  // A fresh emulator starts a separate runtime for this callable. Give only
  // that cold invocation a startup allowance; the replay keeps the normal limit.
  const firstResponse = await call(60000);
  const firstText = await firstResponse.text();
  assert.equal(firstResponse.status, 200, firstText);
  const first = JSON.parse(firstText).result;
  const secondResponse = await call();
  const secondText = await secondResponse.text();
  assert.equal(secondResponse.status, 200, secondText);
  const second = JSON.parse(secondText).result;

  assert.equal(first.ticketId, second.ticketId);
  assert.equal(first.created, true);
  assert.equal(second.created, false);
  assert.equal((await db.collection("Events").doc(eventId).get())
      .get("issuedTickets"), 1);
  assert.equal((await db.collection("Tickets")
      .where("eventId", "==", eventId).get()).size, 1);
  assert.equal((await db.collection("RegisterAttendance")
      .where("eventId", "==", eventId).get()).size, 1);
});
