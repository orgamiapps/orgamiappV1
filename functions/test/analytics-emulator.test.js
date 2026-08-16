"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const admin = require("../firebase-admin-compat");
const {
  RECOMPUTE_COLLECTION,
  commitUserAnalyticsGeneration,
  processUserAnalyticsRecompute,
  requestUserAnalyticsRecompute,
} = require("../analytics/user-analytics");
const {
  fetchWithTimeout,
  uniqueId,
  waitFor,
} = require("./emulator-test-helpers");

const projectId = process.env.GCLOUD_PROJECT;
assert.equal(projectId, "demo-attendus-admin");
const backfillAnalyticsApi =
  `http://127.0.0.1:5001/${projectId}/us-central1/backfillUserAnalyticsV2`;
const authApi = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1";

async function auth(method, body) {
  const response = await fetchWithTimeout(
      `${authApi}/accounts:${method}?key=emulator-key`,
      {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(body),
      },
  );
  const responseText = await response.text();
  assert.equal(response.ok, true, responseText);
  return JSON.parse(responseText);
}

async function analyticsState(db, ownerId, eventIds) {
  const aggregate = await db.collection("user_analytics").doc(ownerId).get();
  const recompute = await db.collection(RECOMPUTE_COLLECTION).doc(ownerId).get();
  const eventAnalytics = await Promise.all(eventIds.map((eventId) =>
    db.collection("event_analytics").doc(eventId).get(),
  ));
  return {
    aggregateExists: aggregate.exists,
    totalEvents: aggregate.get("totalEvents"),
    totalAttendees: aggregate.get("totalAttendees"),
    sourceGeneration: aggregate.get("sourceGeneration"),
    eventIds: Object.keys(aggregate.get("eventAnalytics") || {}).sort(),
    eventAnalytics: eventAnalytics.map((snapshot) => snapshot.exists),
    requestedGeneration: recompute.get("requestedGeneration"),
    processedGeneration: recompute.get("processedGeneration"),
  };
}

test("analytics V2 triggers aggregate create, update, and deletion", async () => {
  const db = admin.firestore();
  const ownerId = uniqueId("analytics-owner");
  const firstEventId = uniqueId("analytics-first");
  const secondEventId = uniqueId("analytics-second");
  const thirdEventId = uniqueId("analytics-third");
  const eventIds = [firstEventId, secondEventId, thirdEventId];
  const event = (title) => ({
    customerUid: ownerId,
    title,
    categories: ["Community"],
    selectedDateTime: admin.firestore.Timestamp.fromDate(
        new Date("2026-10-01T18:00:00Z"),
    ),
  });
  const describe = () => analyticsState(db, ownerId, eventIds);

  try {
    await Promise.all([
      db.collection("Events").doc(firstEventId).set(event("First")),
      db.collection("Events").doc(secondEventId).set(event("Second")),
    ]);
    await waitFor(async () => {
      const aggregate = await db.collection("user_analytics").doc(ownerId).get();
      const recompute = await db.collection(RECOMPUTE_COLLECTION)
          .doc(ownerId).get();
      const aggregateEvents = aggregate.get("eventAnalytics") || {};
      return aggregate.exists && aggregate.get("totalEvents") === 2 &&
        aggregateEvents[firstEventId] && aggregateEvents[secondEventId] &&
        recompute.exists && recompute.get("processedGeneration") ===
          recompute.get("requestedGeneration") &&
        aggregate.get("sourceGeneration") ===
          recompute.get("processedGeneration");
    }, "initial V2 user aggregate", {describe});

    await Promise.all([
      db.collection("event_analytics").doc(firstEventId).set({
        totalAttendees: 7,
        repeatAttendees: 2,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true}),
      db.collection("event_analytics").doc(secondEventId).set({
        totalAttendees: 3,
        repeatAttendees: 0,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true}),
    ]);
    await waitFor(async () => {
      const aggregate = await db.collection("user_analytics").doc(ownerId).get();
      const recompute = await db.collection(RECOMPUTE_COLLECTION)
          .doc(ownerId).get();
      return aggregate.exists && aggregate.get("totalAttendees") === 10 &&
        recompute.get("processedGeneration") ===
          recompute.get("requestedGeneration");
    }, "updated V2 user aggregate", {describe});
    const updated = await db.collection("user_analytics").doc(ownerId).get();
    assert.equal(updated.get("averageAttendance"), 5);
    assert.equal(updated.get("topPerformingEvent.id"), firstEventId);
    assert.equal(updated.get("eventCategories.Community"), 2);
    assert.equal(updated.get("monthlyTrends.2026-10"), 10);
    assert.equal(updated.get("retentionRate"), 0);

    await Promise.all([
      db.collection("Events").doc(firstEventId).delete(),
      db.collection("Events").doc(thirdEventId).set(event("Third")),
    ]);
    await waitFor(async () => {
      const analytics = await db.collection("event_analytics")
          .doc(firstEventId).get();
      const aggregate = await db.collection("user_analytics").doc(ownerId).get();
      return !analytics.exists && aggregate.exists &&
        aggregate.get("totalEvents") === 2 &&
        aggregate.get(`eventAnalytics.${secondEventId}`) &&
        aggregate.get(`eventAnalytics.${thirdEventId}`) &&
        !aggregate.get(`eventAnalytics.${firstEventId}`);
    }, "V2 aggregate after overlapping create and deletion", {describe});

    await Promise.all([
      db.collection("Events").doc(secondEventId).delete(),
      db.collection("Events").doc(thirdEventId).delete(),
    ]);
    await waitFor(async () =>
      !(await db.collection("user_analytics").doc(ownerId).get()).exists,
    "V2 aggregate cleanup after final event deletion", {describe});
  } finally {
    await Promise.all(eventIds.map(async (eventId) => {
      await db.collection("Events").doc(eventId).delete();
      await db.collection("event_analytics").doc(eventId).delete();
    }));
    await db.collection("user_analytics").doc(ownerId).delete();
    await db.collection(RECOMPUTE_COLLECTION).doc(ownerId).delete();
  }
});

test("analytics generation guard rejects stale and duplicate processors", async () => {
  const db = admin.firestore();
  const ownerId = uniqueId("analytics-generation-owner");
  const eventId = uniqueId("analytics-generation-event");
  const recompute = db.collection(RECOMPUTE_COLLECTION).doc(ownerId);

  try {
    await db.collection("Events").doc(eventId).set({
      customerUid: ownerId,
      title: "Generation test",
      categories: ["Technology"],
      selectedDateTime: admin.firestore.Timestamp.fromDate(
          new Date("2026-11-01T18:00:00Z"),
      ),
    });
    await waitFor(async () =>
      (await db.collection("user_analytics").doc(ownerId).get()).exists,
    "generation test initial aggregate");

    const staleGeneration = await requestUserAnalyticsRecompute(
        admin, ownerId, "stale_test",
    );
    await requestUserAnalyticsRecompute(admin, ownerId, "newer_test");
    const staleOutcome = await commitUserAnalyticsGeneration(
        admin,
        ownerId,
        staleGeneration,
        {totalEvents: 999, eventAnalytics: {}},
    );
    assert.equal(staleOutcome, "superseded");

    await Promise.all([
      processUserAnalyticsRecompute(admin, ownerId),
      processUserAnalyticsRecompute(admin, ownerId),
    ]);
    const aggregate = await db.collection("user_analytics").doc(ownerId).get();
    const state = await recompute.get();
    assert.equal(aggregate.get("totalEvents"), 1);
    assert.equal(aggregate.get("sourceGeneration"),
        state.get("processedGeneration"));
    assert.equal(state.get("processedGeneration"),
        state.get("requestedGeneration"));
  } finally {
    await db.collection("Events").doc(eventId).delete();
    await db.collection("event_analytics").doc(eventId).delete();
    await db.collection("user_analytics").doc(ownerId).delete();
    await recompute.delete();
  }
});

test("analytics V2 backfill enforces role and rebuilds aggregate", async () => {
  const db = admin.firestore();
  const password = "ValidPassword123!";
  const email = `${uniqueId("ordinary-analytics")}@example.test`;
  const ownerId = uniqueId("backfill-owner");
  const eventId = uniqueId("backfill-event");
  const ordinary = await auth("signUp", {
    email,
    password,
    returnSecureToken: true,
  });
  const payload = JSON.stringify({data: {
    confirmed: true,
    reason: "Verified analytics migration in the emulator",
  }});

  try {
    await db.collection("Events").doc(eventId).set({
      customerUid: ownerId,
      title: "Backfill integration event",
      categories: ["Education"],
      selectedDateTime: admin.firestore.Timestamp.fromDate(
          new Date("2026-10-02T18:00:00Z"),
      ),
    });

    const denied = await fetchWithTimeout(backfillAnalyticsApi, {
      method: "POST",
      headers: {
        authorization: `Bearer ${ordinary.idToken}`,
        "content-type": "application/json",
      },
      body: payload,
    });
    assert.equal(denied.status, 403);

    await admin.auth().setCustomUserClaims(ordinary.localId, {admin: true});
    await db.collection("admin_roles").doc(ordinary.localId).set({
      active: true,
      roles: ["analyst"],
    });
    const signedIn = await auth("signInWithPassword", {
      email,
      password,
      returnSecureToken: true,
    });
    const acceptedRequest = fetchWithTimeout(backfillAnalyticsApi, {
      method: "POST",
      headers: {
        authorization: `Bearer ${signedIn.idToken}`,
        "content-type": "application/json",
      },
      body: payload,
    }, 30000);
    await db.collection("event_analytics").doc(eventId).set({
      totalAttendees: 4,
      repeatAttendees: 1,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    const accepted = await acceptedRequest;
    assert.equal(accepted.status, 200, await accepted.text());

    await waitFor(async () => {
      const aggregate = await db.collection("user_analytics").doc(ownerId).get();
      const recompute = await db.collection(RECOMPUTE_COLLECTION)
          .doc(ownerId).get();
      return aggregate.exists && aggregate.get("totalEvents") === 1 &&
        aggregate.get("totalAttendees") === 4 && recompute.exists &&
        recompute.get("processedGeneration") ===
          recompute.get("requestedGeneration");
    }, "backfilled user aggregate", {
      describe: () => analyticsState(db, ownerId, [eventId]),
    });
  } finally {
    await db.collection("admin_roles").doc(ordinary.localId).delete();
    await db.collection("Events").doc(eventId).delete();
    await db.collection("event_analytics").doc(eventId).delete();
    await db.collection("user_analytics").doc(ownerId).delete();
    await db.collection(RECOMPUTE_COLLECTION).doc(ownerId).delete();
    await admin.auth().deleteUser(ordinary.localId).catch(() => undefined);
  }
});
