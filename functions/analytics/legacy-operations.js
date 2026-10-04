"use strict";

const crypto = require("node:crypto");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const documentId = (value) => typeof value === "string" && /^[^/]{1,500}$/.test(value);
const markerId = (value) => crypto.createHash("sha256").update(value).digest("hex");
const count = (value) => Number.isFinite(value) && value >= 0 ? value : 0;
const date = (value) => value?.toDate ? value.toDate() : new Date(value);

function createLegacyAnalyticsHandlers(admin) {
  const db = admin.firestore();
  const stamp = () => admin.firestore.FieldValue.serverTimestamp();
  async function aggregateAttendance(event) {
    const source = event.data?.data();
    const eventId = source?.eventId;
    if (!documentId(eventId) || !documentId(event.params?.docId)) return {skipped: true, reason: "missing_event_id"};
    const root = await db.collection("Events").doc(eventId).get();
    if (!root.exists) return {skipped: true, reason: "missing_event"};
    const uid = source.customerUid || source.userId;
    let repeat = false;
    if (uid && root.get("customerUid") && !["manual", "pre-registered"].includes(uid)) {
      const hostEvents = await db.collection("Events").where("customerUid", "==", root.get("customerUid")).get();
      const otherIds = hostEvents.docs.map((doc) => doc.id).filter((id) => id !== eventId);
      for (let offset = 0; offset < otherIds.length && !repeat; offset += 30) {
        const prior = await db.collection("Attendance").where("customerUid", "==", uid)
            .where("eventId", "in", otherIds.slice(offset, offset + 30)).limit(1).get();
        repeat = !prior.empty;
      }
    }
    const registrations = await db.collection("RegisterAttendance").where("eventId", "==", eventId).get();
    const registered = registrations.docs.filter((doc) => !["cancelled", "declined", "pending", "pending_approval", "waitlisted"].includes(doc.get("status"))).length;
    const sourceTime = date(source.attendanceDateTime || source.checkedInAt || source.createdAt || event.data.createTime || event.time);
    if (!Number.isFinite(sourceTime.getTime())) return {skipped: true, reason: "missing_attendance_time"};
    let hour;
    try {
      hour = new Intl.DateTimeFormat("en-GB", {hour: "2-digit", hourCycle: "h23", timeZone: root.get("eventTimeZone") || "UTC"}).format(sourceTime);
    } catch (_error) { hour = String(sourceTime.getUTCHours()).padStart(2, "0"); }
    const bucket = `${hour}:00`;
    const ref = db.collection("event_analytics").doc(eventId);
    const marker = ref.collection("processedAttendance").doc(markerId(event.params.docId));
    return db.runTransaction(async (tx) => {
      const [current, processed, live] = await Promise.all([tx.get(ref), tx.get(marker), tx.get(event.data.ref)]);
      if (processed.exists || !live.exists) return {skipped: true};
      const existing = current.data() || {};
      const total = count(existing.totalAttendees) + 1;
      const hours = {...existing.hourlySignIns, [bucket]: count(existing.hourlySignIns?.[bucket]) + 1};
      tx.set(ref, {totalAttendees: total, hourlySignIns: hours,
        repeatAttendees: count(existing.repeatAttendees) + (repeat ? 1 : 0),
        dropoutRate: registered ? Math.max(0, (registered - total) / registered * 100) : 0,
        lastUpdated: stamp()}, {merge: true});
      tx.create(marker, {processedAt: stamp()});
      return {processed: true};
    });
  }
  async function aggregateFeedback(event) {
    const source = event.data?.data();
    if (!documentId(source?.eventId) || !documentId(event.params?.docId) ||
        !Number.isInteger(source.rating) || source.rating < 1 || source.rating > 5) return {skipped: true, reason: "invalid_feedback"};
    const ref = db.collection("event_analytics").doc(source.eventId);
    const marker = ref.collection("processedFeedback").doc(markerId(event.params.docId));
    return db.runTransaction(async (tx) => {
      const [current, processed, live] = await Promise.all([tx.get(ref), tx.get(marker), tx.get(event.data.ref)]);
      if (processed.exists || !live.exists) return {skipped: true};
      const existing = current.get("feedbackAnalytics") || {};
      const oldTotal = count(existing.totalRatings);
      const totalRatings = oldTotal + 1;
      const averageRating = (count(existing.averageRating) * oldTotal + source.rating) / totalRatings;
      const commentSummaries = Array.isArray(existing.commentSummaries) ? existing.commentSummaries.slice(0, 10) : [];
      if (typeof source.comment === "string" && source.comment && commentSummaries.length < 10) commentSummaries.push(source.comment.slice(0, 100) + (source.comment.length > 100 ? "..." : ""));
      tx.set(ref, {feedbackAnalytics: {averageRating, totalRatings,
        ratingDistribution: {...existing.ratingDistribution, [source.rating]: count(existing.ratingDistribution?.[source.rating]) + 1},
        anonymousCount: count(existing.anonymousCount) + (source.isAnonymous === true ? 1 : 0),
        namedCount: count(existing.namedCount) + (source.isAnonymous === true ? 0 : 1),
        sentiment: averageRating >= 4 ? "positive" : averageRating >= 3 ? "neutral" : "negative",
        commentSummaries}, lastUpdated: stamp()}, {merge: true});
      tx.create(marker, {processedAt: stamp()});
      return {processed: true};
    });
  }
  async function resetMonthly(event = {}) {
    const scheduled = date(event.scheduleTime || Date.now());
    if (!Number.isFinite(scheduled.getTime())) throw new Error("Invalid monthly reset schedule time");
    const month = new Date(Date.UTC(scheduled.getUTCFullYear(), scheduled.getUTCMonth(), 1));
    let cursor;
    let resetCount = 0;
    let hasMore = true;
    while (hasMore) {
      let query = db.collection("subscriptions").where("tier", "==", "basic").where("status", "==", "active")
          .orderBy(admin.firestore.FieldPath.documentId()).limit(200);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      if (page.empty) break;
      // Each conditional reset preserves usage already created in this month,
      // including after a partially successful scheduler invocation is retried.
      for (const doc of page.docs) {
        const changed = await db.runTransaction(async (tx) => {
          const current = await tx.get(doc.ref);
          if (!current.exists || current.get("tier") !== "basic" || current.get("status") !== "active") return false;
          const previous = date(current.get("currentMonthStart"));
          if (Number.isFinite(previous.getTime()) && previous >= month) return false;
          tx.update(doc.ref, {eventsCreatedThisMonth: 0, currentMonthStart: admin.firestore.Timestamp.fromDate(month), updatedAt: stamp()});
          return true;
        });
        if (changed) resetCount++;
      }
      cursor = page.docs[page.docs.length - 1];
      hasMore = page.size === 200;
    }
    return {success: true, count: resetCount, month: month.toISOString()};
  }
  return {aggregateAttendance, aggregateFeedback, resetMonthly};
}

function createLegacyAnalyticsOperations(admin) {
  const handlers = createLegacyAnalyticsHandlers(admin);
  return {
    aggregateAttendanceData: onDocumentCreated({document: "Attendance/{docId}", retry: true}, handlers.aggregateAttendance),
    aggregateFeedbackData: onDocumentCreated({document: "event_feedback/{docId}", retry: true}, handlers.aggregateFeedback),
    resetMonthlyEventLimits: onSchedule({schedule: "0 0 1 * *", timeZone: "UTC", region: "us-central1", timeoutSeconds: 540}, handlers.resetMonthly),
  };
}

module.exports = {createLegacyAnalyticsHandlers, createLegacyAnalyticsOperations};
