"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("../firebase-admin-compat");
const {runAccountDeletion} = require("../account/deletion");

const projectId = process.env.GCLOUD_PROJECT || "demo-attendus-admin";
const api = `http://127.0.0.1:5001/${projectId}/us-central1/adminApi`;
const authApi = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1";
async function auth(method, body) {
  const response = await fetch(`${authApi}/accounts:${method}?key=emulator-key`, {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify(body)});
  const responseText = await response.text();
  assert.equal(response.ok, true, responseText);
  return JSON.parse(responseText);
}

test("emulator rejects non-admin and audited mutation creates record", async () => {
  const email = `support-${Date.now()}@example.test`; const password = "ValidPassword123!";
  const created = await auth("signUp", {email, password, returnSecureToken: true});
  const denied = await fetch(`${api}/v1/accounts`, {headers: {authorization: `Bearer ${created.idToken}`}});
  assert.equal(denied.status, 403); assert.equal((await denied.json()).error.code, "ADMIN_CLAIM_REQUIRED");

  await admin.auth().setCustomUserClaims(created.localId, {admin: true});
  await admin.firestore().collection("admin_roles").doc(created.localId).set({active: true, roles: ["support"]});
  const signedIn = await auth("signInWithPassword", {email, password, returnSecureToken: true});
  const target = await auth("signUp", {email: `target-${Date.now()}@example.test`, password, returnSecureToken: true});
  const requestId = `integration-${Date.now()}`;
  const changed = await fetch(`${api}/v1/accounts/${target.localId}/disable`, {method: "POST", headers: {"authorization": `Bearer ${signedIn.idToken}`, "content-type": "application/json", "idempotency-key": `integration-key-${Date.now()}`, "x-request-id": requestId}, body: JSON.stringify({reason: "Verified emulator support case", confirmed: true})});
  assert.equal(changed.status, 200, await changed.text());
  const audit = await admin.firestore().collection("admin_audit_logs").where("requestId", "==", requestId).get();
  assert.equal(audit.size, 1); assert.equal(audit.docs[0].get("action"), "account.disable");
});

test("account erasure is complete, auditable, and idempotent", async () => {
  const email = `erase-${Date.now()}@example.test`;
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
