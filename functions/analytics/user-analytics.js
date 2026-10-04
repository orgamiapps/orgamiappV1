"use strict";

const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");

const REGION = "us-central1";
const RECOMPUTE_COLLECTION = "_user_analytics_recompute";
const MAX_PROCESSING_ATTEMPTS = 5;

function normalizedUserId(userId) {
  if (typeof userId !== "string" || userId.trim().length === 0) {
    throw new Error("A non-empty analytics userId is required.");
  }
  return userId.trim();
}

function normalizedReason(reason) {
  const value = typeof reason === "string" ? reason.trim() : "unknown";
  return value.length > 0 ? value.slice(0, 80) : "unknown";
}

function recomputeReference(db, userId) {
  return db.collection(RECOMPUTE_COLLECTION).doc(normalizedUserId(userId));
}

function asDate(value) {
  if (!value) return null;
  const date = typeof value.toDate === "function" ?
    value.toDate() : new Date(value);
  return Number.isFinite(date.getTime()) ? date : null;
}

function attendeeRetentionRate(documents) {
  const attendedEvents = new Map();
  for (const document of documents) {
    const uid = document.get("customerUid") || document.get("userId");
    const eventId = document.get("eventId");
    if (!uid || !eventId || ["manual", "pre-registered"].includes(uid) ||
        document.get("voided") === true || document.get("status") === "voided") continue;
    if (!attendedEvents.has(uid)) attendedEvents.set(uid, new Set());
    attendedEvents.get(uid).add(eventId);
  }
  const repeat = [...attendedEvents.values()].filter((events) => events.size > 1).length;
  return attendedEvents.size ? repeat / attendedEvents.size * 100 : 0;
}

async function requestUserAnalyticsRecompute(
    adminSdk,
    userId,
    reason,
) {
  const db = adminSdk.firestore();
  const reference = recomputeReference(db, userId);
  const timestamp = adminSdk.firestore.Timestamp.now();

  return db.runTransaction(async (transaction) => {
    const [snapshot, deleting] = await Promise.all([
      transaction.get(reference),
      transaction.get(db.collection("account_deletion_jobs").doc(normalizedUserId(userId))),
    ]);
    if (deleting.exists) return null;
    const data = snapshot.exists ? snapshot.data() : {};
    const requestedGeneration = Number(data.requestedGeneration || 0);
    const processedGeneration = Number(data.processedGeneration || 0);
    const generation = requestedGeneration + 1;
    transaction.set(reference, {
      requestedGeneration: generation,
      processedGeneration,
      requestedAt: timestamp,
      lastReason: normalizedReason(reason),
    }, {merge: true});
    return generation;
  });
}

// Event-trigger deliveries can arrive after deletion or out of order. Fence
// initialization, cleanup, and enqueue against the same current source snapshot.
async function reconcileEventUserAnalytics(adminSdk, eventId, {
  reason, expectedOwner = null, initialize = false, deleted = false,
}) {
  const db = adminSdk.firestore();
  const eventRef = db.collection("Events").doc(eventId);
  const eventAnalyticsRef = db.collection("event_analytics").doc(eventId);
  return db.runTransaction(async (tx) => {
    const currentEvent = await tx.get(eventRef);
    if (!deleted && !currentEvent.exists) return {skipped: true, reason: "event_not_found"};
    const userId = deleted ? expectedOwner : currentEvent.get("customerUid");
    if (!userId) return {skipped: true, reason: "missing_owner"};
    if (!deleted && expectedOwner && userId !== expectedOwner) return {skipped: true, reason: "owner_changed"};
    const recomputeRef = recomputeReference(db, userId);
    const userAnalyticsRef = db.collection("user_analytics").doc(userId);
    const [recompute, eventAnalytics, deleting, remainingEvents] = await Promise.all([
      tx.get(recomputeRef), tx.get(eventAnalyticsRef),
      tx.get(db.collection("account_deletion_jobs").doc(userId)),
      deleted ? tx.get(db.collection("Events").where("customerUid", "==", userId).limit(1)) : null,
    ]);
    if (deleting.exists) return {skipped: true, reason: "account_deleting"};
    const data = recompute.data() || {};
    const generation = Number(data.requestedGeneration || 0) + 1;
    if (deleted) {
      // A delayed old delete cannot remove the analytics of a recreated event.
      if (!currentEvent.exists && eventAnalytics.exists) tx.delete(eventAnalyticsRef);
      if (remainingEvents.empty) {
        tx.delete(userAnalyticsRef);
        // Preserve a monotonic fence for workers that computed before deletion.
        // A later event must not reuse their generation after an empty period.
        // Do not recreate a marker already removed by owned fixture cleanup.
        if (recompute.exists) tx.set(recomputeRef, {requestedGeneration: generation,
          processedGeneration: generation, requestedAt: adminSdk.firestore.Timestamp.now(),
          processedAt: adminSdk.firestore.Timestamp.now(), lastReason: normalizedReason(reason)}, {merge: true});
        return {removed: true, reason: "no_owned_events"};
      }
    } else if (initialize && !eventAnalytics.exists) {
      tx.create(eventAnalyticsRef, {totalAttendees: 0, lastUpdated: adminSdk.firestore.Timestamp.now()});
    }
    tx.set(recomputeRef, {requestedGeneration: generation,
      processedGeneration: Number(data.processedGeneration || 0),
      requestedAt: adminSdk.firestore.Timestamp.now(), lastReason: normalizedReason(reason)}, {merge: true});
    return {requested: true, generation};
  });
}

async function buildUserAnalytics(adminSdk, userId) {
  const db = adminSdk.firestore();
  const normalizedId = normalizedUserId(userId);
  const userEventsQuery = await db.collection("Events")
      .where("customerUid", "==", normalizedId)
      .get();
  const userEvents = userEventsQuery.docs.map((document) => ({
    id: document.id,
    ...document.data(),
  }));

  if (userEvents.length === 0) return null;

  const eventAnalyticsDocs = await Promise.all(userEvents.map((event) =>
    db.collection("event_analytics").doc(event.id).get(),
  ));
  let totalAttendees = 0;
  let topPerformingEvent = null;
  let maxAttendees = -1;
  const eventCategories = {};
  const monthlyTrends = {};
  const eventAnalytics = {};

  userEvents.forEach((event, index) => {
    const analyticsDocument = eventAnalyticsDocs[index];
    const analytics = analyticsDocument.exists ? analyticsDocument.data() : {};
    const attendees = Number(analytics.totalAttendees || 0);
    const repeatAttendees = Number(analytics.repeatAttendees || 0);
    totalAttendees += attendees;
    eventAnalytics[event.id] = {attendees, repeatAttendees};

    if (attendees > maxAttendees) {
      maxAttendees = attendees;
      topPerformingEvent = {
        id: event.id,
        title: event.title || "Untitled Event",
        attendees,
        date: event.selectedDateTime || null,
      };
    }

    const category = event.categories?.length > 0 ?
      event.categories[0] : "Other";
    eventCategories[category] = (eventCategories[category] || 0) + 1;

    const selectedDate = asDate(event.selectedDateTime);
    if (selectedDate) {
      const monthKey = `${selectedDate.getFullYear()}-${String(
          selectedDate.getMonth() + 1,
      ).padStart(2, "0")}`;
      monthlyTrends[monthKey] = (monthlyTrends[monthKey] || 0) + attendees;
    }
  });

  let retentionRate = 0;
  try {
    const recentEventIds = [...userEvents]
        .sort((first, second) => {
          const firstDate = asDate(first.selectedDateTime);
          const secondDate = asDate(second.selectedDateTime);
          return (secondDate?.getTime() || 0) - (firstDate?.getTime() || 0);
        })
        .slice(0, 60)
        .map((event) => event.id);
    const attendanceDocuments = [];
    for (let offset = 0; offset < recentEventIds.length; offset += 10) {
      const eventIds = recentEventIds.slice(offset, offset + 10);
      const snapshot = await db.collection("Attendance")
          .where("eventId", "in", eventIds)
          .get();
      attendanceDocuments.push(...snapshot.docs);
    }
    retentionRate = attendeeRetentionRate(attendanceDocuments);
  } catch (error) {
    logger.error("Error calculating user analytics retention", {
      userId: normalizedId,
      error: String(error),
    });
  }

  return {
    totalEvents: userEvents.length,
    totalAttendees,
    averageAttendance: totalAttendees / userEvents.length,
    topPerformingEvent,
    eventCategories,
    monthlyTrends,
    retentionRate,
    eventAnalytics,
    lastUpdated: adminSdk.firestore.Timestamp.now(),
  };
}

async function commitUserAnalyticsGeneration(
    adminSdk,
    userId,
    generation,
    analytics,
) {
  const db = adminSdk.firestore();
  const normalizedId = normalizedUserId(userId);
  const recomputeRef = recomputeReference(db, normalizedId);
  const analyticsRef = db.collection("user_analytics").doc(normalizedId);
  return db.runTransaction(async (transaction) => {
    const [recomputeSnapshot, deleting] = await Promise.all([
      transaction.get(recomputeRef), transaction.get(db.collection("account_deletion_jobs").doc(normalizedId)),
    ]);
    if (deleting.exists) return "account_deleting";
    if (!recomputeSnapshot.exists) {
      return "missing";
    }
    const data = recomputeSnapshot.data();
    const requestedGeneration = Number(data.requestedGeneration || 0);
    const processedGeneration = Number(data.processedGeneration || 0);
    if (processedGeneration >= generation) {
      return "already_processed";
    }
    if (requestedGeneration !== generation) {
      return "superseded";
    }

    if (analytics === null) {
      transaction.delete(analyticsRef);
    } else {
      transaction.set(analyticsRef, {
        ...analytics,
        sourceGeneration: generation,
      });
    }
    transaction.set(recomputeRef, {
      processedGeneration: generation,
      processedAt: adminSdk.firestore.Timestamp.now(),
    }, {merge: true});
    return "committed";
  });
}

async function processUserAnalyticsRecompute(
    adminSdk,
    userId,
    options = {},
) {
  const db = adminSdk.firestore();
  const normalizedId = normalizedUserId(userId);
  const recomputeRef = recomputeReference(db, normalizedId);
  const maximumAttempts = Number(options.maximumAttempts ||
    MAX_PROCESSING_ATTEMPTS);

  for (let attempt = 1; attempt <= maximumAttempts; attempt += 1) {
    const [snapshot, deleting] = await Promise.all([
      recomputeRef.get(), db.collection("account_deletion_jobs").doc(normalizedId).get(),
    ]);
    if (deleting.exists) return {status: "account_deleting"};
    if (!snapshot.exists) return {status: "missing"};
    const requestedGeneration = Number(
        snapshot.get("requestedGeneration") || 0,
    );
    const processedGeneration = Number(
        snapshot.get("processedGeneration") || 0,
    );
    if (processedGeneration >= requestedGeneration) {
      return {status: "already_processed", generation: processedGeneration};
    }

    const analytics = await buildUserAnalytics(adminSdk, normalizedId);
    const outcome = await commitUserAnalyticsGeneration(
        adminSdk,
        normalizedId,
        requestedGeneration,
        analytics,
    );
    if (["committed", "already_processed", "account_deleting", "missing"].includes(outcome)) {
      return {status: outcome, generation: requestedGeneration};
    }
  }

  throw new Error(
      `User analytics generation kept changing for ${normalizedId}.`,
  );
}

function createProcessUserAnalyticsRecompute(adminSdk) {
  return onDocumentWritten({
    document: `${RECOMPUTE_COLLECTION}/{userId}`,
    region: REGION,
    retry: true,
  }, async (event) => {
    if (!event.data?.after.exists) return {status: "deleted"};
    try {
      const result = await processUserAnalyticsRecompute(
          adminSdk,
          event.params.userId,
      );
      logger.info("User analytics recompute processed", {
        userId: event.params.userId,
        ...result,
      });
      return result;
    } catch (error) {
      logger.error("User analytics recompute failed", {
        userId: event.params.userId,
        error: String(error),
      });
      throw error;
    }
  });
}

module.exports = {
  attendeeRetentionRate,
  MAX_PROCESSING_ATTEMPTS,
  RECOMPUTE_COLLECTION,
  buildUserAnalytics,
  commitUserAnalyticsGeneration,
  createProcessUserAnalyticsRecompute,
  processUserAnalyticsRecompute,
  requestUserAnalyticsRecompute,
  reconcileEventUserAnalytics,
};
