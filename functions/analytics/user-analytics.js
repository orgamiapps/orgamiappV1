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

async function requestUserAnalyticsRecompute(
    adminSdk,
    userId,
    reason,
) {
  const db = adminSdk.firestore();
  const reference = recomputeReference(db, userId);
  const timestamp = adminSdk.firestore.Timestamp.now();
  let generation;

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const data = snapshot.exists ? snapshot.data() : {};
    const requestedGeneration = Number(data.requestedGeneration || 0);
    const processedGeneration = Number(data.processedGeneration || 0);
    generation = requestedGeneration + 1;
    transaction.set(reference, {
      requestedGeneration: generation,
      processedGeneration,
      requestedAt: timestamp,
      lastReason: normalizedReason(reason),
    }, {merge: true});
  });

  return generation;
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
    const attendanceCounts = {};
    for (const document of attendanceDocuments) {
      const attendeeId = document.get("customerUid");
      if (attendeeId && attendeeId !== "manual") {
        attendanceCounts[attendeeId] =
          (attendanceCounts[attendeeId] || 0) + 1;
      }
    }
    const totalUniqueAttendees = Object.keys(attendanceCounts).length;
    const repeatAttendeeCount = Object.values(attendanceCounts)
        .filter((count) => count > 1)
        .length;
    retentionRate = totalUniqueAttendees > 0 ?
      (repeatAttendeeCount / totalUniqueAttendees) * 100 : 0;
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
  let outcome = "superseded";

  await db.runTransaction(async (transaction) => {
    const recomputeSnapshot = await transaction.get(recomputeRef);
    if (!recomputeSnapshot.exists) {
      outcome = "missing";
      return;
    }
    const data = recomputeSnapshot.data();
    const requestedGeneration = Number(data.requestedGeneration || 0);
    const processedGeneration = Number(data.processedGeneration || 0);
    if (processedGeneration >= generation) {
      outcome = "already_processed";
      return;
    }
    if (requestedGeneration !== generation) {
      outcome = "superseded";
      return;
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
    outcome = "committed";
  });

  return outcome;
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
    const snapshot = await recomputeRef.get();
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
    if (outcome === "committed" || outcome === "already_processed") {
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
  MAX_PROCESSING_ATTEMPTS,
  RECOMPUTE_COLLECTION,
  buildUserAnalytics,
  commitUserAnalyticsGeneration,
  createProcessUserAnalyticsRecompute,
  processUserAnalyticsRecompute,
  requestUserAnalyticsRecompute,
};
