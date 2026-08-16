"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("../firebase-admin-compat");
const {runAccountDeletion} = require("../account/deletion");
const {
  fetchWithTimeout,
  uniqueId,
} = require("./emulator-test-helpers");

const projectId = process.env.GCLOUD_PROJECT;
assert.equal(projectId, "demo-attendus-admin");
const api = `http://127.0.0.1:5001/${projectId}/us-central1/adminApi`;
const freeTicketApi = `http://127.0.0.1:5001/${projectId}/us-central1/issueFreeTicket`;
const authApi = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1";
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
  await db.collection("Attendance").doc(`attendance-${uid}`).set({userId: uid});
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
    ticketsEnabled: true,
    ticketPrice: 0,
    maxTickets: 2,
    issuedTickets: 0,
    selectedDateTime: admin.firestore.Timestamp.fromDate(
        new Date("2026-10-01T18:00:00Z"),
    ),
  });

  const call = () => fetchWithTimeout(freeTicketApi, {
    method: "POST",
    headers: {
      authorization: `Bearer ${created.idToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({data: {eventId}}),
  });
  const firstResponse = await call();
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
