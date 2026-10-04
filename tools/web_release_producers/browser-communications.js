"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {isDeepStrictEqual} = require("node:util");
const {createPilotObserver, validatePilot} = require("./browser-pilot");
const {bindingId} = require("../../functions/communications/qualification-isolation");
const {schedule} = require("../../functions/events/schedule");
const hash = (text) => crypto.createHash("sha256").update(text).digest("hex");
const iso = (value) => value?.toDate?.().toISOString() || null;
const safeId = (value) => typeof value === "string" && /^[A-Za-z0-9_.:-]{1,500}$/.test(value);

function previousDeletion({candidate, candidateIdentity, identity, priorEvidence, fixture}) {
  const {validateEvidence, relativeFile} = require("../web_release_contract");
  for (const {report, outputDir} of priorEvidence) {
    if (report.producer !== "tools/web_release_producers/browser.js" || report.gate !== "browser-auth-guest-organizer") continue;
    validateEvidence(report, candidate, outputDir);
    if (report.observedStateSha256 !== candidateIdentity.deployment?.stateSha256) throw Error("Prior deletion deployment differs.");
    const names = Object.keys(report.rawFiles).filter((name) => /(^|\/)communications-receipts\.json$/.test(name));
    if (!names.length) continue;
    if (names.length !== 1) throw Error("Prior deletion receipt is ambiguous.");
    const previous = JSON.parse(fs.readFileSync(path.join(outputDir, relativeFile(names[0])), "utf8"));
    if (previous.schemaVersion !== 1 || !isDeepStrictEqual(previous.identity, identity) || previous.receipts?.deletedUid !== fixture.deletion.uid ||
        !safeId(previous.receipts.appFeedbackId) || !Number.isFinite(Date.parse(previous.completedAt)) || !Number.isFinite(Date.parse(previous.startedAt)) ||
        Date.parse(previous.completedAt) < Date.parse(previous.startedAt) ||
        Date.parse(previous.startedAt) < Date.parse(report.startedAt) || Date.parse(previous.completedAt) > Date.parse(report.finishedAt) ||
        !previous.assertions?.length || previous.assertions.some((item) => !isDeepStrictEqual(item.expected, item.actual)) ||
        !previous.assertions.some((item) => item.id === "deletion_job_completed_without_remaining_data")) throw Error("Prior deletion identity or completion proof differs.");
    return {receipts: previous.receipts, provenance: {workflowRunId: report.workflowRunId, path: names[0], sha256: report.rawFiles[names[0]]}};
  }
  return null;
}

function validateCommunications(fixture, candidateIdentity) {
  const identity = validatePilot(fixture, candidateIdentity), spec = fixture.communications;
  if (!spec || [spec.reminderEventId, spec.discoveryEventId].some((id) => !fixture.ownedFixtureIds.includes(id)) ||
      spec.reminderEventId === spec.discoveryEventId || [spec.reminderEventId, spec.discoveryEventId].includes(fixture.event.id) ||
      spec.pendingPushId !== `${fixture.runId}-pending` ||
      fixture.conversationId !== [fixture.owner.uid, fixture.attendee.uid].sort().join("_") ||
      !fixture.ownedFixtureIds.includes(fixture.conversationId)) throw Error("Separate bound communication fixtures are required.");
  for (const role of ["administrator", "deletion"]) {
    const account = fixture[role];
    if (!account || !fixture.ownedFixtureIds.includes(account.uid) ||
        account.uid !== `${fixture.runId}-${role}` || account.email !== `${fixture.runId}-${role}@example.test`) throw Error("A controlled communication actor is required.");
  }
  return identity;
}

function createCommunicationsObserver({fixture, candidateIdentity, db, auth}) {
  const identity = validateCommunications(fixture, candidateIdentity);
  const guardPilot = createPilotObserver({fixture, candidateIdentity, db});
  const spec = fixture.communications;
  const bounded = async (query, limit = 1000) => {
    const value = await query.limit(limit + 1).get();
    if (value.size > limit) throw Error("Communication fixture observation exceeded its budget.");
    return value.docs;
  };
  return async function observe(selection = {}) {
    if (Object.entries(selection).some(([key, value]) => key.endsWith("Id") && !safeId(value))) throw Error("Invalid communication receipt identity.");
    await guardPilot({guardOnly: true});
    const refs = [db.doc(`QualificationScopes/${fixture.runId}`), db.doc(`admin_roles/${fixture.administrator.uid}`),
      db.doc(`QualificationBindings/${bindingId("account", fixture.administrator.uid)}`),
      db.doc(`QualificationBindings/${bindingId("account", fixture.deletion.uid)}`),
      db.doc(`QualificationBindings/${bindingId("conversation", fixture.conversationId)}`),
      ...[spec.reminderEventId, spec.discoveryEventId].flatMap((id) => [db.doc(`Events/${id}`), db.doc(`QualificationBindings/${bindingId("event", id)}`)])];
    const [scope, admin, ...records] = await db.getAll(...refs);
    const [adminBinding, deletionBinding, conversationBinding, reminder, reminderBinding, discovery, discoveryBinding] = records;
    const bound = (row) => row.get("schemaVersion") === 1 && row.get("state") === "bound" && row.get("projectId") === identity.projectId && row.get("runId") === identity.runId;
    if (![adminBinding, deletionBinding, conversationBinding, reminderBinding, discoveryBinding].every(bound) ||
        !scope.get("actorUids").includes(fixture.administrator.uid) || !scope.get("recipientUids").includes(fixture.administrator.uid) ||
        scope.get("actorUids").includes(fixture.deletion.uid) || scope.get("recipientUids").includes(fixture.deletion.uid) ||
        !scope.get("conversationIds").includes(fixture.conversationId) || admin.get("active") !== true || !admin.get("roles")?.includes("support") ||
        [reminder, discovery].some((event) => !scope.get("eventIds").includes(event.id) || event.get("customerUid") !== fixture.owner.uid ||
          event.get("private") !== false || event.get("status") !== "active" || event.get("isHidden") === true || event.get("deleted") === true)) {
      throw Error("Communication fixture bindings, administrative role or deletion isolation changed.");
    }
    if (selection.guardOnly) return {};
    const [captures, pending, discoveryItems, discoveryDeliveries, reminders, registration, message, feedback, adminOperation,
      deleting, profile, user, appFeedback] = await Promise.all([
      bounded(db.collection("QualificationCaptures").where("runId", "==", fixture.runId)),
      db.doc(`pendingPushNotifications/${spec.pendingPushId}`).get(),
      bounded(db.doc(`discovery_notification_batches/${fixture.attendee.uid}`).collection("events"), 100),
      bounded(db.doc(`discovery_notification_batches/${fixture.attendee.uid}`).collection("deliveries"), 100),
      bounded(db.collection("scheduledNotifications").where("eventId", "==", spec.reminderEventId), 100),
      selection.registrationId ? db.doc(`RegisterAttendance/${selection.registrationId}`).get() : null,
      selection.messageId ? db.doc(`Messages/${selection.messageId}`).get() : null,
      selection.feedbackId ? db.doc(`event_feedback/${selection.feedbackId}`).get() : null,
      db.doc(`admin_idempotency/${hash(`sendCustomNotifications:${fixture.administrator.uid}:${fixture.runId}:admin-notification`)}`).get(),
      db.doc(`account_deletion_jobs/${fixture.deletion.uid}`).get(), db.doc(`Customers/${fixture.deletion.uid}`).get(),
      db.doc(`users/${fixture.deletion.uid}`).get(), selection.appFeedbackId ? db.doc(`app_feedback/${selection.appFeedbackId}`).get() : null,
    ]);
    let authenticationExists = true;
    try {await auth.getUser(fixture.deletion.uid);} catch (error) {if (error.code === "auth/user-not-found") authenticationExists = false; else throw error;}
    return {observedAt: new Date().toISOString(),
      captures: captures.map((doc) => {
        const row = doc.data();
        return {id: doc.id, sourceKey: row.sourceKey, recipientUid: row.recipientUid || null, eventIds: row.eventIds || [],
          capturedAt: iso(row.capturedAt), provider: row.provider,
          valid: row.fingerprint === hash(JSON.stringify(row.payload)) && doc.id === hash(JSON.stringify([row.runId, row.recipientUid || row.recipientEmailHash, row.sourceKey]))};
      }),
      reminder: {eventId: reminder.id, startsAt: schedule(reminder.data()).start?.toISOString(),
        jobs: reminders.filter((doc) => doc.get("userId") === fixture.attendee.uid).map((doc) => ({id: doc.id, status: doc.get("deliveryState"),
          dueAt: iso(doc.get("originalDueAt")), deadlineAt: iso(doc.get("deliveryDeadline")), reminderMinutes: doc.get("reminderMinutes"), attempts: doc.get("attemptCount") || 0}))},
      discovery: {eventId: discovery.id, startsAt: schedule(discovery.data()).start?.toISOString(),
        createdAt: iso(discovery.get("createdAt")),
        items: discoveryItems.filter((doc) => doc.get("eventId") === spec.discoveryEventId).map((doc) => ({id: doc.id, status: doc.get("status"), readyAt: iso(doc.get("readyAt")), queuedAt: iso(doc.get("queuedAt"))})),
        deliveries: discoveryDeliveries.filter((doc) => (doc.get("eventIds") || []).includes(spec.discoveryEventId))
            .map((doc) => ({id: doc.id, state: doc.get("state"), createdAt: iso(doc.get("createdAt"))}))},
      pending: {id: pending.id, exists: pending.exists, status: pending.get("status") || null,
        sourceMatches: pending.get("senderId") === fixture.owner.uid && pending.get("receiverId") === fixture.attendee.uid &&
          pending.get("eventId") === fixture.event.id && pending.get("conversationId") === fixture.conversationId && !pending.get("fcmToken")},
      sourceReceipts: {registration: registration?.exists && registration.get("eventId") === spec.reminderEventId && registration.get("customerUid") === fixture.attendee.uid && registration.get("status") === "confirmed",
        message: message?.exists && message.get("senderId") === fixture.owner.uid && message.get("conversationId") === fixture.conversationId,
        feedback: feedback?.exists && feedback.get("eventId") === fixture.event.id && feedback.get("userId") === fixture.attendee.uid,
        adminOperation: adminOperation.get("status") === "completed" && adminOperation.get("actorUid") === fixture.administrator.uid},
      deletion: {uid: fixture.deletion.uid, authenticationExists, profileExists: profile.exists, userExists: user.exists,
        appFeedbackExists: appFeedback?.exists ?? null, status: deleting.get("status") || null,
        verificationRecorded: Array.isArray(deleting.get("verification")?.remaining),
        remaining: (deleting.get("verification")?.remaining || []).length}};
  };
}

async function runBrowserCommunications({fixture, candidateIdentity, candidate, priorEvidence = [], callAs, observe, timeoutMs = 360000, pollIntervalMs = 3000}) {
  const identity = validateCommunications(fixture, candidateIdentity), spec = fixture.communications;
  if (typeof callAs !== "function" || typeof observe !== "function" || !(timeoutMs > 0 && timeoutMs <= 600000) ||
      !(pollIntervalMs >= 0 && pollIntervalMs <= 15000)) throw Error("Bounded authenticated communication adapters are required.");
  const report = {schemaVersion: 1, identity, startedAt: new Date().toISOString(), assertions: [], observations: [], receipts: {}};
  const check = (id, expected, actual) => {
    report.assertions.push({id, expected, actual: actual ?? null});
    if (!isDeepStrictEqual(expected, actual)) throw Error(`Communications assertion failed: ${id}`);
  };
  const call = async (role, name, data) => {await observe({guardOnly: true}); return callAs(role, name, data);};
  const poll = async (read, ready) => {
    const end = Date.now() + timeoutMs;
    for (;;) {
      const result = await read();
      if (ready(result)) return result;
      if (Date.now() >= end) throw Error("Communication receipts or private captures did not become observable.");
      await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
    }
  };
  try {
    const initial = await observe(); report.observations.push({phase: "before", ...initial});
    const priorDeletion = initial.deletion.authenticationExists ? null : previousDeletion({candidate, candidateIdentity, identity, priorEvidence, fixture});
    if (!priorDeletion) check("disposable_account_exists_before_authentication", true, initial.deletion.authenticationExists && initial.deletion.profileExists);
    const conversation = await call("owner", "getOrCreateDirectConversationV2", {otherUserId: fixture.attendee.uid});
    check("conversation_bound_to_fixture", fixture.conversationId, conversation.conversationId);
    const messageInput = {conversationId: conversation.conversationId, requestId: `${fixture.runId}:message`, content: "Controlled communication capture."};
    const message = await call("owner", "sendConversationMessageV2", messageInput);
    check("message_receipt_id", true, safeId(message.messageId));
    report.receipts.messageId = message.messageId;
    check("message_idempotent_retry", message.messageId, (await call("owner", "sendConversationMessageV2", messageInput)).messageId);
    const feedback = await call("attendee", "communityMutationV1", {action: "submitFeedback", eventId: fixture.event.id,
      rating: 5, comment: "Controlled qualification feedback.", isAnonymous: false});
    check("feedback_receipt_id", true, safeId(feedback.feedbackId));
    report.receipts.feedbackId = feedback.feedbackId;
    const notification = await call("administrator", "sendCustomNotifications", {confirmation: true,
      reason: "Controlled isolated staging capture qualification", idempotencyKey: `${fixture.runId}:admin-notification`,
      userIds: [fixture.attendee.uid], title: "Controlled administrative capture", body: "Synthetic qualification only.", type: "event_update", data: {eventId: fixture.event.id}});
    check("admin_transport_not_handed_to_provider", [0, 0], [notification.pushSuccessCount, notification.pushFailureCount]);
    const registration = await call("attendee", "startPublicRegistrationV3", {eventId: spec.reminderEventId,
      idempotencyKey: `${fixture.runId}:reminder-registration`, fullName: "Controlled reminder attendee", email: fixture.attendee.email, answers: {}});
    check("future_event_registration_confirmed", "confirmed", registration.status);
    check("future_registration_receipt_id", true, safeId(registration.registrationId));
    report.receipts.registrationId = registration.registrationId;
    const selection = {...report.receipts};
    const proof = await poll(() => observe(selection), (value) => {
      const has = (predicate) => value.captures.some(predicate);
      return Object.values(value.sourceReceipts).every((match) => match === true) &&
        has((row) => row.sourceKey === `message:${message.messageId}` && row.recipientUid === fixture.attendee.uid) &&
        has((row) => row.sourceKey.startsWith(`legacy:feedback:event_feedback/${feedback.feedbackId}:`) && row.recipientUid === fixture.owner.uid) &&
        has((row) => row.sourceKey === `admin:${hash(`sendCustomNotifications:${fixture.administrator.uid}:${fixture.runId}:admin-notification`)}` && row.recipientUid === fixture.attendee.uid) &&
        has((row) => row.sourceKey === `pending:${spec.pendingPushId}` && row.recipientUid === fixture.attendee.uid) &&
        value.pending.sourceMatches && value.pending.status === "qualification_capture" && value.reminder.jobs.length > 0 &&
        (value.discovery.items.length > 0 || value.discovery.deliveries.length > 0 || has((row) => row.sourceKey.startsWith("discovery:") && row.eventIds.includes(spec.discoveryEventId)));
    });
    check("all_observed_captures_are_valid_and_isolated", true, proof.captures.every((row) => row.valid && row.provider === "qualification_capture"));
    check("reminder_source_not_failed_or_expired", true, proof.reminder.jobs.every((job) => ["pending", "processing", "retry", "captured"].includes(job.status) &&
      Number.isFinite(Date.parse(job.dueAt)) && Number.isFinite(Date.parse(job.deadlineAt))));
    check("reminder_preserves_actual_scheduled_offset", true, proof.reminder.jobs.every((job) =>
      [15, 30, 60, 120, 1440].includes(job.reminderMinutes) && Date.parse(proof.reminder.startsAt) - Date.parse(job.dueAt) === job.reminderMinutes * 60000));
    check("discovery_preserves_real_45_minute_delay", true,
      proof.discovery.items.some((item) => Number.isFinite(Date.parse(item.queuedAt)) && Date.parse(item.readyAt) - Date.parse(item.queuedAt) >= 45 * 60000 - 1000) ||
      proof.discovery.deliveries.some((item) => Date.parse(item.createdAt) - Date.parse(proof.discovery.createdAt) >= 45 * 60000 - 1000) ||
      proof.captures.some((row) => row.sourceKey.startsWith("discovery:") && row.eventIds.includes(spec.discoveryEventId) &&
        Date.parse(row.capturedAt) - Date.parse(proof.discovery.createdAt) >= 45 * 60000 - 1000));
    report.observations.push({phase: "communication_sources_and_immediate_captures", ...proof});
    // These are actual pending timer receipts, not delivery-success assertions.
    // The backend producer later requires real reminder/discovery captures.
    report.timers = {reminder: proof.reminder, discovery: proof.discovery};
    if (priorDeletion) {
      report.receipts.appFeedbackId = priorDeletion.receipts.appFeedbackId;
      report.priorDeletion = priorDeletion.provenance;
    } else {
      const appFeedback = await call("deletion", "communityMutationV1", {action: "submitAppFeedback", submissionId: `${fixture.runId}-deletion-feedback`,
        rating: 4, comment: "Disposable account deletion fixture.", isAnonymous: false});
      check("disposable_feedback_receipt_id", true, safeId(appFeedback.feedbackId));
      report.receipts.appFeedbackId = appFeedback.feedbackId;
      const beforeDeletion = await observe({...selection, appFeedbackId: appFeedback.feedbackId});
      check("disposable_personal_data_exists_before_deletion", true, beforeDeletion.deletion.appFeedbackExists);
      report.deletionAttempt = {uid: fixture.deletion.uid, requestedAt: new Date().toISOString()};
      try {
        const deleted = await call("deletion", "deleteUserAccount", {});
        report.deletionAttempt.responseStatus = deleted.status;
        check("authenticated_account_deletion_completed", "complete", deleted.status);
      } catch (error) {
        // A lost response is reconciled by observing this original request.
        // Never automatically issue another destructive mutation.
        report.deletionAttempt.responseStatus = "unknown";
        report.deletionAttempt.errorCode = String(error.code || error.status || "transport_unknown").replace(/[^a-zA-Z_-]/g, "").slice(0, 60);
      }
    }
    const after = await poll(() => observe({...selection, appFeedbackId: report.receipts.appFeedbackId}), (value) =>
      value.deletion.status === "complete" && !value.deletion.authenticationExists);
    check("deleted_auth_profile_user_feedback_absent", [false, false, false, false], [after.deletion.authenticationExists,
      after.deletion.profileExists, after.deletion.userExists, after.deletion.appFeedbackExists]);
    check("deletion_job_completed_without_remaining_data", ["complete", 0], [after.deletion.status, after.deletion.remaining]);
    check("deletion_inventory_verification_recorded", true, after.deletion.verificationRecorded);
    report.receipts.deletedUid = fixture.deletion.uid;
    report.observations.push({phase: "after_deletion", deletion: after.deletion});
    report.completedAt = new Date().toISOString();
    return report;
  } catch (error) {error.communicationsReport = report; throw error;}
}

module.exports = {runBrowserCommunications, createCommunicationsObserver, validateCommunications, previousDeletion};
