"use strict";
const {onDocumentCreated, onDocumentWritten} = require("firebase-functions/v2/firestore");
const {createLegacyNotificationSender} = require("../notifications/legacy-delivery");
function sourceId(event, kind) {
  const snapshot = event.data?.after || event.data;
  const revision = event.id || snapshot?.updateTime?.toMillis?.() || event.time;
  if (!revision) throw Error("A stable notification trigger revision is required");
  return `${kind}:${snapshot?.ref?.path || ""}:${revision}`;
}
function createCommunityNotificationHandlers(admin) {
  const db = admin.firestore();
  const send = createLegacyNotificationSender(admin);
  async function organizerFeedback(event) {
    const feedback = event.data?.data();
    if (!feedback?.eventId) return;
    const source = await event.data.ref.get();
    if (!source.exists) return;
    const root = await db.collection("Events").doc(feedback.eventId).get();
    const owner = root.get("customerUid") || root.get("createdBy");
    if (!root.exists || !owner) return;
    return send(owner, {type: "organizer_feedback", actorUid: feedback.userId || undefined, title: "New feedback received",
      body: `Your event "${root.get("title") || root.get("eventTitle") || "Event"}" received new feedback`,
      eventId: feedback.eventId, eventTitle: root.get("title") || root.get("eventTitle") || "Event"}, db,
    sourceId(event, "feedback"), {path: event.data.ref.path});
  }
  async function joinRequest(event) {
    const orgId = event.params.orgId;
    const group = db.collection("Organizations").doc(orgId);
    const current = await event.data.ref.get();
    if (!current.exists || current.get("status") !== "pending") return;
    const members = await group.collection("Members").where("status", "==", "approved").get();
    for (const member of members.docs) {
      if (!["owner", "admin"].includes(String(member.get("role") || "").toLowerCase())) continue;
      await send(member.id, {type: "org_update", actorUid: event.params.userId, title: "New join request", body: "A user requested to join your organization",
        data: {organizationId: orgId}}, db, sourceId(event, "join"), {path: member.ref.path, approvedAdmin: true});
    }
  }
  async function membership(event) {
    if (!event.data?.after.exists) return;
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.data();
    const {orgId, userId} = event.params;
    const group = await db.collection("Organizations").doc(orgId).get();
    const name = group.get("name") || "the group";
    const condition = {path: event.data.after.ref.path, fields: {status: after.status, ...(after.role ? {role: after.role} : {})}};
    const notifications = [];
    if ((!before && after.status === "approved") || (before && before.status !== after.status)) notifications.push({kind: "membership-status",
      title: after.status === "approved" ? "Join request approved" : "Join request updated",
      body: after.status === "approved" ? `You have been approved to join ${name}` : `Your status in ${name} is now ${after.status}`});
    if (before && before.role !== after.role) notifications.push({kind: "membership-role", title: "Role Changed", body: `Your role in ${name} is now ${after.role}`});
    for (const notification of notifications) await send(userId, {type: "org_update", title: notification.title, body: notification.body,
      data: {organizationId: orgId, organizationName: name}}, db, sourceId(event, notification.kind), condition);
  }
  async function joinDecision(event) {
    if (!event.data?.after.exists || !event.data.before.exists || event.data.before.get("status") === event.data.after.get("status") || event.data.after.get("status") !== "declined") return;
    const {orgId, userId} = event.params;
    const group = await db.collection("Organizations").doc(orgId).get();
    const name = group.get("name") || "the group";
    await send(userId, {type: "org_update", title: "Join request declined", body: `Your request to join ${name} was declined`,
      data: {organizationId: orgId, organizationName: name}}, db, sourceId(event, "join-declined"),
    {path: event.data.after.ref.path, fields: {status: "declined"}});
  }
  return {organizerFeedback, joinRequest, membership, joinDecision};
}
function createCommunityNotifications(admin) {
  const handlers = createCommunityNotificationHandlers(admin);
  return {
    notifyOrganizerOnFeedback: onDocumentCreated({document: "event_feedback/{docId}", retry: true}, handlers.organizerFeedback),
    notifyOrgAdminsOnJoinRequest: onDocumentCreated({document: "Organizations/{orgId}/JoinRequests/{userId}", retry: true}, handlers.joinRequest),
    notifyOrgMembershipChanges: onDocumentWritten({document: "Organizations/{orgId}/Members/{userId}", retry: true}, handlers.membership),
    notifyOrgJoinRequestDecision: onDocumentWritten({document: "Organizations/{orgId}/JoinRequests/{userId}", retry: true}, handlers.joinDecision),
  };
}
module.exports = {createCommunityNotifications, createCommunityNotificationHandlers};
