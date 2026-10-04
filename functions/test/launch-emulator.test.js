"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw Error("Local Firestore emulator required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
process.env.GUEST_CONTACT_KMS_KEY_NAME = "emulator";
process.env.GUEST_CONTACT_HMAC_KEY = "local-launch-fixture-only";
const admin = require("../firebase-admin-compat");
const db = admin.firestore();
const {createStartPublicRegistrationV3} = require("../events/registration-v3");
const {createGetPublicRegistrationStatusV2, createCancelPublicRegistrationV1} = require("../public-web/accountless");
const {createLaunchOperations} = require("../events/launch-operations");
const {archiveAttendance, archiveBeforeDeletion, createAttendanceHistory} = require("../account/attendance-history");
const suffix = crypto.randomUUID();
const eventId = `launch-${suffix}`;
const owner = `owner-${suffix}`;
const guest = `guest-${suffix}`;
const request = (uid, data, anonymous = false) => ({auth: {uid, token: {firebase: {sign_in_provider: anonymous ? "anonymous" : "password"}}}, data});
const start = createStartPublicRegistrationV3(admin);
const status = createGetPublicRegistrationStatusV2(admin);
const operations = createLaunchOperations(admin);
const history = createAttendanceHistory(admin);
const input = {eventId, fullName: "Original Attendee", email: `test-${suffix}@example.test`, idempotencyKey: "same-submission-1", answers: {diet: "Vegetarian"}};
let registration;
test.before(async () => {
  await db.collection("AppConfig").doc("publicWeb").set({accountlessRegistrationEnabled: true});
  await db.collection("Events").doc(eventId).set({title: "Launch test", customerUid: owner, private: false,
    status: "active", selectedDateTime: new Date(Date.now() + 86400000), eventDurationMinutes: 90,
    eventTimeZone: "America/New_York", eventRevision: 1, ticketsEnabled: true, ticketPrice: 0,
    confirmedRegistrationCount: 0, issuedTickets: 0, maxTickets: 1, registrationPolicy: {mode: "free_ticket", capacity: 1, waitlistEnabled: true}});
  await db.collection("Events").doc(eventId).collection("EventQuestions").doc("diet").set({id: "diet", timing: "registration", prompt: "Diet", type: "short_text", required: true});
});
test.after(async () => { await db.terminate(); });
test("actual roster handlers invalidate current parents and ignore delayed deleted-parent deliveries", async () => {
  const deletedId = `roster-deleted-${suffix}`, liveId = `roster-current-${suffix}`;
  const sourceId = `roster-source-${suffix}`, uid = `roster-person-${suffix}`;
  const event = db.doc(`Events/${deletedId}`), state = db.doc(`EventRosters/${deletedId}`);
  const liveEvent = db.doc(`Events/${liveId}`), liveState = db.doc(`EventRosters/${liveId}`);
  const registration = db.doc(`RegisterAttendance/${sourceId}`), ticket = db.doc(`Tickets/${sourceId}`);
  const historical = db.doc(`HistoricalAttendance/${sourceId}`);
  const refs = [event, state, liveEvent, liveState, registration, ticket, historical];
  try {
    await event.set({customerUid: uid, status: "active"});
    await state.set({revision: 3, ready: true, generation: "retained", count: 2});
    await operations.refreshRosterEvent.run({params: {id: deletedId}});
    assert.deepEqual((await state.get()).data(), {revision: 4, ready: false, generation: "retained", count: 2});
    await registration.set({eventId: deletedId, customerUid: uid, guestId: uid});
    await ticket.set({eventId: deletedId, customerUid: uid, guestId: uid});
    await historical.set({eventId: deletedId});
    const before = await registration.get();
    await Promise.all([event.delete(), state.delete()]);
    await operations.refreshRosterEvent.run({params: {id: deletedId}});
    for (const name of ["RegisterAttendance", "Attendance", "Tickets", "HistoricalAttendance"]) {
      await operations[`refreshRoster${name}`].run({params: {id: sourceId}, data: {before, after: before}});
    }
    await operations.refreshRosterCorrection.run({params: {id: sourceId, correction: "late"}});
    await operations.refreshRosterCustomers.run({params: {id: uid}});
    await operations.refreshRosterGuestAttendees.run({params: {id: uid}});
    assert.equal((await state.get()).exists, false);
    // A moved source must still invalidate its surviving parent.
    await liveEvent.set({customerUid: uid, status: "cancelled"});
    await registration.update({eventId: liveId});
    const after = await registration.get();
    await operations.refreshRosterRegisterAttendance.run({params: {id: sourceId}, data: {before, after}});
    assert.equal((await state.get()).exists, false);
    assert.deepEqual((await liveState.get()).data(), {revision: 1, ready: false});
  } finally {
    await Promise.all(refs.map((ref) => ref.delete()));
  }
});
for (const replacement of [false, true]) test(`roster publication fences concurrent parent ${replacement ? "replacement" : "deletion"}`, async () => {
  const id = `roster-publish-${replacement ? "replace" : "delete"}-${suffix}`;
  const event = db.doc(`Events/${id}`), state = db.doc(`EventRosters/${id}`);
  let intercepted = false;
  try {
    await event.set({customerUid: owner, status: "active", eventRevision: 1});
    const proxy = new Proxy(db, {get(target, property) {
      if (property === "runTransaction") return async (...args) => {
        if (!intercepted) {
          intercepted = true;
          assert.equal((await state.collection("generations").get()).size, 1,
              "The race must occur after materialization and before final publication");
          await event.delete();
          if (replacement) await event.set({customerUid: `replacement-${owner}`, status: "active", eventRevision: 1});
        }
        return target.runTransaction(...args);
      };
      const value = target[property];
      return typeof value === "function" ? value.bind(target) : value;
    }});
    const firestore = () => proxy;
    firestore.FieldValue = admin.firestore.FieldValue;
    await assert.rejects(createLaunchOperations({firestore}).listEventRosterV2.run(request(owner, {eventId: id})),
        {code: "unavailable"});
    assert.equal(intercepted, true);
    assert.equal((await state.get()).exists, false);
    assert.equal((await state.collection("generations").get()).empty, true);
    const current = await event.get();
    assert.equal(current.exists, replacement);
    if (replacement) assert.equal(current.get("customerUid"), `replacement-${owner}`);
  } finally {
    await db.recursiveDelete(state);
    await event.delete();
  }
});

test("concurrent free publications consume the current final allowance only once", async () => {
  const {consumePublicationAllowance} = require("../events/wizard");
  const uid = `quota-${suffix}`;
  const ref = db.collection("Customers").doc(uid);
  await ref.set({uid, eventsCreated: 0});
  const stale = await ref.get();
  await ref.update({eventsCreated: 4});
  const results = await Promise.allSettled([1, 2].map(() => db.runTransaction((tx) =>
    consumePublicationAllowance(tx, db, uid, "free", stale))));
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.find((result) => result.status === "rejected").reason.code, "resource-exhausted");
  assert.equal((await ref.get()).get("eventsCreated"), 5);
  await ref.set({uid});
  await assert.rejects(db.runTransaction((tx) => consumePublicationAllowance(tx, db, uid, "free", stale)),
      {code: "failed-precondition"});
  assert.equal((await ref.get()).get("eventsCreated"), undefined);
  await ref.set({uid, eventsCreated: 0});
  await db.collection("subscriptions").doc(uid).set({tier: "premium", status: "cancelled"});
  await assert.rejects(db.runTransaction((tx) => consumePublicationAllowance(tx, db, uid, "premium", stale)),
      {code: "aborted"});
  assert.equal((await ref.get()).get("eventsCreated"), 0);
});

test("guest retries are identical, reject changed information, and consume one place", async () => {
  const [a, b] = await Promise.all([start.run(request(guest, input, true)), start.run(request(guest, input, true))]);
  assert.equal(a.registrationId, b.registrationId); assert.equal(a.ticketId, b.ticketId); assert.equal(a.claimToken, b.claimToken);
  registration = a;
  assert.equal((await db.collection("Events").doc(eventId).get()).get("issuedTickets"), 1);
  await assert.rejects(start.run(request(guest, {...input, fullName: "Changed"}, true)), {code: "already-exists"});
  const messages = await db.collection("OutboundMessages").where("registrationId", "==", a.registrationId).get();
  assert.equal(messages.size, 1);
});
test("capacity, required questions and owner-only live status", async () => {
  await assert.rejects(start.run(request(`other-${suffix}`, {...input, email: "missing@example.test", answers: {}, idempotencyKey: "missing-answers"}, true)));
  const other = await start.run(request(`other-${suffix}`, {...input, email: `other-${suffix}@example.test`, idempotencyKey: "waitlisted-request"}, true));
  assert.equal(other.status, "waitlisted"); assert.equal(other.ticketId, null);
  await assert.rejects(status.run(request(owner, {flowId: registration.flowId})), {code: "not-found"});
  await createCancelPublicRegistrationV1(admin).run(request(guest, {registrationId: registration.registrationId}, true));
  const current = await status.run(request(guest, {flowId: registration.flowId}, true));
  assert.equal(current.status, "cancelled"); assert.equal(current.ticketId, null);
  assert.equal((await db.collection("Events").doc(eventId).get()).get("confirmedRegistrationCount"), 0);
});
test("archive only real attendance, audit identity access and strip it during deletion", async () => {
  const attendance = {eventId, customerUid: guest, realName: "Original Attendee", checkedInAt: new Date(), verificationSource: "staff_roster"};
  await db.collection("Attendance").doc(`stamp-${suffix}`).set(attendance);
  const id = await archiveAttendance(db, `stamp-${suffix}`, attendance);
  assert.equal(await archiveAttendance(db, "unused", {eventId, customerUid: guest}), null);
  await assert.rejects(history.getAttendanceHistoryIdentityV1.run(request(guest, {eventId, historyId: id, reason: "Investigate attendance"})), {code: "permission-denied"});
  const identity = await history.getAttendanceHistoryIdentityV1.run(request(owner, {eventId, historyId: id, reason: "Investigate attendance"}));
  assert.equal(identity.identity.recordedName, "Original Attendee");
  await db.collection("account_deletion_jobs").doc(guest).set({status: "running"});
  assert.equal(await archiveBeforeDeletion(db, guest), 1);
  assert.equal((await db.collection("HistoricalAttendance").doc(id).get()).exists, true);
  assert.equal((await db.collection("AttendanceHistoryIdentities").doc(id).get()).exists, false);
  await archiveAttendance(db, `stamp-${suffix}`, attendance);
  assert.equal((await db.collection("AttendanceHistoryIdentities").doc(id).get()).exists, false);
});
test("door staff cannot communicate, export contacts, delete, or cancel; manager cannot delete records", async () => {
  const staff = `staff-${suffix}`;
  await db.collection("Events").doc(eventId).update({checkInStaff: [staff]});
  for (const operation of [operations.previewEventAnnouncementV1, operations.createEventExportV2, operations.cancelEventV1, operations.deleteEmptyEventV1]) {
    await assert.rejects(operation.run(request(staff, {eventId})), {code: "permission-denied"});
  }
  await assert.rejects(operations.deleteEmptyEventV1.run(request(owner, {eventId})), {code: "failed-precondition"});
  const stale = await operations.previewEventCancellationV1.run(request(owner, {eventId}));
  await db.collection("Events").doc(eventId).update({eventRevision: 2});
  await assert.rejects(operations.cancelEventV1.run(request(owner, {eventId, previewToken: stale.previewToken, reason: "Weather"})), {code: "aborted"});
  const preview = await operations.previewEventCancellationV1.run(request(owner, {eventId}));
  await operations.cancelEventV1.run(request(owner, {eventId, previewToken: preview.previewToken, reason: "Weather"}));
  assert.equal((await db.collection("Events").doc(eventId).get()).get("status"), "cancelled");
  assert.equal((await db.collection("RegisterAttendance").doc(registration.registrationId).get()).exists, true);
});

test("complete roster pagination and search include records beyond 500", async () => {
  const largeEvent = `large-${suffix}`;
  await db.collection("Events").doc(largeEvent).set({customerUid: owner, selectedDateTime: new Date(), eventDurationMinutes: 90});
  for (let offset = 0; offset < 620; offset += 300) {
    const batch = db.batch();
    for (let index = offset; index < Math.min(offset + 300, 620); index++) {
      batch.set(db.collection("RegisterAttendance").doc(`large-${suffix}-${index}`), {eventId: largeEvent, customerUid: `large-person-${suffix}-${index}`,
        realName: index === 619 ? "Zebra Last" : "Repeated Name", status: "confirmed"});
    }
    await batch.commit();
  }
  let cursor; const ids = new Set();
  do {
    const page = await operations.listEventRosterV2.run(request(owner, {eventId: largeEvent, cursor, pageSize: 100}));
    page.rows.forEach((row) => ids.add(row.id)); cursor = page.nextCursor;
    assert.equal(page.summary.confirmed, 620);
  } while (cursor);
  assert.equal(ids.size, 620);
  const search = await operations.listEventRosterV2.run(request(owner, {eventId: largeEvent, query: "zebra"}));
  assert.equal(search.rows.length, 1); assert.equal(search.rows[0].name, "Zebra Last");
  const first = await operations.listEventRosterV2.run(request(owner, {eventId: largeEvent, pageSize: 100}));
  await db.collection("EventRosters").doc(largeEvent).update({ready: false});
  const continued = await operations.listEventRosterV2.run(request(owner, {eventId: largeEvent, cursor: first.nextCursor, pageSize: 100}));
  assert.equal(continued.newerDataAvailable, true);
  assert.equal(continued.summary.confirmed, 620);
  assert.equal(continued.rows.some((row) => first.rows.some((previous) => previous.id === row.id)), false);
  const cursorParts = first.nextCursor.split(".");
  const payload = JSON.parse(Buffer.from(cursorParts[1], "base64url").toString());
  payload.expiresAt += 86400000;
  const forged = `${cursorParts[0]}.${Buffer.from(JSON.stringify(payload)).toString("base64url")}.${cursorParts[2]}`;
  await assert.rejects(operations.listEventRosterV2.run(request(owner, {eventId: largeEvent, cursor: forged})), {code: "invalid-argument"});
  await db.collection("account_deletion_jobs").doc(continued.rows[0].uid).set({status: "running"});
  await assert.rejects(operations.listEventRosterV2.run(request(owner, {eventId: largeEvent, cursor: first.nextCursor, pageSize: 100})), {code: "aborted"});
});

test("archive failure prevents destructive cleanup and a retry resumes safely", async () => {
  const uid = `delete-${suffix}`;
  await db.collection("Customers").doc(uid).set({name: "Delete fixture"});
  await db.collection("ProfileReadLimits").doc(uid).set({buckets: {read: {window: 1, count: 2}}});
  await db.collection("Tickets").doc(`other-admission-${suffix}`).set({eventId, purchaserUid: uid, customerUid: "another-attendee", purchaserEmail: "delete@example.test", status: "confirmed"});
  await db.collection("GuestAttendees").doc(uid).set({ownerUid: uid});
  await db.collection("GuestEventEmailClaims").doc(uid).set({guestId: uid});
  await db.collection("Attendance").doc(uid).set({eventId, customerUid: uid, realName: "Recorded fixture", checkedInAt: new Date()});
  const {runAccountDeletion} = require("../account/deletion");
  let authDeleted = false;
  const auth = {deleteUser: async () => { authDeleted = true; }};
  const bucket = {getFiles: async () => [[]], file: () => ({delete: async () => {}})};
  let transactions = 0;
  const failingDb = {collection: (name) => db.collection(name), collectionGroup: (name) => db.collectionGroup(name), runTransaction: async (work) => { if (transactions++ === 1) throw Error("archive unavailable"); return db.runTransaction(work); }};
  await assert.rejects(runAccountDeletion({uid, db: failingDb, auth, bucket}), /archive unavailable/);
  assert.equal(authDeleted, false);
  assert.equal((await db.collection("Customers").doc(uid).get()).exists, true);
  assert.equal((await db.collection("Attendance").doc(uid).get()).exists, true);
  const result = await runAccountDeletion({uid, db, auth, bucket});
  assert.equal(result.status, "complete"); assert.equal(authDeleted, true);
  assert.equal((await db.collection("Customers").doc(uid).get()).exists, false);
  assert.equal((await db.collection("ProfileReadLimits").doc(uid).get()).exists, false);
  const otherAdmission = await db.collection("Tickets").doc(`other-admission-${suffix}`).get();
  assert.equal(otherAdmission.get("customerUid"), "another-attendee");
  assert.equal(otherAdmission.get("purchaserUid"), undefined);
  assert.equal((await db.collection("GuestEventEmailClaims").doc(uid).get()).exists, false);
  const {key} = require("../events/roster");
  assert.equal((await db.collection("HistoricalAttendance").doc(key(uid)).get()).exists, true);
});

test("announcement retries reuse one job and cannot substitute an unreviewed audience", async () => {
  const event = `announcement-${suffix}`;
  await db.collection("Events").doc(event).set({customerUid: owner, title: "Announcement fixture"});
  const preview = await operations.previewEventAnnouncementV1.run(request(owner, {eventId: event, title: "Update", body: "Fixture announcement only", audience: "confirmed"}));
  const a = await operations.sendEventAnnouncementV1.run(request(owner, {eventId: event, previewToken: preview.previewToken}));
  const b = await operations.sendEventAnnouncementV1.run(request(owner, {eventId: event, previewToken: preview.previewToken, audience: "pending"}));
  assert.equal(a.announcementId, b.announcementId);
  assert.equal((await db.collection("EventAnnouncements").doc(a.announcementId).get()).get("audience"), "confirmed");
});


test("edit drafts cannot target another organization or change their authorized source", async () => {
  const wizard = require("../events/wizard").createEventWizardFunctions(admin);
  const org = `org-${suffix}`;
  await db.collection("Organizations").doc(org).set({createdBy: owner, allowMemberEventCreation: true});
  const foreign = `foreign-${suffix}`;
  await db.collection("Events").doc(foreign).set({customerUid: "unrelated-owner", organizationId: "unrelated-org", eventRevision: 0});
  await assert.rejects(wizard.saveEventDraftV1.run(request(owner, {mode: "edit", sourceEventId: foreign, formData: {organizationId: org}})), {code: "permission-denied"});
  const saved = await wizard.saveEventDraftV1.run(request(owner, {mode: "edit", sourceEventId: eventId, formData: {}}));
  await assert.rejects(wizard.saveEventDraftV1.run(request(owner, {draftId: saved.draftId, expectedRevision: saved.revision, mode: "edit", sourceEventId: foreign, formData: {}})), {code: "permission-denied"});
  assert.equal((await require("../events/wizard").groupAccess(db, "absent-member", org)).allowed, false);
});

test("approval preserves capacity and retries do not issue duplicate tickets", async () => {
  const wizard = require("../events/wizard").createEventWizardFunctions(admin);
  const id = `approval-${suffix}`; const reg = `approval-reg-${suffix}`;
  await db.collection("Events").doc(id).set({customerUid: owner, status: "active", selectedDateTime: new Date(Date.now() + 86400000), eventDurationMinutes: 90, maxTickets: 1, confirmedRegistrationCount: 1, registrationPolicy: {mode: "free_ticket", waitlistEnabled: false}});
  await db.collection("RegisterAttendance").doc(reg).set({eventId: id, customerUid: `applicant-${suffix}`, status: "pending"});
  const input = {eventId: id, registrationId: reg, decision: "approve", idempotencyKey: "decision-1"};
  await assert.rejects(wizard.decideEventRegistrationV1.run(request(owner, input)), {code: "resource-exhausted"});
  assert.equal((await db.collection("RegisterAttendance").doc(reg).get()).get("status"), "pending");
  await db.collection("Events").doc(id).update({confirmedRegistrationCount: 0});
  const first = await wizard.decideEventRegistrationV1.run(request(owner, input));
  const retry = await wizard.decideEventRegistrationV1.run(request(owner, input));
  assert.deepEqual(first, retry);
  assert.equal((await db.collection("Tickets").where("eventId", "==", id).get()).size, 1);
  await assert.rejects(wizard.decideEventRegistrationV1.run(request(owner, {...input, decision: "decline"})), {code: "already-exists"});
});

test("removed organization role invalidates a previously reviewed cancellation", async () => {
  const org = `removed-role-${suffix}`; const id = `role-event-${suffix}`; const manager = `manager-${suffix}`;
  await db.collection("Organizations").doc(org).set({createdBy: owner});
  const member = db.collection("Organizations").doc(org).collection("Members").doc(manager);
  await member.set({role: "admin", status: "approved"});
  await db.collection("Events").doc(id).set({customerUid: owner, organizationId: org, eventRevision: 1, title: "Role fixture"});
  const preview = await operations.previewEventCancellationV1.run(request(manager, {eventId: id}));
  await member.delete();
  await assert.rejects(operations.cancelEventV1.run(request(manager, {eventId: id, previewToken: preview.previewToken, reason: "Fixture change"})), {code: "permission-denied"});
});

test("export request identity conflicts when filters change", async () => {
  const input = {eventId, idempotencyKey: "export-fixture-1", query: ""};
  const first = await operations.createEventExportV2.run(request(owner, input));
  assert.deepEqual(await operations.createEventExportV2.run(request(owner, input)), first);
  await assert.rejects(operations.createEventExportV2.run(request(owner, {...input, query: "different"})), {code: "already-exists"});
});

test("worker leases serialize execution and terminal errors do not escape", async () => {
  const {runJob} = require("../events/jobs");
  const ref = db.collection("EventExportJobs").doc(`lease-${suffix}`);
  await ref.set({status: "queued"}); let calls = 0;
  const work = async (ref, heartbeat) => { calls++; await heartbeat(); await ref.update({status: "complete"}); };
  await Promise.all([runJob(db, ref, work), runJob(db, ref, work)]);
  assert.equal(calls, 1);
  await ref.set({status: "queued"});
  await runJob(db, ref, async () => { throw Object.assign(Error("No access"), {code: "permission-denied"}); });
  assert.equal((await ref.get()).get("status"), "failed");
});

test("published draft retries return their original result and reject changed scope", async () => {
  const {createEventWizardFunctions} = require("../events/wizard");
  const draftId = `published-${suffix}`;
  const publicationResult = {status: "scheduled", eventId, eventIds: [eventId], seriesId: null, occurrenceCount: 1};
  const publicationFingerprint = crypto.createHash("sha256").update(JSON.stringify([1, "this_occurrence", "", null])).digest("hex");
  await db.collection("EventDrafts").doc(draftId).set({ownerUid: owner, revision: 1, publishedAt: new Date(), publishedEventIds: [eventId], publicationFingerprint, publicationResult});
  const publish = createEventWizardFunctions(admin).publishEventDraftV1;
  assert.deepEqual(await publish.run(request(owner, {draftId, expectedDraftRevision: 1})), publicationResult);
  await assert.rejects(publish.run(request(owner, {draftId, expectedDraftRevision: 1, recurrenceScope: "entire_series"})), {code: "already-exists"});
});

test("export download signing never outlives retention and rejects invalid expiry", async () => {
  const eid = `export-expiry-${suffix}`;
  await db.collection("Events").doc(eid).set({customerUid: owner, title: "Export expiry"});
  const signed = [];
  const isolated = createLaunchOperations({firestore: admin.firestore, storage: () => ({bucket: () => ({file: () => ({
    getSignedUrl: async (options) => { signed.push(options); return ["https://example.test/fixture.csv"]; },
  })})})});
  for (const [scenario, expiry] of [["near", new Date(Date.now() + 60000)], ["normal", new Date(Date.now() + 3600000)],
    ["expired", new Date(Date.now() - 1000)], ["malformed", "invalid"], ["map", {toMillis: "invalid"}], ["missing", null]]) {
    const id = crypto.createHash("sha256").update(`${eid}-${scenario}`).digest("hex");
    await db.collection("EventExportJobs").doc(id).set({eventId: eid, actorUid: owner, status: "complete", expiresAt: expiry,
      path: `private-event-exports/${id}/fixture.csv`, subjectUids: [], rowCount: 1, generation: "fixture-generation"});
    const before = Date.now(); const count = signed.length;
    if (["near", "normal"].includes(scenario)) {
      const result = await isolated.getEventExportV2.run(request(owner, {eventId: eid, jobId: id}));
      assert.equal(result.status, "complete");
      const options = signed.at(-1);
      assert.equal(options.action, "read");
      if (scenario === "near") assert.equal(options.expires, expiry.getTime());
      else assert.ok(options.expires >= before + 5 * 60000 && options.expires <= Date.now() + 5 * 60000);
      assert.ok(options.expires <= expiry.getTime());
    } else {
      await assert.rejects(isolated.getEventExportV2.run(request(owner, {eventId: eid, jobId: id})), {code: "not-found"});
      assert.equal(signed.length, count);
    }
  }
});

test("export publication rechecks deletion after writing the private object", async () => {
  const eid = `export-race-${suffix}`; const attendee = `export-subject-${suffix}`;
  await db.collection("Events").doc(eid).set({customerUid: owner, title: "Export race", selectedDateTime: new Date(), eventDurationMinutes: 90, eventTimeZone: "UTC"});
  await db.collection("RegisterAttendance").doc(attendee).set({eventId: eid, customerUid: attendee, status: "confirmed", realName: "Fixture"});
  let removed = false;
  const isolated = createLaunchOperations({firestore: admin.firestore, storage: () => ({bucket: () => ({file: () => ({
    save: async () => db.collection("account_deletion_jobs").doc(attendee).set({status: "inventory"}),
    delete: async () => { removed = true; },
  })})})});
  const job = await isolated.createEventExportV2.run(request(owner, {eventId: eid, idempotencyKey: `export-race-${suffix}`}));
  const ref = db.collection("EventExportJobs").doc(job.jobId);
  await isolated.generateEventExport.run({data: {ref}});
  assert.equal((await ref.get()).get("status"), "failed");
  assert.equal((await ref.get()).get("path"), undefined);
  assert.equal(removed, true);
});


test("announcement and empty deletion reject roles removed after initial authorization", async () => {
  for (const action of ["announcement", "delete"]) {
    const id = `transaction-role-${action}-${suffix}`;
    const org = `transaction-org-${action}-${suffix}`;
    const manager = `transaction-manager-${action}-${suffix}`;
    const member = db.collection("Organizations").doc(org).collection("Members").doc(manager);
    await db.collection("Organizations").doc(org).set({createdBy: owner});
    await member.set({role: "admin", status: "approved"});
    await db.collection("Events").doc(id).set({customerUid: owner, organizationId: org});
    const previewId = `preview-${action}-${suffix}`;
    await db.collection("EventAnnouncementPreviews").doc(previewId).set({actorUid: manager, eventId: id, ready: true, count: 0, expiresAt: new Date(Date.now() + 60000)});
    let intercepted = false;
    const proxy = new Proxy(db, {get(target, property) {
      if (property === "runTransaction") return async (...args) => {
        intercepted = true;
        await member.delete();
        return target.runTransaction(...args);
      };
      const value = target[property];
      return typeof value === "function" ? value.bind(target) : value;
    }});
    const firestore = () => proxy;
    firestore.FieldValue = admin.firestore.FieldValue;
    const isolated = createLaunchOperations({firestore});
    const operation = action === "announcement" ? isolated.sendEventAnnouncementV1 : isolated.deleteEmptyEventV1;
    await assert.rejects(operation.run(request(manager, {eventId: id, previewToken: previewId})), {code: "permission-denied"});
    assert.equal(intercepted, true);
    assert.equal((await db.collection("Events").doc(id).get()).exists, true);
    assert.equal((await db.collection("EventAnnouncements").doc(previewId).get()).exists, false);
  }
});

test("admission recovery preserves legacy owners and event-aware paid eligibility", async () => {
  const id = `recovery-${suffix}`; const uid = `recovery-owner-${suffix}`;
  await db.collection("Events").doc(id).set({title: "Paid legacy event", ticketPrice: 10, selectedDateTime: new Date(Date.now() + 86400000), eventDurationMinutes: 90});
  for (const [ticket, isPaid] of [["paid", true], ["unpaid", false]]) {
    await db.collection("Tickets").doc(`${ticket}-${suffix}`).set({eventId: id, userId: uid, isPaid, ticketCode: ticket});
  }
  const result = await operations.listMyAdmissionsV1.run(request(uid, {}));
  assert.equal(result.admissions.length, 2);
  assert.equal(result.admissions.find((row) => row.ticketId === `paid-${suffix}`).status, "confirmed");
  assert.equal(result.admissions.find((row) => row.ticketId === `unpaid-${suffix}`).status, "pending");
  const recovered = await status.run(request(uid, {eventId: id}));
  assert.equal(recovered.admissions.length, 2);
  assert.equal(recovered.ticketId, null);
  assert.equal(recovered.ticketCode, null);
  const selected = await status.run(request(uid, {eventId: id, ticketId: `paid-${suffix}`}));
  assert.equal(selected.ticketId, `paid-${suffix}`);
  assert.equal(selected.ticketCode, "paid");
  const unpaid = await status.run(request(uid, {eventId: id, ticketId: `unpaid-${suffix}`}));
  assert.equal(unpaid.status, "pending");
  assert.equal(unpaid.ticketCode, null);
  assert.equal((await status.run(request("other-account", {eventId: id}))).status, "none");
});


test("legacy and V3 requests compete for one reconciled seat and cancellation releases it", async () => {
  const {createIssueFreeTicket} = require("../tickets/issuance");
  const legacy = createIssueFreeTicket();
  const id = `mixed-capacity-${suffix}`;
  const first = `legacy-buyer-${suffix}`; const second = `v3-buyer-${suffix}`;
  await db.collection("Events").doc(id).set({customerUid: owner, title: "Last seat", status: "active", ticketsEnabled: true, ticketPrice: 0,
    selectedDateTime: new Date(Date.now() + 86400000), eventDurationMinutes: 90,
    maxTickets: 1, issuedTickets: 0, confirmedRegistrationCount: 0,
    registrationPolicy: {mode: "free_ticket", capacity: 1, waitlistEnabled: false}});
  const results = await Promise.allSettled([
    legacy.run(request(first, {eventId: id})),
    start.run(request(second, {eventId: id, fullName: "Fixture", email: `${second}@example.test`, idempotencyKey: "mixed-last-place"})),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.find((result) => result.status === "rejected").reason.code, "resource-exhausted");
  const registrations = await db.collection("RegisterAttendance").where("eventId", "==", id).get();
  assert.equal(registrations.size, 1);
  const registration = registrations.docs[0];
  const ticket = await db.collection("Tickets").doc(registration.get("ticketId")).get();
  assert.equal(ticket.get("registrationId"), registration.id);
  assert.equal((await db.collection("Events").doc(id).get()).get("confirmedRegistrationCount"), 1);
  await createCancelPublicRegistrationV1(admin).run(request(registration.get("customerUid"), {registrationId: registration.id}));
  assert.equal((await db.collection("Events").doc(id).get()).get("confirmedRegistrationCount"), 0);
  assert.equal((await ticket.ref.get()).get("revoked"), true);
});


test("delayed lifecycle delivery preserves the intended revision instead of a later edit", async () => {
  const id = `revision-announcement-${suffix}`; const uid = `revision-subject-${suffix}`;
  const rid = `revision-reg-${suffix}`;
  const intended = {title: "Original title", selectedDateTime: new Date("2026-10-01T12:00:00Z"), eventDurationMinutes: 35, eventTimeZone: "UTC", eventRevision: 2};
  const job = db.collection("EventAnnouncements").doc(id);
  await db.collection("Events").doc(id).set({...intended, customerUid: owner, title: "Later title", selectedDateTime: new Date("2026-10-02T12:00:00Z"), eventRevision: 3});
  await db.collection("Customers").doc(uid).set({name: "Fixture", email: "revision@example.test"});
  await db.collection("RegisterAttendance").doc(rid).set({eventId: id, customerUid: uid, status: "confirmed"});
  await db.collection("EventAnnouncementPreviews").doc(id).collection("recipients").doc(rid).set({id: rid, uid, guestId: null, registrationId: rid, ticketId: null, status: "confirmed", identityType: "account"});
  await job.set({eventId: id, actorUid: owner, status: "queued", audience: "active", templateId: "event_rescheduled", recipientSource: id, title: "Update", body: "Original change", eventSnapshot: require("../events/lifecycle-snapshot").lifecycleSnapshot(intended)});
  await operations.deliverEventAnnouncement.run({data: {ref: job}});
  const messages = await db.collection("OutboundMessages").where("announcementId", "==", id).get();
  assert.equal(messages.size, 1);
  assert.equal(messages.docs[0].get("payload.eventRevision"), 2);
  assert.equal(messages.docs[0].get("payload.eventTitle"), "Original title");
  assert.equal(messages.docs[0].get("payload.eventStart").toDate().toISOString(), intended.selectedDateTime.toISOString());
  assert.equal(messages.docs[0].get("registrationId"), rid);
  await operations.deliverEventAnnouncement.run({data: {ref: job}});
  assert.equal((await db.collection("OutboundMessages").where("announcementId", "==", id).get()).size, 1);
});

test("export publication rejects contact changes and claimed guest deletion", async () => {
  for (const scenario of ["contact-change", "claimed-deletion"]) {
    const eid = `export-${scenario}-${suffix}`; const originalUid = `original-${scenario}-${suffix}`;
    const claimedUid = `claimed-${scenario}-${suffix}`; const guestId = `export-guest-${scenario}-${suffix}`;
    await db.collection("Events").doc(eid).set({customerUid: owner, title: "Contact race", selectedDateTime: new Date(), eventDurationMinutes: 60});
    await db.collection("RegisterAttendance").doc(eid).set({eventId: eid, customerUid: originalUid, guestId, status: "confirmed", realName: "Fixture"});
    const guestRef = db.collection("GuestAttendees").doc(guestId);
    await guestRef.set({ownerUid: claimedUid, claimedByUid: claimedUid, encryptedEmail: Buffer.from("original@example.test").toString("base64")});
    let saved = false; let removed = false;
    const isolated = createLaunchOperations({firestore: admin.firestore, storage: () => ({bucket: () => ({file: () => ({
      save: async () => {
        saved = true;
        if (scenario === "contact-change") await guestRef.update({encryptedEmail: Buffer.from("changed@example.test").toString("base64")});
        else await db.collection("account_deletion_jobs").doc(claimedUid).set({status: "running"});
      }, delete: async () => { removed = true; },
    })})})});
    const job = await isolated.createEventExportV2.run(request(owner, {eventId: eid, idempotencyKey: `export-${scenario}`}));
    const ref = db.collection("EventExportJobs").doc(job.jobId);
    await isolated.generateEventExport.run({data: {ref}});
    assert.equal(saved, true); assert.equal(removed, true);
    assert.equal((await ref.get()).get("status"), "failed");
    assert.equal((await ref.get()).get("path"), undefined);
  }
});

test("paged announcement commits count unavailable recipients exactly once", async () => {
  const id = `paged-announcement-${suffix}`;
  const job = db.collection("EventAnnouncements").doc(id);
  await db.collection("Events").doc(id).set({customerUid: owner, title: "Paged fixture"});
  for (let offset = 0; offset < 205; offset += 100) {
    const batch = db.batch();
    for (let i = offset; i < Math.min(offset + 100, 205); i++) {
      const uid = `paged-subject-${suffix}-${i}`; const rid = `paged-reg-${suffix}-${i}`;
      if (i) batch.set(db.collection("Customers").doc(uid), {name: "Fixture"});
      batch.set(db.collection("RegisterAttendance").doc(rid), {eventId: id, customerUid: uid, status: "confirmed"});
      batch.set(db.collection("EventAnnouncementPreviews").doc(id).collection("recipients").doc(String(i).padStart(4, "0")),
          {id: rid, uid, guestId: null, registrationId: rid, ticketId: null, status: "confirmed", identityType: "account"});
    }
    await batch.commit();
  }
  await job.set({eventId: id, actorUid: owner, status: "queued", audience: "confirmed", templateId: "event_announcement", recipientSource: id, title: "Fixture", body: "Fixture"});
  await operations.deliverEventAnnouncement.run({data: {ref: job}});
  const complete = await job.get();
  assert.equal(complete.get("status"), "complete");
  assert.equal(complete.get("count"), 205);
  assert.equal(complete.get("unreachable"), 1);
  assert.equal(complete.get("recipientCursor"), "0204");
  await operations.deliverEventAnnouncement.run({data: {ref: job}});
  assert.equal((await job.collection("recipients").count().get()).data().count, 205);
});

test("ambiguous export commit preserves the published private object", async () => {
  const eid = `ambiguous-export-${suffix}`;
  await db.collection("Events").doc(eid).set({customerUid: owner, title: "Ambiguous export", selectedDateTime: new Date(), eventDurationMinutes: 90});
  let jobRef; let injected = false; let deleted = false;
  const proxy = new Proxy(db, {get(target, property) {
    if (property === "runTransaction") return async (...args) => {
      const result = await target.runTransaction(...args);
      if (jobRef && !injected && (await jobRef.get()).get("status") === "complete") {
        injected = true;
        throw Error("ambiguous transport response");
      }
      return result;
    };
    const value = target[property];
    return typeof value === "function" ? value.bind(target) : value;
  }});
  const firestore = () => proxy; firestore.FieldValue = admin.firestore.FieldValue;
  const isolated = createLaunchOperations({firestore, storage: () => ({bucket: () => ({file: () => ({save: async () => {}, delete: async () => { deleted = true; }})})})});
  const job = await isolated.createEventExportV2.run(request(owner, {eventId: eid, idempotencyKey: "ambiguous-export-key"}));
  jobRef = db.collection("EventExportJobs").doc(job.jobId);
  await isolated.generateEventExport.run({data: {ref: jobRef}});
  assert.equal(injected, true);
  assert.equal((await jobRef.get()).get("status"), "complete");
  assert.equal(deleted, false);
});


test("cancellation follows forward links and blocks unresolved legacy admission", async () => {
  for (const linked of [true, false]) {
    const id = `cancel-link-${linked}-${suffix}`; const uid = `cancel-owner-${linked}-${suffix}`;
    const registrationId = `cancel-registration-${linked}-${suffix}`; const ticketId = `cancel-ticket-${linked}-${suffix}`;
    await db.collection("Events").doc(id).set({status: "active", selectedDateTime: new Date(Date.now() + 86400000), eventDurationMinutes: 90, ticketsEnabled: true, ticketPrice: 0, maxTickets: 1, issuedTickets: 1, confirmedRegistrationCount: 1});
    await db.collection("RegisterAttendance").doc(registrationId).set({eventId: id, customerUid: uid, status: "confirmed", ...(linked ? {ticketId} : {})});
    const ticket = db.collection("Tickets").doc(ticketId);
    await ticket.set({eventId: id, customerUid: uid, revoked: false, price: 0});
    const action = createCancelPublicRegistrationV1(admin).run(request(uid, {registrationId}));
    if (linked) await action;
    else await assert.rejects(action, {code: "failed-precondition"});
    assert.equal((await ticket.get()).get("revoked"), linked);
    assert.equal((await db.collection("Events").doc(id).get()).get("confirmedRegistrationCount"), linked ? 0 : 1);
  }
});
