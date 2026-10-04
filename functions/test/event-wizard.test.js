"use strict";

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
