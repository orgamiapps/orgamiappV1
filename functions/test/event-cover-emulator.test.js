"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "") ||
    !/^127\.0\.0\.1:\d+$/.test(process.env.FIREBASE_STORAGE_EMULATOR_HOST || "")) throw Error("Local emulators required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: "demo-attendus-admin", storageBucket: "demo-attendus-admin.appspot.com"});
const admin = require("../firebase-admin-compat");
const {createEventWizardFunctions} = require("../events/wizard");
const db = admin.firestore();
const handlers = createEventWizardFunctions(admin);
const uid = `cover-${Date.now()}`;
const request = (data) => ({auth: {uid, token: {firebase: {sign_in_provider: "password"}}}, data});
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=", "base64");
test.after(async () => db.terminate());

test("uploaded cover publishes to permanent storage, survives cleanup and replays once", async () => {
  await db.doc(`Customers/${uid}`).set({name: "Image fixture", eventsCreated: 0});
  const formData = {title: "Text location image test", locationType: "in_person", locationInputMode: "text", location: "Community clubhouse",
    startAt: new Date(Date.now() + 86400000).toISOString(), endAt: new Date(Date.now() + 90000000).toISOString(),
    eventTimeZone: "America/New_York", primaryDiscoveryCategoryId: "community-causes", registration: {mode: "rsvp"},
    experience: {checkInPolicy: {profile: "none"}}};
  const draft = await handlers.saveEventDraftV1.run(request({formData}));
  const path = `event-drafts/${uid}/${draft.draftId}/cover.png`;
  const bucket = admin.storage().bucket();
  const source = bucket.file(path);
  await source.save(png, {metadata: {contentType: "image/png"}});
  formData.imageUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media`;
  const saved = await handlers.saveEventDraftV1.run(request({draftId: draft.draftId, expectedRevision: draft.revision, formData}));
  const args = request({draftId: saved.draftId, expectedDraftRevision: saved.revision});
  const published = await handlers.publishEventDraftV1.run(args);
  const event = (await db.doc(`Events/${published.eventId}`).get()).data();
  assert.equal(event.location, "Community clubhouse");
  assert.equal(event.locationInputMode, "text");
  assert.equal(event.latitude, 0);
  assert.equal(event.getLocation, false);
  assert.ok(event.imageUrl.includes("events_images%2Fwizard-"));
  const permanent = decodeURIComponent(new URL(event.imageUrl).pathname.split("/o/")[1]);
  assert.deepEqual((await bucket.file(permanent).download())[0], png);
  assert.equal((await source.exists())[0], false);
  assert.deepEqual(await handlers.publishEventDraftV1.run(args), published);
  assert.equal((await db.doc(`Customers/${uid}`).get()).get("eventsCreated"), 1);
});

test("missing cover leaves the draft unpublished and consumes no event allowance", async () => {
  const formData = {title: "Failed cover", locationType: "in_person", locationInputMode: "text", location: "Clubhouse",
    startAt: new Date(Date.now() + 86400000).toISOString(), endAt: new Date(Date.now() + 90000000).toISOString(),
    eventTimeZone: "UTC", primaryDiscoveryCategoryId: "community-causes", experience: {checkInPolicy: {profile: "none"}}};
  const draft = await handlers.saveEventDraftV1.run(request({formData}));
  formData.imageUrl = `https://firebasestorage.googleapis.com/v0/b/demo-attendus-admin.appspot.com/o/${encodeURIComponent(`event-drafts/${uid}/${draft.draftId}/missing.png`)}`;
  const saved = await handlers.saveEventDraftV1.run(request({draftId: draft.draftId, expectedRevision: draft.revision, formData}));
  const before = (await db.doc(`Customers/${uid}`).get()).get("eventsCreated");
  await assert.rejects(handlers.publishEventDraftV1.run(request({draftId: saved.draftId, expectedDraftRevision: saved.revision})));
  assert.equal((await db.doc(`EventDrafts/${draft.draftId}`).get()).get("publishedAt"), undefined);
  assert.equal((await db.doc(`Customers/${uid}`).get()).get("eventsCreated"), before);
});

test("typed location with optional coordinates persists its label and pin through publication", async () => {
  const formData = {title: "Pinned label", locationType: "in_person", locationInputMode: "text", locationCoordinatesEnabled: true,
    location: "Upstairs lounge", latitude: 26.64, longitude: -81.87, city: "Fort Myers", regionCode: "FL", countryCode: "US",
    startAt: new Date(Date.now() + 86400000).toISOString(), endAt: new Date(Date.now() + 90000000).toISOString(),
    eventTimeZone: "America/New_York", primaryDiscoveryCategoryId: "community-causes", experience: {checkInPolicy: {profile: "none"}}};
  const draft = await handlers.saveEventDraftV1.run(request({formData}));
  const published = await handlers.publishEventDraftV1.run(request({draftId: draft.draftId, expectedDraftRevision: draft.revision}));
  const event = (await db.doc(`Events/${published.eventId}`).get()).data();
  assert.equal(event.location, "Upstairs lounge");
  assert.equal(event.locationName, "Upstairs lounge");
  assert.equal(event.locationCoordinatesEnabled, true);
  assert.equal(event.latitude, 26.64);
  assert.equal(event.getLocation, true);
  const edit = await handlers.createEditEventDraftV1.run(request({eventId: published.eventId}));
  assert.equal(edit.formData.locationCoordinatesEnabled, true);
  assert.equal(edit.formData.location, "Upstairs lounge");
  const saved = await handlers.saveEventDraftV1.run(request({draftId: edit.id, expectedRevision: edit.revision,
    mode: "edit", sourceEventId: edit.sourceEventId, sourceSeriesId: edit.sourceSeriesId,
    sourceEventRevision: edit.sourceEventRevision, formData: {...edit.formData, locationCoordinatesEnabled: false}}));
  await assert.rejects(handlers.publishEventDraftV1.run(request({draftId: saved.draftId, expectedDraftRevision: saved.revision})), {code: "failed-precondition"});
  const preview = await handlers.previewEventChangeV1.run(request({draftId: saved.draftId, expectedDraftRevision: saved.revision}));
  await handlers.publishEventDraftV1.run(request({draftId: saved.draftId, expectedDraftRevision: saved.revision,
    changePreviewToken: preview.previewToken, changeReason: "Remove the optional map pin"}));
  const edited = (await db.doc(`Events/${published.eventId}`).get()).data();
  assert.equal(edited.location, "Upstairs lounge");
  assert.equal(edited.locationCoordinatesEnabled, false);
  assert.equal(edited.latitude, 0);
  assert.equal(edited.getLocation, false);
});
