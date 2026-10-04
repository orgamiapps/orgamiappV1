"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const core = require("../attendance/arrival-core");
const arrival = require("../attendance/arrival");
const v2 = require("../attendance/v2");

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIRESTORE_EMULATOR_HOST.startsWith("127.0.0.1:")) {
  throw Error("Attendance integration tests require the local Firestore emulator.");
}
const app = initializeApp({projectId: "demo-attendus-admin"}, "arrival-tests");
const db = getFirestore(app);
const sdk = {firestore: () => db};
const suffix = crypto.randomBytes(6).toString("hex");
const eventId = `arrival-${suffix}`;
const uid = `attendee-${suffix}`;
const staff = `staff-${suffix}`;
const registrationId = `registration-${suffix}`;
const key = crypto.generateKeyPairSync("ed25519");
process.env.ATTENDANCE_PASS_SIGNING_KEY = JSON.stringify({kid: `key-${suffix}`, privateKey: key.privateKey.export({format: "pem", type: "pkcs8"})});
delete process.env.APPLE_WALLET_SIGNING;
delete process.env.GOOGLE_WALLET_SERVICE_ACCOUNT_JSON;
const request = (actor, data, anonymous = false) => ({auth: {uid: actor, token: {firebase: {sign_in_provider: anonymous ? "anonymous" : "password"}}}, data});
const position = () => ({latitude: 40, longitude: -74, accuracy: 10, sampledAt: new Date().toISOString()});
const event = () => ({id: eventId, title: "Arrival integration", customerUid: staff, private: false,
  status: "active", locationType: "in_person", location: "Test venue", latitude: 40, longitude: -74,
  selectedDateTime: Timestamp.fromMillis(Date.now() - 60000), eventDuration: 2,
  checkInPolicy: {version: 3, profile: "hybrid", eligibility: "registered_only", opensBeforeMinutes: 60,
    closesAfterMinutes: 60, allowReentry: true, openingMode: "scheduled",
    smartArrival: {enabled: true, latitude: 40, longitude: -74, radiusMeters: 150}}});
let sessionId;
let pass;
test.before(async () => {
  await db.collection("AppConfig").doc("attendance").set({smartArrival: {enabled: true, allEvents: true}, corePasses: {enabled: true, allEvents: true, identityEnabled: true},
    appleDelivery: {enabled: false}, googleDelivery: {enabled: false}});
  await db.collection("Events").doc(eventId).set(event());
  await db.collection("Customers").doc(uid).set({name: "Test Attendee"});
  await db.collection("RegisterAttendance").doc(registrationId).set({eventId, customerUid: uid, realName: "Test Attendee", status: "confirmed", answers: ["Diet--ans--Vegetarian"]});
  await db.collection("Events").doc(eventId).collection("EventQuestions").doc("diet").set({questionTitle: "Diet", required: true});
});
test.after(async () => { await deleteApp(app); });

test("event pass issues before a session opens and rejects other owners", async () => {
  pass = await arrival.issuePass(db, uid, {kind: "event", eventId, registrationId});
  assert.ok(pass.qrData.startsWith(core.PREFIX));
  assert.equal((await db.collection("CheckInSessions").where("eventId", "==", eventId).get()).size, 0);
  await assert.rejects(() => arrival.issuePass(db, staff, {kind: "event", eventId, registrationId}));
  await assert.rejects(() => arrival.issuePass(db, uid, {kind: "identity"}));
});

test("location lazily opens a session and concurrent confirmations count once", async () => {
  const handler = v2.createSubmitCheckIn(sdk);
  const submit = () => handler.run(request(uid, {eventId, sessionId: "", credential: {type: "location", position: position()},
    answers: [], idempotencyKey: crypto.randomUUID()}));
  const receipts = await Promise.all([submit(), submit()]);
  assert.equal(receipts[0].attendanceId, receipts[1].attendanceId);
  sessionId = receipts[0].sessionId;
  const attendance = (await db.collection("Attendance").doc(receipts[0].attendanceId).get()).data();
  assert.equal(attendance.reentryCount, 0);
  assert.equal(attendance.verificationLevel, "location_assisted");
  assert.deepEqual(attendance.answers, ["Diet--ans--Vegetarian"]);
  assert.equal(JSON.stringify(attendance).includes("latitude"), false);
});

test("event and identity scans share attendance across a session restart", async () => {
  await v2.createEndCheckInSession(sdk).run(request(staff, {sessionId}));
  sessionId = (await v2.createStartCheckInSession(sdk).run(request(staff, {eventId}))).sessionId;
  const identity = await arrival.issuePass(db, uid, {kind: "identity"}, {fullAccount: true});
  const handler = v2.createSubmitCheckIn(sdk);
  for (const token of [pass.qrData, identity.qrData]) {
    const receipt = await handler.run(request(staff, {eventId, sessionId, credential: {type: "attendance_pass", value: token}, answers: [], idempotencyKey: crypto.randomUUID()}));
    assert.equal(receipt.created, false);
  }
  assert.equal((await db.collection("Attendance").where("eventId", "==", eventId).get()).size, 1);
});

test("manual pause survives automatic opening and resume", async () => {
  const functions = arrival.createArrivalFunctions(sdk);
  await functions.setAttendanceControl.run(request(staff, {eventId, status: "paused"}));
  await assert.rejects(() => arrival.ensureSession(db, event(), uid, position()));
  await functions.setAttendanceControl.run(request(staff, {eventId, status: "open"}));
  assert.equal(await arrival.ensureSession(db, event(), uid, position()), sessionId);
});

test("cancelled registration rejects previously issued pass at transaction time", async () => {
  await db.collection("RegisterAttendance").doc(registrationId).update({status: "cancelled"});
  await assert.rejects(() => v2.createSubmitCheckIn(sdk).run(request(staff, {eventId, sessionId,
    credential: {type: "attendance_pass", value: pass.qrData}, answers: [], idempotencyKey: crypto.randomUUID()})));
  await db.collection("RegisterAttendance").doc(registrationId).update({status: "confirmed"});
});

test("offline kit is scoped to event staff and rejects changed schedules on replay", async () => {
  await assert.rejects(() => arrival.offlineKit(db, eventId, sessionId, uid));
  const kit = await arrival.offlineKit(db, eventId, sessionId, staff);
  assert.ok(kit.passes[pass.id]);
  await db.collection("Events").doc(eventId).update({"checkInPolicy.closesAfterMinutes": 90});
  await assert.rejects(() => v2.createSubmitCheckIn(sdk).run(request(staff, {eventId, sessionId,
    offline: true, offlineKitRevision: kit.revision, observedAt: new Date().toISOString(),
    credential: {type: "attendance_pass", value: pass.qrData}, answers: [], idempotencyKey: crypto.randomUUID()})));
});

test("multiple owned tickets require an explicit admission selection", async () => {
  for (const ticketId of [`ticket-a-${suffix}`, `ticket-b-${suffix}`]) {
    await db.collection("Tickets").doc(ticketId).set({eventId, customerUid: uid, registrationId, isUsed: false});
  }
  await assert.rejects(() => arrival.entitlement(db, db, event(), uid), (error) => error.details.tickets.length === 2);
  const selected = await arrival.entitlement(db, db, event(), uid, {ticketId: `ticket-a-${suffix}`});
  assert.equal(selected.ticket.id, `ticket-a-${suffix}`);
});


test("guest claim preserves the event pass and admission before provider updates", async () => {
  const eid = `claim-${suffix}`, guest = `guest-${suffix}`, account = `claimed-${suffix}`, rid = `claim-reg-${suffix}`;
  await db.collection("Events").doc(eid).set({...event(), id: eid});
  await db.collection("RegisterAttendance").doc(rid).set({eventId: eid, customerUid: guest, guestId: guest, status: "confirmed", realName: "Guest Name", isAnonymous: true});
  const original = await arrival.issuePass(db, guest, {kind: "event", eventId: eid, registrationId: rid});
  const sid = (await v2.createStartCheckInSession(sdk).run(request(staff, {eventId: eid}))).sessionId;
  const scan = () => v2.createSubmitCheckIn(sdk).run(request(staff, {eventId: eid, sessionId: sid, credential: {type: "attendance_pass", value: original.qrData}, answers: [], idempotencyKey: crypto.randomUUID()}));
  const first = await scan();
  await db.collection("Customers").doc(account).set({name: "Guest Name"});
  await db.collection("RegisterAttendance").doc(rid).update({customerUid: account, isAnonymous: false});
  const repeated = await scan();
  assert.equal(repeated.attendanceId, first.attendanceId);
  const claimed = await arrival.issuePass(db, account, {kind: "event", eventId: eid, registrationId: rid});
  assert.equal(claimed.id, original.id);
  assert.equal(claimed.qrData, original.qrData);
});

test("required answers, wrong event, and pass replacement fail closed", async () => {
  const eid = `required-${suffix}`, person = `required-person-${suffix}`, rid = `required-reg-${suffix}`;
  await db.collection("Events").doc(eid).set({...event(), id: eid});
  await db.collection("Customers").doc(person).set({name: "Required Person"});
  await db.collection("RegisterAttendance").doc(rid).set({eventId: eid, customerUid: person, status: "confirmed", realName: "Required Person"});
  await db.collection("Events").doc(eid).collection("EventQuestions").doc("required").set({required: true, questionTitle: "Consent"});
  const epass = await arrival.issuePass(db, person, {kind: "event", eventId: eid});
  const sid = (await v2.createStartCheckInSession(sdk).run(request(staff, {eventId: eid}))).sessionId;
  const submit = (answers, value = epass.qrData) => v2.createSubmitCheckIn(sdk).run(request(staff, {eventId: eid, sessionId: sid, credential: {type: "attendance_pass", value}, answers, idempotencyKey: crypto.randomUUID()}));
  await assert.rejects(() => submit([]));
  await assert.rejects(() => submit(["Consent--ans--Yes"], pass.qrData));
  await submit(["Consent--ans--Yes"]);
  const replacement = await arrival.issuePass(db, person, {kind: "event", eventId: eid, replace: true});
  assert.equal(replacement.id, epass.id);
  await assert.rejects(() => submit(["Consent--ans--Yes"]));
  const repeated = await submit(["Consent--ans--Yes"], replacement.qrData);
  assert.equal(repeated.created, false);
  const identity = await arrival.issuePass(db, person, {kind: "identity"}, {fullAccount: true});
  await db.collection("Customers").doc(person).delete();
  await assert.rejects(() => submit(["Consent--ans--Yes"], identity.qrData));
});

test("overlapping private events require access and boundary indexing follows the arrival pin", async () => {
  const {geohashForLocation} = require("geofire-common");
  const eid = `private-${suffix}`, publicId = `public-${suffix}`, visitor = `visitor-${suffix}`;
  const base = {...event(), checkInPolicy: {...event().checkInPolicy, eligibility: "open"}, smartArrivalGeohash: geohashForLocation([40, -74])};
  await db.collection("Events").doc(eid).set({...base, id: eid, private: true});
  await db.collection("Events").doc(publicId).set({...base, id: publicId});
  await assert.rejects(() => arrival.candidates(db, visitor, position(), eid));
  let found = await arrival.candidates(db, visitor, position());
  assert.ok(found.events.some(e => e.eventId === publicId));
  assert.ok(!found.events.some(e => e.eventId === eid));
  await db.collection("RegisterAttendance").doc(`private-reg-${suffix}`).set({eventId: eid, customerUid: visitor, status: "confirmed"});
  found = await arrival.candidates(db, visitor, position());
  assert.equal(found.events[0].eventId, eid);
});


test("offline reconciliation is idempotent and exposes concurrent-device duplicates", async () => {
  const eid = `offline-${suffix}`, person = `offline-person-${suffix}`;
  await db.collection("Events").doc(eid).set({...event(), id: eid});
  await db.collection("RegisterAttendance").doc(`offline-reg-${suffix}`).set({eventId: eid, customerUid: person, status: "confirmed", realName: "Offline Person"});
  const pass = await arrival.issuePass(db, person, {kind: "event", eventId: eid});
  const sid = (await v2.createStartCheckInSession(sdk).run(request(staff, {eventId: eid}))).sessionId;
  const kit = await arrival.offlineKit(db, eid, sid, staff);
  const key = crypto.randomUUID();
  const scan = (idempotencyKey) => v2.createSubmitCheckIn(sdk).run(request(staff, {eventId: eid, sessionId: sid,
    offline: true, offlineKitRevision: kit.revision, observedAt: new Date().toISOString(),
    credential: {type: "attendance_pass", value: pass.qrData}, answers: [], idempotencyKey}));
  const first = await scan(key);
  const replay = await scan(key);
  assert.equal(first.attendanceId, replay.attendanceId);
  assert.equal(replay.conflict, false);
  const otherDevice = await scan(crypto.randomUUID());
  assert.equal(otherDevice.conflict, true);
  assert.equal(otherDevice.attendanceId, first.attendanceId);
  assert.equal((await db.collection("Attendance").where("eventId", "==", eid).get()).size, 1);
});


test("rescheduling and reusable renewal preserve Wallet serial identifiers", async () => {
  const wallet = require("../attendance/wallet");
  const eid = `renew-${suffix}`, person = `renew-person-${suffix}`;
  await db.collection("Events").doc(eid).set({...event(), id: eid});
  await db.collection("Customers").doc(person).set({name: "Renew Person"});
  await db.collection("RegisterAttendance").doc(`renew-reg-${suffix}`).set({eventId: eid, customerUid: person, status: "confirmed", realName: "Renew Person"});
  const original = await arrival.issuePass(db, person, {kind: "event", eventId: eid});
  await db.collection("Events").doc(eid).update({selectedDateTime: Timestamp.fromMillis(Date.now() + core.DAY), location: "New venue"});
  const updated = await wallet.refreshRecord(db, original);
  assert.equal(updated.id, original.id);
  assert.equal(updated.appleAuthenticationToken, original.appleAuthenticationToken);
  assert.equal(updated.location, "New venue");
  assert.ok(updated.expiresAtMs > original.expiresAtMs);
  const identity = await arrival.issuePass(db, person, {kind: "identity"}, {fullAccount: true});
  await db.collection("AttendancePasses").doc(identity.id).update({expiresAtMs: Date.now() + core.DAY});
  const renewed = await wallet.refreshRecord(db, identity);
  assert.equal(renewed.id, identity.id);
  assert.ok(renewed.expiresAtMs > Date.now() + 360 * core.DAY);
  await db.collection("Events").doc(eid).update({status: "cancelled"});
  assert.equal((await wallet.refreshRecord(db, updated)).status, "revoked");
});

test("guest management requires a secure cookie session and renders valid pass controls", async () => {
  const {guestContext, createGuestAttendanceWeb} = require("../attendance/guest-web");
  const eid = `guest-web-${suffix}`, person = `guest-web-person-${suffix}`, rid = `guest-web-reg-${suffix}`;
  await db.collection("Events").doc(eid).set({...event(), id: eid});
  await db.collection("RegisterAttendance").doc(rid).set({eventId: eid, customerUid: person, guestId: person, status: "confirmed", isAnonymous: true, realName: "Web Guest"});
  await assert.rejects(() => guestContext(db, {get: () => ""}));
  await assert.rejects(() => guestContext(db, {get: () => `attendus_guest_manage=${rid}`}));
  const token = crypto.randomBytes(32).toString("hex");
  await db.collection("GuestManageSessions").doc(core.digest(token)).set({registrationId: rid, guestId: person, status: "active", csrfToken: "test-csrf", expiresAt: Timestamp.fromMillis(Date.now() + core.DAY)});
  const req = {method: "GET", get: key => key === "cookie" ? `attendus_guest_manage=${token}` : ""};
  assert.equal((await guestContext(db, req)).uid, person);
  let body;
  const res = {set: () => res, type: () => res, status: () => res, send: value => {body = value;}, json: value => {body = value;}, sendStatus: value => {body = value;}};
  await createGuestAttendanceWeb(sdk)(req, res);
  assert.ok(body.includes("Get my event pass"));
  const script = /<script nonce="[^"]+">([\s\S]*?)<\/script>/.exec(body)[1];
  assert.doesNotThrow(() => new (require("node:vm").Script)(script));
  await createGuestAttendanceWeb(sdk)({...req, method: "POST", body: {csrf: "wrong", action: "wallet"}}, res);
  assert.equal(body, 403);
  await createGuestAttendanceWeb(sdk)({...req, method: "POST", body: {csrf: "test-csrf", action: "wallet"}}, res);
  assert.ok(body.qrImage.startsWith("data:image/png;base64,"));
  assert.equal((await db.collection("AttendancePasses").doc(body.passId).get()).data().status, "active");
  assert.equal(body.appleWalletUrl, null);
  assert.equal(body.googleWalletUrl, null);
});

test("account and event rollout scopes disable issuance without disabling issued verification", async () => {
  const eid = `scoped-${suffix}`, person = `scoped-person-${suffix}`, outsider = `scoped-outsider-${suffix}`;
  const configRef = db.collection("AppConfig").doc("attendance");
  const original = (await configRef.get()).data();
  await db.collection("Events").doc(eid).set({...event(), id: eid});
  for (const owner of [person, outsider]) await db.collection("RegisterAttendance").doc(`scoped-reg-${owner}`).set({eventId: eid, customerUid: owner, status: "confirmed", realName: "Scoped Person"});
  try {
    await configRef.set({corePasses: {enabled: true, eventIds: [eid], userIds: [person]},
      smartArrival: {enabled: true, eventIds: [eid], userIds: [person]}, appleDelivery: {enabled: false}, googleDelivery: {enabled: false}});
    const issued = await arrival.issuePass(db, person, {kind: "event", eventId: eid});
    await assert.rejects(() => arrival.issuePass(db, outsider, {kind: "event", eventId: eid}));
    await assert.rejects(() => arrival.issuePass(db, uid, {kind: "event", eventId}));
    const sid = await arrival.ensureSession(db, {...event(), id: eid}, person, position());
    await assert.rejects(() => arrival.ensureSession(db, {...event(), id: eid}, outsider, position()));
    await configRef.update({"corePasses.enabled": false, "smartArrival.enabled": false});
    await assert.rejects(() => arrival.issuePass(db, person, {kind: "event", eventId: eid}));
    await assert.rejects(() => arrival.ensureSession(db, {...event(), id: eid}, person, position()));
    const receipt = await v2.createSubmitCheckIn(sdk).run(request(staff, {eventId: eid, sessionId: sid,
      credential: {type: "attendance_pass", value: issued.qrData}, answers: [], idempotencyKey: crypto.randomUUID()}));
    assert.equal(receipt.created, true);
    assert.equal((await db.collection("Attendance").doc(receipt.attendanceId).get()).exists, true);
  } finally { await configRef.set(original); }
});

test("offline replay evaluates historical pause and revocation at reconciliation", async () => {
  const eid = `pause-offline-${suffix}`, people = [0, 1, 2].map((n) => `pause-person-${n}-${suffix}`);
  await db.collection("Events").doc(eid).set({...event(), id: eid});
  const passes = [];
  for (const person of people) {
    await db.collection("RegisterAttendance").doc(`pause-reg-${person}`).set({eventId: eid, customerUid: person, status: "confirmed", realName: "Offline Person"});
    passes.push(await arrival.issuePass(db, person, {kind: "event", eventId: eid}));
  }
  const sid = (await v2.createStartCheckInSession(sdk).run(request(staff, {eventId: eid}))).sessionId;
  const kit = await arrival.offlineKit(db, eid, sid, staff);
  const beforePause = Date.now() - 10000;
  await db.collection("check_in_event_state").doc(eid).update({transitions: [
    {status: "open", atMs: beforePause - 1000}, {status: "paused", atMs: beforePause + 1000}, {status: "open", atMs: beforePause + 3000},
  ]});
  const scan = (index, observed) => v2.createSubmitCheckIn(sdk).run(request(staff, {eventId: eid, sessionId: sid,
    offline: true, offlineKitRevision: kit.revision, observedAt: new Date(observed).toISOString(),
    credential: {type: "attendance_pass", value: passes[index].qrData}, answers: [], idempotencyKey: crypto.randomUUID()}));
  assert.equal((await scan(0, beforePause)).created, true);
  await assert.rejects(() => scan(1, beforePause + 2000));
  await db.collection("AttendancePasses").doc(passes[2].id).update({status: "revoked"});
  await assert.rejects(() => scan(2, beforePause));
  const freshKit = await arrival.offlineKit(db, eid, sid, staff);
  assert.ok(freshKit.checkedInAdmissions.includes(passes[0].admissionKey));
  assert.equal(freshKit.passes[passes[2].id], undefined);
});

test("duplicate offline attempts stay conflicts after checkout and never become reentry", async () => {
  const eid = `replay-${suffix}`, person = `replay-person-${suffix}`;
  await db.collection("Events").doc(eid).set({...event(), id: eid,
    checkInPolicy: {...event().checkInPolicy, checkoutEnabled: true}});
  await db.collection("RegisterAttendance").doc(`replay-reg-${suffix}`).set({eventId: eid, customerUid: person, status: "confirmed", realName: "Replay Person"});
  const epass = await arrival.issuePass(db, person, {kind: "event", eventId: eid});
  const sid = (await v2.createStartCheckInSession(sdk).run(request(staff, {eventId: eid}))).sessionId;
  const kit = await arrival.offlineKit(db, eid, sid, staff);
  const handler = v2.createSubmitCheckIn(sdk);
  const replayKey = crypto.randomUUID();
  const scan = (idempotencyKey) => handler.run(request(staff, {eventId: eid, sessionId: sid,
    offline: true, offlineKitRevision: kit.revision, observedAt: new Date().toISOString(),
    credential: {type: "attendance_pass", value: epass.qrData}, answers: [], idempotencyKey}));
  const first = await scan(crypto.randomUUID());
  assert.equal((await scan(replayKey)).conflict, true);
  await handler.run(request(staff, {eventId: eid, sessionId: sid,
    credential: {type: "checkout", attendanceId: first.attendanceId}, idempotencyKey: crypto.randomUUID()}));
  assert.equal((await scan(replayKey)).conflict, true);
  const stored = (await db.collection("Attendance").doc(first.attendanceId).get()).data();
  assert.equal(stored.status, "checked_out");
  assert.equal(stored.reentryCount, 0);
  await scan(crypto.randomUUID());
  assert.equal((await db.collection("Attendance").doc(first.attendanceId).get()).data().reentryCount, 1);
});

test("staff override preserves entitlement identity and cannot admit an unpaid ticket", async () => {
  const eid = `override-${suffix}`, person = `override-person-${suffix}`;
  await db.collection("Events").doc(eid).set({...event(), id: eid});
  await db.collection("RegisterAttendance").doc(`override-reg-${suffix}`).set({eventId: eid, customerUid: person, status: "confirmed", realName: "Override Person"});
  const sid = (await v2.createStartCheckInSession(sdk).run(request(staff, {eventId: eid}))).sessionId;
  const handler = v2.createSubmitCheckIn(sdk);
  const scan = (overrideReason) => handler.run(request(staff, {eventId: eid, sessionId: sid,
    credential: {type: "staff_roster", attendeeId: person, overrideReason}, answers: [], idempotencyKey: crypto.randomUUID()}));
  const first = await scan("");
  assert.equal((await scan("Verified by organizer")).attendanceId, first.attendanceId);
  await db.collection("Tickets").doc(`override-ticket-${suffix}`).set({eventId: eid, customerUid: person, price: 10, paymentStatus: "unpaid"});
  await assert.rejects(() => scan("Verified by organizer"));
});

test("manual admission merges structured registration answers with required legacy door answers", async () => {
  const eid = `structured-answers-${suffix}`, person = `structured-person-${suffix}`, rid = `structured-reg-${suffix}`;
  const answer = {questionId: "access", prompt: "Accessibility needs", type: "short_text", version: 2, answer: "Step-free"};
  await db.collection("Events").doc(eid).set({...event(), id: eid});
  await db.collection("RegisterAttendance").doc(rid).set({eventId: eid, customerUid: person, status: "confirmed", answers: [answer]});
  await db.doc(`Events/${eid}/EventQuestions/access`).set({prompt: "Accessibility needs", timing: "registration", required: true});
  await db.doc(`Events/${eid}/EventQuestions/door`).set({questionTitle: "Door code", required: true});
  const sid = (await v2.createStartCheckInSession(sdk).run(request(staff, {eventId: eid}))).sessionId;
  const input = {eventId: eid, sessionId: sid, credential: {type: "staff_roster", attendeeId: person, registrationId: rid},
    answers: ["Door code--ans--Ready"], idempotencyKey: crypto.randomUUID()};
  const handler = v2.createSubmitCheckIn(sdk);
  const receipt = await handler.run(request(staff, input));
  const replay = await handler.run(request(staff, input));
  assert.equal(replay.attendanceId, receipt.attendanceId);
  assert.equal(replay.created, false);
  assert.deepEqual((await db.doc(`Attendance/${receipt.attendanceId}`).get()).get("answers"), [answer, "Door code--ans--Ready"]);
});

test("closing an older session preserves the newer session and legacy issuance uses stable passes", async () => {
  const eid = `old-session-${suffix}`, person = `old-person-${suffix}`;
  await db.collection("Events").doc(eid).set({...event(), id: eid});
  await db.collection("RegisterAttendance").doc(`old-reg-${suffix}`).set({eventId: eid, customerUid: person, status: "confirmed", realName: "Session Person"});
  const start = () => v2.createStartCheckInSession(sdk).run(request(staff, {eventId: eid}));
  const end = (sessionId) => v2.createEndCheckInSession(sdk).run(request(staff, {sessionId}));
  const old = (await start()).sessionId;
  await end(old);
  const current = (await start()).sessionId;
  await end(old);
  assert.equal((await db.collection("check_in_event_state").doc(eid).get()).data().activeSessionId, current);
  const first = await v2.createGetPersonalPass(sdk).run(request(person, {eventId: eid}));
  const second = await arrival.issuePass(db, person, {kind: "event", eventId: eid});
  assert.equal(first.qrData, second.qrData);
  assert.equal(first.appleWalletUrl, null);
  assert.equal(first.googleWalletUrl, null);
});


test("offline kit excludes active tickets with cancelled registrations and reuses confirmed answers", async () => {
  const eid = `kit-entitlement-${suffix}`;
  await db.collection("Events").doc(eid).set({...event(), id: eid});
  for (const status of ["confirmed", "cancelled", "pending", "waitlisted"]) {
    const owner = `kit-${status}-${suffix}`;
    await db.collection("RegisterAttendance").doc(owner).set({eventId: eid, customerUid: owner, status,
      realName: status, answers: ["Diet--ans--Vegetarian"]});
    await db.collection("Tickets").doc(owner).set({eventId: eid, customerUid: owner, registrationId: owner, status: "active", price: 0,
      ticketCode: `code-${status}`, isUsed: false});
  }
  const sid = (await v2.createStartCheckInSession(sdk).run(request(staff, {eventId: eid}))).sessionId;
  const kit = await arrival.offlineKit(db, eid, sid, staff);
  assert.deepEqual(kit.tickets.map(ticket => ticket.ticketCode), ["code-confirmed"]);
  assert.deepEqual(kit.tickets[0].answers, ["Diet--ans--Vegetarian"]);
  assert.deepEqual(kit.rosterAnswers[`kit-confirmed-${suffix}`], ["Diet--ans--Vegetarian"]);
  assert.equal(kit.rosterIds.includes(`kit-cancelled-${suffix}`), false);
});


test("routine issuance and refresh cannot undo explicit revocation", async () => {
  const eid = `sticky-revocation-${suffix}`, owner = `sticky-owner-${suffix}`;
  await db.collection("Events").doc(eid).set({...event(), id: eid});
  await db.collection("RegisterAttendance").doc(owner).set({eventId: eid, customerUid: owner, status: "confirmed", realName: "Revoked"});
  const issued = await arrival.issuePass(db, owner, {kind: "event", eventId: eid});
  await db.collection("AttendancePasses").doc(issued.id).update({status: "revoked", revocationReason: "manual"});
  await assert.rejects(() => arrival.issuePass(db, owner, {kind: "event", eventId: eid}), /revoked/);
  await assert.rejects(() => arrival.issuePass(db, owner, {kind: "event", eventId: eid, replace: true}), /revoked/);
  const refreshed = await require("../attendance/wallet").refreshRecord(db, issued);
  assert.equal(refreshed.status, "revoked");
  assert.equal(refreshed.credentialVersion, issued.credentialVersion);
  await assert.rejects(() => arrival.resolvePass(db, issued.qrData));
});


test("explicit admission pair rejects cross-link selection and supports legacy userId", async () => {
  const eid = `pair-${suffix}`; const person = `pair-owner-${suffix}`;
  const fixture = {...event(), id: eid};
  await db.collection("Events").doc(eid).set(fixture);
  for (const name of ["a", "b"]) {
    await db.collection("RegisterAttendance").doc(`pair-reg-${name}-${suffix}`).set({eventId: eid, userId: person, status: "confirmed", ticketId: `pair-ticket-${name}-${suffix}`});
    await db.collection("Tickets").doc(`pair-ticket-${name}-${suffix}`).set({eventId: eid, userId: person, registrationId: `pair-reg-${name}-${suffix}`, price: 0});
  }
  await assert.rejects(arrival.entitlement(db, db, fixture, person), (error) => error.details.admissions.length === 2);
  await assert.rejects(arrival.entitlement(db, db, fixture, person, {registrationId: `pair-reg-a-${suffix}`, ticketId: `pair-ticket-b-${suffix}`}), {code: "permission-denied"});
  const result = await arrival.entitlement(db, db, fixture, person, {ticketId: `pair-ticket-b-${suffix}`});
  assert.equal(result.registration.id, `pair-reg-b-${suffix}`);
  assert.equal(result.ticket.id, `pair-ticket-b-${suffix}`);
});
