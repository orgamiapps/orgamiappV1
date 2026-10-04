"use strict";

process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  TEMPLATE_CATALOG,
  generateOccurrences,
  normalizeDraftForm,
  occurrenceLimitForTier,
  sanitizedDuplicateForm,
  sanitizedTemplateForm,
  seriesOccurrenceStart,
  validatePublishable,
} = require("../events/wizard-core");
const {draftStoragePath, eventDocument, signInMethods} = require("../events/wizard");
const {normalizeAnswer} = require("../events/registration-v3");
const {memoryAdmin} = require("./helpers/community-memory");

function registrationDecisionFixture(status = "waitlisted", guest = false) {
  const admin = memoryAdmin({
    "Events/decision_event": {customerUid: "owner", status: "active",
      selectedDateTime: new Date(Date.now() + 86400000), eventDurationMinutes: 90,
      confirmedRegistrationCount: 1, issuedTickets: 1, reservedTickets: 0,
      registrationPolicy: {mode: "free_ticket", capacity: 1, waitlistEnabled: true}},
    "RegisterAttendance/decision_registration": {eventId: "decision_event",
      customerUid: "attendee", status, ...(guest ? {guestId: "decision_guest"} : {})},
    ...(guest ? {"GuestAttendees/decision_guest": {encryptedEmail: "fixture-ciphertext",
      maskedEmail: "f***@example.test", greetingName: "Fixture"}} : {}),
  });
  // Increment sentinels are used only by a deliberately discarded attempt below;
  // committed numeric counter behavior is covered by the real Firestore suite.
  admin.firestore.FieldValue.increment = (value) => ({increment: value});
  admin.firestore.Timestamp.now = () => new Date();
  const handler = require("../events/wizard").createEventWizardFunctions(admin).decideEventRegistrationV1;
  const request = (decision = "decline", uid = "owner") => ({
    auth: {uid, token: {firebase: {sign_in_provider: "password"}}},
    app: {appId: "offline-fixture"},
    data: {eventId: "decision_event", registrationId: "decision_registration", decision},
  });
  const rows = (collection) => [...admin.db.values.entries()].filter(([key]) => key.startsWith(`${collection}/`));
  return {admin, handler, request, rows};
}

for (const initialStatus of ["pending", "waitlisted"]) {
  test(`actual registration decision declines ${initialStatus} with legacy-key replay and no capacity mutation`, async () => {
    const {admin, handler, request, rows} = registrationDecisionFixture(initialStatus, true);
    const eventBefore = structuredClone(admin.db.values.get("Events/decision_event"));
    assert.deepEqual(await handler.run(request()), {status: "declined", ticketId: null});
    assert.deepEqual(await handler.run(request()), {status: "declined", ticketId: null});
    assert.deepEqual(admin.db.values.get("Events/decision_event"), eventBefore);
    assert.equal(admin.db.values.get("RegisterAttendance/decision_registration").status, "declined");
    assert.equal(rows("Tickets").length, 0);
    assert.equal(rows("RegistrationDecisions").length, 1);
    assert.equal(rows("GuestManageTokens").length, 1);
    assert.equal(rows("OutboundMessages").length, 1);
    assert.equal(rows("OutboundMessages")[0][1].templateId, "guest_registration_declined");
  });
}

test("registration decline does not admit unrelated or terminal states", async () => {
  for (const status of ["confirmed", "cancelled", "declined", "unknown", null]) {
    const {admin, handler, request, rows} = registrationDecisionFixture(status);
    await assert.rejects(handler.run(request()), {code: "failed-precondition"});
    assert.equal(admin.db.values.get("RegisterAttendance/decision_registration").status, status);
    assert.equal(rows("RegistrationDecisions").length, 0);
  }
});

test("registration decline preserves actor, event, deletion and idempotency boundaries", async () => {
  for (const mode of ["foreign_actor", "door_only", "actor_deleted", "attendee_deleted", "foreign_event", "cancelled_event", "missing_guest"]) {
    const {admin, handler, request, rows} = registrationDecisionFixture("waitlisted", mode === "missing_guest");
    const input = request();
    if (mode === "foreign_actor" || mode === "door_only") input.auth.uid = "other";
    if (mode === "door_only") admin.db.values.get("Events/decision_event").checkInStaff = ["other"];
    if (mode === "actor_deleted") admin.db.values.set("account_deletion_jobs/owner", {status: "complete"});
    if (mode === "attendee_deleted") admin.db.values.set("account_deletion_jobs/attendee", {status: "complete"});
    if (mode === "foreign_event") admin.db.values.get("RegisterAttendance/decision_registration").eventId = "other_event";
    if (mode === "cancelled_event") admin.db.values.get("Events/decision_event").status = "cancelled";
    if (mode === "missing_guest") admin.db.values.delete("GuestAttendees/decision_guest");
    await assert.rejects(handler.run(input), {code: ["foreign_actor", "door_only", "actor_deleted"].includes(mode) ? "permission-denied" : "failed-precondition"});
    assert.equal(rows("RegistrationDecisions").length, 0);
    assert.equal(rows("Tickets").length, 0);
  }
  const {handler, request} = registrationDecisionFixture();
  const input = request(); input.data.idempotencyKey = "explicit-key";
  await handler.run(input);
  await assert.rejects(handler.run({...input, data: {...input.data, decision: "promote"}}), {code: "already-exists"});
  await assert.rejects(handler.run({...input, auth: {...input.auth, uid: "other"}}), {code: "permission-denied"});
});

test("approval and promotion keep their distinct source states and full-capacity behavior", async () => {
  const pending = registrationDecisionFixture("pending");
  assert.deepEqual(await pending.handler.run(pending.request("approve")), {status: "waitlisted", ticketId: null});
  assert.equal(pending.rows("Tickets").length, 0);
  await assert.rejects(pending.handler.run(pending.request("promote")), {code: "resource-exhausted"});
  const newApproval = pending.request("approve");
  newApproval.data.idempotencyKey = "new-approval";
  await assert.rejects(pending.handler.run(newApproval), {code: "failed-precondition"});
});

function discardFirstDecisionAttempt(admin, mutateAfterDiscard) {
  const original = admin.db.runTransaction.bind(admin.db);
  const discarded = new Error("discarded test transaction");
  let attempts = 0;
  admin.db.runTransaction = async (callback) => {
    if (attempts++ === 0) {
      await assert.rejects(original(async (transaction) => {
        await callback(transaction);
        throw discarded;
      }), (error) => error === discarded);
      mutateAfterDiscard();
    }
    return original(callback);
  };
}

test("discarded confirmed approval cannot leak a ticket into committed waitlist or replay", async () => {
  const {admin, handler, request, rows} = registrationDecisionFixture("pending");
  const event = admin.db.values.get("Events/decision_event");
  event.confirmedRegistrationCount = 0; event.issuedTickets = 0;
  discardFirstDecisionAttempt(admin, () => {
    assert.equal(rows("Tickets").length, 0);
    event.confirmedRegistrationCount = 1; event.issuedTickets = 1;
  });
  assert.deepEqual(await handler.run(request("approve")), {status: "waitlisted", ticketId: null});
  assert.deepEqual(await handler.run(request("approve")), {status: "waitlisted", ticketId: null});
  assert.equal(admin.db.values.get("RegisterAttendance/decision_registration").ticketId, null);
  assert.equal(rows("RegistrationDecisions")[0][1].ticketId, null);
  assert.equal(rows("Tickets").length, 0);
  assert.equal(admin.db.values.get("Events/decision_event").confirmedRegistrationCount, 1);
  assert.equal(admin.db.values.get("Events/decision_event").issuedTickets, 1);
});

test("a retried decline rechecks current registration state and manager access before committing", async () => {
  for (const changed of ["status", "owner"]) {
    const {admin, handler, request, rows} = registrationDecisionFixture("pending");
    discardFirstDecisionAttempt(admin, () => {
      if (changed === "status") admin.db.values.get("RegisterAttendance/decision_registration").status = "confirmed";
      else admin.db.values.get("Events/decision_event").customerUid = "new_owner";
    });
    await assert.rejects(handler.run(request()), {code: changed === "status" ? "failed-precondition" : "permission-denied"});
    assert.equal(rows("RegistrationDecisions").length, 0);
    assert.equal(rows("OutboundMessages").length, 0);
  }
});

const validForm = () => normalizeDraftForm({
  title: "Community breakfast",
  description: "Meet neighbors and local organizers.",
  startAt: "2027-03-13T14:00:00.000Z",
  endAt: "2027-03-13T16:00:00.000Z",
  eventTimeZone: "America/New_York",
  locationType: "in_person",
  location: "100 Main Street",
  locationName: "Community Hall",
  city: "Fort Myers",
  regionCode: "FL",
  countryCode: "US",
  latitude: 26.64,
  longitude: -81.87,
  radius: 30,
  primaryDiscoveryCategoryId: "community-causes",
  discoveryCategoryIds: ["community-causes"],
  registration: {mode: "free_ticket", capacity: 50, approvalMode: "manual",
    waitlistEnabled: true},
  questions: [{id: "diet", prompt: "Dietary needs", type: "short_text",
    timing: "registration", required: false}],
  experience: {agenda: [{title: "Welcome", offsetMinutes: 0}],
    accessibilityOptions: ["Wheelchair accessible"], thingsToBring: ["Photo ID"],
    checkInPolicy: {profile: "hybrid", eligibility: "registered_only"}},
  recurrence: {enabled: false},
  reminderPreset: "24h_1h",
});

test("wizard catalog exposes stable curated templates", () => {
  assert.equal(TEMPLATE_CATALOG.length, 8);
  assert.equal(new Set(TEMPLATE_CATALOG.map((item) => item.id)).size, 8);
});

test("draft normalization preserves registration and check-in timing", () => {
  const form = validForm();
  assert.equal(form.registration.mode, "free_ticket");
  assert.equal(form.registration.approvalMode, "manual");
  assert.equal(form.questions[0].timing, "registration");
  assert.equal(form.experience.checkInPolicy.profile, "hybrid");
});

test("publish validation rejects incomplete, invalid, and disabled paid events", () => {
  const incomplete = normalizeDraftForm({title: "Missing place"});
  assert.ok(validatePublishable(incomplete).length >= 3);
  const paid = validForm();
  paid.registration.mode = "paid_ticket";
  paid.registration.priceUsd = 10;
  assert.ok(validatePublishable(paid, {paidEnabled: false})
      .some((error) => error.field === "mode"));
});

test("recurrence is bounded by tier and one year", () => {
  assert.equal(occurrenceLimitForTier("free"), 12);
  assert.equal(occurrenceLimitForTier("basic"), 26);
  assert.equal(occurrenceLimitForTier("premium"), 52);
  const recurrence = {enabled: true, frequency: "weekly", interval: 1,
    endMode: "count", occurrenceCount: 52, weekDays: []};
  assert.throws(() => generateOccurrences("2027-01-01T15:00:00.000Z", recurrence, 12),
      (error) => error.code === "resource-exhausted");
  assert.equal(generateOccurrences("2027-01-01T15:00:00.000Z",
      {...recurrence, occurrenceCount: 12}, 12).length, 12);
});

test("recurrence preserves local wall time across daylight-saving changes", () => {
  const recurrence = {enabled: true, frequency: "weekly", interval: 1,
    endMode: "count", occurrenceCount: 3, weekDays: []};
  const occurrences = generateOccurrences(
      "2027-03-07T14:00:00.000Z",
      recurrence,
      12,
      "America/New_York",
  );
  assert.deepEqual(occurrences.map((value) => value.toISOString()), [
    "2027-03-07T14:00:00.000Z",
    "2027-03-14T13:00:00.000Z",
    "2027-03-21T13:00:00.000Z",
  ]);
});

test("future-series edits apply the requested local time across DST", () => {
  const changed = seriesOccurrenceStart(
      "2027-03-21T13:00:00.000Z",
      "2027-03-07T14:00:00.000Z",
      "2027-03-07T15:30:00.000Z",
      "America/New_York",
  );
  assert.equal(changed.toISOString(), "2027-03-21T14:30:00.000Z");
});

test("saved templates and duplicates strip volatile event data", () => {
  const form = validForm();
  form.experience.publicContact = {name: "Host", email: "host@example.com", visible: true};
  const template = sanitizedTemplateForm(form);
  assert.equal(template.startAt, null);
  assert.equal(template.location, "");
  assert.equal(template.experience.publicContact.email, "");
  const duplicate = sanitizedDuplicateForm({title: "Original", selectedDateTime: new Date(),
    eventDuration: 2, locationType: "online", location: "https://secret.example",
    primaryDiscoveryCategoryId: "community-causes", discoveryCategoryIds: ["community-causes"]});
  assert.equal(duplicate.startAt, null);
  assert.equal(duplicate.location, "");
  assert.match(duplicate.title, /Copy/);
});

test("draft media promotion accepts only the owner's selected draft path", () => {
  const url = "https://firebasestorage.googleapis.com/v0/b/example/o/" +
    "event-drafts%2Fowner%2Fdraft-a%2Fcover.jpg?alt=media&token=secret";
  assert.equal(draftStoragePath(url, "owner", "draft-a"),
      "event-drafts/owner/draft-a/cover.jpg");
  assert.equal(draftStoragePath(url, "another-owner", "draft-a"), null);
});

test("question answers enforce type and required semantics", () => {
  assert.deepEqual(normalizeAnswer({type: "multiple_choice", options: ["A", "B"],
    required: true, prompt: "Choose"}, ["A", "invalid"]), ["A"]);
  assert.throws(() => normalizeAnswer({type: "acknowledgement", required: true,
    prompt: "Agree"}, false));
});

test("published event adapter preserves server counters and Attendance 2.0", () => {
  const form = validForm();
  const timestamp = {fromDate: (value) => value, serverTimestamp: () => "server"};
  const event = eventDocument({firestore: {Timestamp: timestamp, FieldValue: timestamp}}, form, {
    eventId: "event-1", uid: "owner", status: "scheduled", createdAt: new Date(),
    authorName: "Owner", authorRole: "member", groupName: "Owner",
    startAt: new Date(form.startAt), endAt: new Date(form.endAt), eventRevision: 2,
    preserved: {issuedTickets: 4, reservedTickets: 1, saveCount: 7},
  });
  assert.equal(event.issuedTickets, 4);
  assert.equal(event.saveCount, 7);
  assert.equal(event.checkInPolicy.profile, "hybrid");
  assert.deepEqual(signInMethods("staff_entry"), ["personal_pass", "staff_roster"]);
});
