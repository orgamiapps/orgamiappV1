"use strict";

const crypto = require("node:crypto");
const {onRequest} = require("firebase-functions/v2/https");
const {authorize} = require("./auth");
const {AdminError, fail} = require("./errors");
const validate = require("./validation");
const {rateLimit} = require("./rate-limit");
const {runIdempotent} = require("./idempotency");
const {writeAudit} = require("./audit");
const {PLAN_PRICE_ENV} = require("./constants");
const {canAssignRoles} = require("./rbac");
const {planForPrice, tierForPlan} = require("./subscriptions");
const {CONTACT_KMS_KEY_NAME, decryptContact, encryptContact,
  maskedContact, normalizeContact} = require("../public-web/accountless");

const asIso = (value) => value && typeof value.toDate === "function" ? value.toDate().toISOString() : value instanceof Date ? value.toISOString() : value || null;
const pageToken = (value) => value ? Buffer.from(String(value), "utf8").toString("base64url") : null;
const decodePage = (value) => {
  try {
    return value ? Buffer.from(value, "base64url").toString("utf8") : null;
  } catch (_) {
    fail(400, "INVALID_PAGE_TOKEN", "The page token is invalid.");
  }
};
const docDto = (doc, fields) => Object.fromEntries([["id", doc.id], ...fields.map((key) => [key, key.endsWith("At") || key.endsWith("Date") ? asIso(doc.get(key)) : doc.get(key) ?? null])]);

function json(res, status, body, requestId) {
  res.status(status).json({...body, meta: {...body.meta, requestId}});
}
function routePath(req) {
  return (req.path || req.url.split("?")[0]).replace(/\/+$/, "") || "/";
}

function createAdminApi(adminSdk) {
  const db = adminSdk.firestore();

  async function listCollection(req, collection, permission, fields, orderField = "__name__") {
    const actor = await authorize(req, adminSdk, db, permission);
    const size = validate.limit(req.query.limit);
    let query = db.collection(collection).orderBy(orderField).limit(size + 1);
    const cursor = decodePage(req.query.pageToken);
    if (cursor) {
      const snap = await db.collection(collection).doc(cursor).get();
      if (!snap.exists) fail(400, "INVALID_PAGE_TOKEN", "The page token no longer exists.");
      query = db.collection(collection).orderBy(orderField).startAfter(snap).limit(size + 1);
    }
    const result = await query.get();
    return {actor, data: result.docs.slice(0, size).map((doc) => docDto(doc, fields)), nextPageToken: result.size > size ? pageToken(result.docs[size - 1].id) : null};
  }

  async function accounts(req) {
    const actor = await authorize(req, adminSdk, db, "accounts.read");
    const size = validate.limit(req.query.limit);
    const search = String(req.query.search || "").trim();
    let users;
    if (search) {
      try {
        const user = search.includes("@") ? await adminSdk.auth().getUserByEmail(search) : await adminSdk.auth().getUser(search);
        users = {users: [user], pageToken: undefined};
      } catch (_) {
        const snap = await db.collection("Customers").where("name", ">=", search).where("name", "<=", `${search}\uf8ff`).limit(size).get();
        const resolved = await Promise.all(snap.docs.map((doc) => adminSdk.auth().getUser(doc.id).catch(() => null)));
        users = {users: resolved.filter(Boolean), pageToken: undefined};
      }
    } else {
      users = await adminSdk.auth().listUsers(size, req.query.pageToken || undefined);
    }
    const profileRefs = users.users.map((user) => db.collection("Customers").doc(user.uid));
    const profiles = profileRefs.length ? await db.getAll(...profileRefs) : [];
    return {actor, data: users.users.map((user, index) => ({uid: user.uid, email: user.email || null, displayName: user.displayName || profiles[index]?.get("name") || null, disabled: user.disabled, emailVerified: user.emailVerified, createdAt: user.metadata.creationTime || null, lastSignInAt: user.metadata.lastSignInTime || null, tier: null})), nextPageToken: users.pageToken || null};
  }

  async function accountDetail(req, uid) {
    const actor = await authorize(req, adminSdk, db, "accounts.read");
    const [user, profile, subscription, eventCount, attendanceCount, orgCount] = await Promise.all([
      adminSdk.auth().getUser(uid).catch(() => fail(404, "ACCOUNT_NOT_FOUND", "Account not found.")),
      db.collection("Customers").doc(uid).get(),
      db.collection("subscriptions").doc(uid).get(),
      db.collection("Events").where("customerUid", "==", uid).count().get(),
      db.collection("Attendance").where("customerUid", "==", uid).count().get(),
      db.collection("Organizations").where("createdBy", "==", uid).count().get(),
    ]);
    return {actor, data: {auth: {uid, email: user.email || null, displayName: user.displayName || null, disabled: user.disabled, emailVerified: user.emailVerified, providers: user.providerData.map((p) => p.providerId), createdAt: user.metadata.creationTime, lastSignInAt: user.metadata.lastSignInTime}, profile: profile.exists ? docDto(profile, ["name", "email", "username", "phoneNumber", "location", "company", "createdAt", "eventsCreated", "groupsCreated"]) : null, subscription: subscription.exists ? docDto(subscription, ["planId", "tier", "status", "stripeCustomerId", "stripeSubscriptionId", "currentPeriodEnd", "trialEndsAt", "scheduledPlanId", "scheduledPlanStartDate"]) : null, activity: {events: eventCount.data().count, registrations: attendanceCount.data().count, groups: orgCount.data().count}}};
  }

  async function subscriptions(req) {
    const search = String(req.query.search || "").trim();
    if (!search) return listCollection(req, "subscriptions", "subscriptions.read", ["userId", "planId", "tier", "status", "stripeCustomerId", "stripeSubscriptionId", "currentPeriodEnd", "isTrial", "trialEndsAt", "scheduledPlanId", "scheduledPlanStartDate", "paymentState"]);
    const actor = await authorize(req, adminSdk, db, "subscriptions.read");
    let uid = search;
    if (search.includes("@")) {
      const user = await adminSdk.auth().getUserByEmail(search).catch(() => null);
      if (!user) return {actor, data: [], nextPageToken: null};
      uid = user.uid;
    }
    let snapshots = [];
    const direct = await db.collection("subscriptions").doc(uid).get();
    if (direct.exists) snapshots = [direct];
    else {
      for (const field of ["stripeCustomerId", "stripeSubscriptionId", "status", "tier", "planId"]) {
        const found = await db.collection("subscriptions").where(field, "==", search).limit(100).get();
        if (!found.empty) {
          snapshots = found.docs; break;
        }
      }
    }
    const fields = ["userId", "planId", "tier", "status", "stripeCustomerId", "stripeSubscriptionId", "currentPeriodEnd", "isTrial", "trialEndsAt", "scheduledPlanId", "scheduledPlanStartDate", "paymentState"];
    return {actor, data: snapshots.map((doc) => docDto(doc, fields)), nextPageToken: null};
  }

  async function metrics(req) {
    const actor = await authorize(req, adminSdk, db, "audit.read");
    const from = String(req.query.from || "0000-00-00");
    const to = String(req.query.to || "9999-99-99");
    const current = await db.collection("admin_metrics_current").doc("current").get();
    const daily = await db.collection("admin_metrics_daily").where("__name__", ">=", from).where("__name__", "<=", to).orderBy("__name__").limit(366).get();
    return {actor, data: {current: current.exists ? current.data() : {}, daily: daily.docs.map((doc) => ({date: doc.id, ...doc.data()}))}};
  }

  async function dailyMetrics(req) {
    const result = await metrics(req);
    await authorize(req, adminSdk, db, "analytics.read");
    return {actor: result.actor, data: result.data.daily, nextPageToken: null};
  }

  async function guestFunnel(req) {
    const actor = await authorize(req, adminSdk, db, "analytics.read");
    const from = String(req.query.from || "0000-00-00");
    const to = String(req.query.to || "9999-99-99");
    if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to) || from > to) {
      fail(400, "INVALID_DATE_RANGE", "Use a valid from/to date range.");
    }
    const snapshot = await db.collection("admin_funnel_daily")
        .where("__name__", ">=", from).where("__name__", "<=", to)
        .orderBy("__name__").limit(366).get();
    const totals = {};
    const byEntryPoint = {};
    const byCheckInMethod = {};
    const byFeature = {};
    let sessions = 0;
    const merge = (target, values) => Object.entries(values || {}).forEach(([key, value]) => {
      target[key] = Number(target[key] || 0) + Number(value || 0);
    });
    const daily = snapshot.docs.map((doc) => {
      const row = doc.data();
      merge(totals, row.counts);
      merge(byEntryPoint, row.byEntryPoint);
      merge(byCheckInMethod, row.byCheckInMethod);
      merge(byFeature, row.byFeature);
      sessions += Number(row.sessions || 0);
      return {date: doc.id, ...row, updatedAt: asIso(row.updatedAt)};
    });
    const rate = (numerator, denominator) => denominator > 0 ? numerator / denominator : 0;
    return {actor, data: {
      totals,
      sessions,
      conversion: {
        auth: rate(totals.guest_auth_completed || 0, totals.guest_auth_started || 0),
        checkIn: rate(totals.guest_checkin_completed || 0, totals.guest_checkin_started || 0),
      },
      byEntryPoint,
      byCheckInMethod,
      byFeature,
      daily,
    }};
  }

  async function discoveryMarketHealth(req) {
    const actor = await authorize(req, adminSdk, db, "analytics.read");
    const now = new Date();
    const end = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
    const [events, funnel] = await Promise.all([
      db.collection("Events")
          .where("selectedDateTime", ">=", adminSdk.firestore.Timestamp.fromDate(now))
          .where("selectedDateTime", "<", adminSdk.firestore.Timestamp.fromDate(end))
          .orderBy("selectedDateTime").limit(5000).get(),
      db.collection("product_funnel_events")
          .where("occurredAt", ">=", adminSdk.firestore.Timestamp.fromDate(
              new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000),
          )).limit(5000).get(),
    ]);
    const markets = new Map();
    const market = (key, city = "Unknown", regionCode = "") => {
      if (!markets.has(key)) markets.set(key, {metro: key, city, regionCode,
        upcomingInventory: 0, organizers: new Set(), categories: {},
        searches: 0, noResults: 0, cardOpens: 0, registrations: 0,
        missingCategories: {}});
      return markets.get(key);
    };
    for (const document of events.docs) {
      const data = document.data();
      const status = String(data.status || "").toLowerCase();
      if (data.private === true || ["draft", "pending", "pending_approval",
        "unpublished", "cancelled", "canceled", "declined"].includes(status)) continue;
      const city = String(data.city || "Unknown");
      const region = String(data.regionCode || "");
      const key = `${city}-${region}`.toLowerCase().replace(/[^a-z0-9-]/g, "-");
      const row = market(key, city, region);
      row.upcomingInventory += 1;
      if (data.customerUid) row.organizers.add(String(data.customerUid));
      for (const category of data.categories || []) {
        row.categories[category] = Number(row.categories[category] || 0) + 1;
      }
    }
    for (const document of funnel.docs) {
      const data = document.data();
      const dimensions = data.dimensions || {};
      if (!dimensions.metro) continue;
      const row = market(dimensions.metro);
      if (data.event === "discovery_search_results" || data.event === "discovery_search_no_result") row.searches += 1;
      if (data.event === "discovery_search_no_result") {
        row.noResults += 1;
        if (dimensions.category) row.missingCategories[dimensions.category] =
          Number(row.missingCategories[dimensions.category] || 0) + 1;
      }
      if (data.event === "discovery_card_open") row.cardOpens += 1;
      if (data.event === "discovery_registration_complete") row.registrations += 1;
    }
    const data = [...markets.values()].map((row) => ({
      ...row,
      activeOrganizers: row.organizers.size,
      organizers: undefined,
      healthy: row.upcomingInventory >= 10 && row.organizers.size >= 3,
      noResultRate: row.searches ? row.noResults / row.searches : 0,
      topMissingCategories: Object.entries(row.missingCategories)
          .sort((a, b) => b[1] - a[1]).slice(0, 5)
          .map(([category, count]) => ({category, count})),
      missingCategories: undefined,
    })).sort((a, b) => b.upcomingInventory - a.upcomingInventory);
    return {actor, data};
  }

  async function communicationMessages(req) {
    return listCollection(req, "OutboundMessages", "communications.read",
        ["templateId", "channel", "status", "maskedContact", "attempts", "provider",
          "providerStatus", "lastError", "createdAt", "acceptedAt"], "createdAt");
  }

  async function guestRegistrations(req) {
    return listCollection(req, "GuestAttendees", "communications.read",
        ["fullName", "contactType", "maskedContact", "deliveryStatus", "verificationStatus",
          "claimedByUid", "createdAt", "retentionAt"], "createdAt");
  }

  async function guestRegistrationDetail(req, id) {
    const actor = await authorize(req, adminSdk, db, "communications.read");
    const snapshot = await db.collection("GuestAttendees").doc(id).get();
    if (!snapshot.exists) fail(404, "GUEST_NOT_FOUND", "Guest registration was not found.");
    const contact = await decryptContact(snapshot.get("encryptedContact"));
    await writeAudit(db, adminSdk, {actor, action: "communications.guest_contact.view",
      targetType: "guest", targetId: id, reason: "Administrative guest detail view",
      requestId: req.requestId, metadata: {contactType: contact.type}});
    return {actor, data: {...docDto(snapshot, ["fullName", "contactType", "maskedContact",
      "deliveryStatus", "verificationStatus", "claimedByUid", "createdAt", "retentionAt"]),
    contact: contact.display || contact.value}};
  }

  async function retryCommunication(req, id) {
    const actor = await authorize(req, adminSdk, db, "communications.mutate");
    return mutate(req, actor, {action: "communications.message.retry",
      targetType: "outbound_message", targetId: id, destructive: false}, async () => {
      const ref = db.collection("OutboundMessages").doc(id);
      const before = await ref.get();
      if (!before.exists) fail(404, "MESSAGE_NOT_FOUND", "Outbound message was not found.");
      if (!["failed", "dead_letter", "retry"].includes(before.get("status"))) {
        fail(409, "MESSAGE_NOT_RETRYABLE", "Only failed messages can be retried.");
      }
      const after = {status: "pending", nextAttemptAt: new Date(), lastError: null,
        retriedBy: actor.uid, retriedAt: adminSdk.firestore.FieldValue.serverTimestamp()};
      await ref.update(after);
      return {before: before.data(), after, response: {status: "pending"}};
    });
  }

  async function testCommunication(req) {
    const actor = await authorize(req, adminSdk, db, "communications.mutate");
    return mutate(req, actor, {action: "communications.test_send", targetType: "provider",
      targetId: String(req.body.contactType || "unknown"), destructive: false}, async () => {
      const contact = normalizeContact(req.body.contactType, req.body.contactValue);
      const encryptedContact = await encryptContact(contact);
      const ref = db.collection("OutboundMessages").doc(`admin_test_${crypto.randomUUID()}`);
      const message = {id: ref.id, templateId: "guest_registration_confirmation",
        channel: contact.type === "phone" ? "sms" : "email", status: "pending", attempts: 0,
        encryptedContact, maskedContact: maskedContact(contact), isProviderTest: true,
        payload: {firstName: "Attendus", eventTitle: "Attendus communications test",
          eventStart: new Date(Date.now() + 86400000), eventLocation: "Attendus",
          kind: "rsvp", manageUrl: "https://attendus.app"},
        createdAt: adminSdk.firestore.FieldValue.serverTimestamp(), nextAttemptAt: new Date(),
        requestedBy: actor.uid};
      await ref.create(message);
      return {before: null, after: {id: ref.id, channel: message.channel, status: "pending"},
        response: {messageId: ref.id, status: "pending", maskedContact: message.maskedContact}};
    });
  }

  async function communicationTemplates(req) {
    const actor = await authorize(req, adminSdk, db, "communications.read");
    const ids = ["guest_registration_confirmation", "guest_registration_cancelled"];
    const snapshots = await db.getAll(...ids.map((id) => db.collection("CommunicationTemplates").doc(id)));
    return {actor, data: snapshots.map((snapshot, index) => snapshot.exists ?
      docDto(snapshot, ["name", "channel", "status", "version", "updatedBy", "updatedAt"]) :
      {id: ids[index], name: ids[index].replaceAll("_", " "), channel: "email_sms",
        status: "fallback", version: 0, updatedBy: null, updatedAt: null}), nextPageToken: null};
  }

  async function communicationTemplateDetail(req, id) {
    const actor = await authorize(req, adminSdk, db, "communications.read");
    const snapshot = await db.collection("CommunicationTemplates").doc(id).get();
    return {actor, data: snapshot.exists ? {id: snapshot.id, ...snapshot.data()} :
      {id, status: "fallback", version: 0,
        subject: id.endsWith("cancelled") ? "Registration cancelled: {{eventTitle}}" :
          "You're confirmed for {{eventTitle}}",
        text: "Hi {{firstName}}, view your Attendus registration: {{manageUrl}}",
        html: "<h1>{{eventTitle}}</h1><p>Hi {{firstName}},</p><p><a href=\"{{manageUrl}}\">View your registration</a></p>",
        sms: "Attendus: {{eventTitle}}. {{manageUrl}} Help: {{supportEmail}}. Reply STOP to opt out."}};
  }

  async function publishTemplate(req, id) {
    const actor = await authorize(req, adminSdk, db, "communications.mutate");
    return mutate(req, actor, {action: "communications.template.publish",
      targetType: "communication_template", targetId: id}, async () => {
      const allowed = new Set(["guest_registration_confirmation", "guest_registration_cancelled"]);
      if (!allowed.has(id)) fail(400, "INVALID_TEMPLATE", "Unsupported template identifier.");
      const fields = ["subject", "text", "html", "sms"];
      const content = Object.fromEntries(fields.map((field) => [field,
        validate.string(req.body[field] || "", field, {min: field === "sms" ? 1 : 0,
          max: field === "html" ? 20000 : 2000})]));
      const unknown = [...String(content.html).matchAll(/\{\{([^}]+)\}\}/g)]
          .map((match) => match[1]).filter((key) =>
            !["firstName", "eventTitle", "manageUrl", "supportEmail"].includes(key));
      if (unknown.length) fail(400, "INVALID_PLACEHOLDER", "Template contains an unknown placeholder.");
      const ref = db.collection("CommunicationTemplates").doc(id);
      const before = await ref.get();
      const version = Number(before.get("version") || 0) + 1;
      const after = {...content, id, name: id.replaceAll("_", " "), channel: "email_sms",
        status: "published", version, updatedBy: actor.uid,
        updatedAt: adminSdk.firestore.FieldValue.serverTimestamp()};
      await ref.set(after);
      return {before: before.data() || null, after, response: {status: "published", version}};
    });
  }

  async function moderationMutation(req, collection, id, action, permission) {
    const actor = await authorize(req, adminSdk, db, permission);
    return mutate(req, actor, {action: `${collection}.${action}`, targetType: collection, targetId: id}, async () => {
      const ref = db.collection(collection).doc(id);
      const before = await ref.get();
      if (!before.exists) fail(404, "NOT_FOUND", "The target record was not found.");
      const updates = collection === "reports" ?
        {status: action === "resolve" ? "resolved" : "dismissed", resolvedBy: actor.uid, resolvedAt: adminSdk.firestore.FieldValue.serverTimestamp()} :
        collection === "Events" ?
          {status: "unpublished", moderationReason: req.body.reason, moderatedBy: actor.uid, moderatedAt: adminSdk.firestore.FieldValue.serverTimestamp()} :
          {adminStatus: "suspended", moderationReason: req.body.reason, moderatedBy: actor.uid, moderatedAt: adminSdk.firestore.FieldValue.serverTimestamp()};
      await ref.update(updates);
      return {before: before.data(), after: updates, response: {status: updates.status || updates.adminStatus}};
    });
  }

  async function mutate(req, actor, spec, operation) {
    const reason = validate.mutation(req.body, spec.destructive !== false);
    const key = req.get("idempotency-key");
    return runIdempotent(db, adminSdk, actor.uid, key, async () => {
      const result = await operation(reason);
      const auditId = await writeAudit(db, adminSdk, {actor, action: spec.action, targetType: spec.targetType, targetId: spec.targetId, reason, requestId: req.requestId, before: result.before, after: result.after, metadata: result.metadata});
      return {ok: true, auditId, ...result.response};
    });
  }

  async function accountMutation(req, uid, action) {
    const actor = await authorize(req, adminSdk, db, action === "roles" ? "roles.mutate" : "accounts.mutate");
    return mutate(req, actor, {action: `account.${action}`, targetType: "account", targetId: uid}, async () => {
      const beforeUser = await adminSdk.auth().getUser(uid).catch(() => fail(404, "ACCOUNT_NOT_FOUND", "Account not found."));
      if (action === "disable" || action === "enable") {
        const disabled = action === "disable";
        await adminSdk.auth().updateUser(uid, {disabled});
        return {before: {disabled: beforeUser.disabled}, after: {disabled}, response: {disabled}};
      }
      if (action === "revoke-sessions") {
        await adminSdk.auth().revokeRefreshTokens(uid);
        return {before: {}, after: {sessionsRevoked: true}, response: {sessionsRevoked: true}};
      }
      if (action === "password-reset") {
        if (!beforeUser.email) fail(409, "ACCOUNT_HAS_NO_EMAIL", "This account has no email address.");
        const link = await adminSdk.auth().generatePasswordResetLink(beforeUser.email);
        return {before: {}, after: {resetGenerated: true}, response: {resetLink: link}};
      }
      if (action === "anonymize") {
        const job = db.collection("admin_jobs").doc();
        await job.create({type: "account_anonymization", targetUid: uid, status: "pending", reason: req.body.reason, requestedBy: actor.uid, createdAt: adminSdk.firestore.FieldValue.serverTimestamp()});
        return {before: {email: beforeUser.email || null}, after: {jobId: job.id, status: "pending"}, response: {jobId: job.id, status: "pending"}};
      }
      if (action === "roles") {
        const roles = req.body.roles;
        if (!canAssignRoles(actor.roles, roles)) fail(403, "PERMISSION_DENIED", "Only super administrators can assign supported roles.");
        if (uid === actor.uid && !roles.includes("super_admin")) fail(409, "SELF_LOCKOUT", "You cannot remove your own super administrator role.");
        const before = await db.collection("admin_roles").doc(uid).get();
        await db.collection("admin_roles").doc(uid).set({roles: [...new Set(roles)], active: req.body.active !== false, updatedBy: actor.uid, updatedAt: adminSdk.firestore.FieldValue.serverTimestamp()}, {merge: true});
        const target = await adminSdk.auth().getUser(uid);
        await adminSdk.auth().setCustomUserClaims(uid, {...target.customClaims, admin: true});
        return {before: before.data() || null, after: {roles, active: req.body.active !== false}, response: {roles, active: req.body.active !== false}};
      }
      fail(404, "NOT_FOUND", "Unknown account action.");
    });
  }

  function stripeClient() {
    if (!process.env.STRIPE_SECRET_KEY) fail(503, "BILLING_NOT_CONFIGURED", "Stripe billing credentials are not configured.");
    return new (require("stripe"))(process.env.STRIPE_SECRET_KEY, {apiVersion: "2024-06-20"});
  }
  function configuredPrice(planId) {
    validate.enumeration(planId, "planId", Object.keys(PLAN_PRICE_ENV));
    const value = process.env[PLAN_PRICE_ENV[planId]];
    if (!value) fail(503, "PLAN_NOT_CONFIGURED", "The selected plan is not configured.");
    return value;
  }
  async function subscriptionMutation(req, uid, action) {
    const actor = await authorize(req, adminSdk, db, "subscriptions.mutate");
    return mutate(req, actor, {action: `subscription.${action}`, targetType: "subscription", targetId: uid}, async () => {
      const ref = db.collection("subscriptions").doc(uid);
      const local = await ref.get();
      if (!local.exists || !local.get("stripeSubscriptionId")) fail(404, "SUBSCRIPTION_NOT_FOUND", "A Stripe-backed subscription was not found.");
      const stripe = stripeClient();
      const sid = local.get("stripeSubscriptionId");
      let stripeSub;
      if (action === "cancel") stripeSub = await stripe.subscriptions.update(sid, {cancel_at_period_end: true});
      else if (action === "reactivate") stripeSub = await stripe.subscriptions.update(sid, {cancel_at_period_end: false});
      else if (action === "change-plan") {
        const price = configuredPrice(req.body.planId);
        const current = await stripe.subscriptions.retrieve(sid);
        if (!current.items.data[0]) fail(409, "STRIPE_ITEM_MISSING", "The Stripe subscription has no item.");
        stripeSub = await stripe.subscriptions.update(sid, {items: [{id: current.items.data[0].id, price}], proration_behavior: "none"});
      } else if (action === "sync") stripeSub = await stripe.subscriptions.retrieve(sid);
      else if (action === "refund") {
        const paymentIntent = validate.string(req.body.paymentIntentId, "paymentIntentId", {min: 5, max: 200});
        const refund = await stripe.refunds.create({payment_intent: paymentIntent, metadata: {adminUid: actor.uid, reason: req.body.reason}});
        return {before: local.data(), after: {refundId: refund.id, refundStatus: refund.status}, response: {refundId: refund.id, status: refund.status}};
      } else fail(404, "NOT_FOUND", "Unknown subscription action.");
      const item = stripeSub.items.data[0];
      const priceId = item?.price?.id || null;
      const planId = planForPrice(priceId, process.env, local.get("planId") || null);
      const tier = tierForPlan(planId);
      const derived = {status: stripeSub.status, planId, tier, cancelAtPeriodEnd: stripeSub.cancel_at_period_end, currentPeriodEnd: adminSdk.firestore.Timestamp.fromMillis(stripeSub.current_period_end * 1000), updatedAt: adminSdk.firestore.FieldValue.serverTimestamp(), stripeSyncAt: adminSdk.firestore.FieldValue.serverTimestamp()};
      await ref.set(derived, {merge: true});
      return {before: local.data(), after: {...derived, currentPeriodEnd: asIso(derived.currentPeriodEnd)}, response: {status: stripeSub.status, planId, tier, cancelAtPeriodEnd: stripeSub.cancel_at_period_end}};
    });
  }

  return onRequest({region: "us-central1", timeoutSeconds: 60, memory: "512MiB", cors: false,
    secrets: [CONTACT_KMS_KEY_NAME]}, async (req, res) => {
    req.requestId = req.get("x-request-id") || crypto.randomUUID();
    res.set("x-request-id", req.requestId);
    res.set("cache-control", "no-store");
    try {
      if (req.method === "OPTIONS") {
        res.set("access-control-allow-origin", "https://localhost"); res.set("access-control-allow-headers", "authorization,content-type,idempotency-key,x-request-id"); res.set("access-control-allow-methods", "GET,POST"); return res.status(204).send("");
      }
      const path = routePath(req);
      let result;
      if (path === "/v1/me" && req.method === "GET") {
        const actor = await authorize(req, adminSdk, db, "accounts.read"); result = {data: actor};
      } else if (path === "/v1/accounts" && req.method === "GET") result = await accounts(req);
      else if (/^\/v1\/accounts\/[^/]+$/.test(path) && req.method === "GET") result = await accountDetail(req, path.split("/")[3]);
      else if (/^\/v1\/accounts\/[^/]+\/(disable|enable|revoke-sessions|password-reset|anonymize|roles)$/.test(path) && req.method === "POST") {
        const parts = path.split("/"); result = {data: await accountMutation(req, parts[3], parts[4])};
      } else if (path === "/v1/subscriptions" && req.method === "GET") result = await subscriptions(req);
      else if (/^\/v1\/subscriptions\/[^/]+\/(cancel|reactivate|change-plan|sync|refund)$/.test(path) && req.method === "POST") {
        const parts = path.split("/"); result = {data: await subscriptionMutation(req, parts[3], parts[4])};
      } else if (path === "/v1/metrics" && req.method === "GET") result = await metrics(req);
      else if (path === "/v1/metrics/daily" && req.method === "GET") result = await dailyMetrics(req);
      else if (path === "/v1/guest-funnel" && req.method === "GET") result = await guestFunnel(req);
      else if (path === "/v1/discovery/market-health" && req.method === "GET") result = await discoveryMarketHealth(req);
      else if (path === "/v1/communications/messages" && req.method === "GET") result = await communicationMessages(req);
      else if (/^\/v1\/communications\/messages\/[^/]+\/retry$/.test(path) && req.method === "POST") {
        result = {data: await retryCommunication(req, path.split("/")[4])};
      } else if (path === "/v1/communications/guests" && req.method === "GET") result = await guestRegistrations(req);
      else if (path === "/v1/communications/test" && req.method === "POST") {
        result = {data: await testCommunication(req)};
      }
      else if (/^\/v1\/communications\/guests\/[^/]+$/.test(path) && req.method === "GET") {
        result = await guestRegistrationDetail(req, path.split("/")[4]);
      } else if (path === "/v1/communications/templates" && req.method === "GET") result = await communicationTemplates(req);
      else if (/^\/v1\/communications\/templates\/[^/]+$/.test(path) && req.method === "GET") {
        result = await communicationTemplateDetail(req, path.split("/")[4]);
      }
      else if (/^\/v1\/communications\/templates\/[^/]+\/publish$/.test(path) && req.method === "POST") {
        result = {data: await publishTemplate(req, path.split("/")[4])};
      }
      else if (path === "/v1/reports" && req.method === "GET") result = await listCollection(req, "reports", "moderation.read", ["type", "reason", "details", "status", "reporterUid", "targetUid", "eventId", "createdAt"], "createdAt");
      else if (/^\/v1\/reports\/[^/]+\/(resolve|dismiss)$/.test(path) && req.method === "POST") {
        const parts = path.split("/"); result = {data: await moderationMutation(req, "reports", parts[3], parts[4], "moderation.mutate")};
      } else if (path === "/v1/events" && req.method === "GET") result = await listCollection(req, "Events", "events.read", ["title", "status", "customerUid", "organizationId", "selectedDateTime", "private", "issuedTickets"]);
      else if (/^\/v1\/events\/[^/]+\/unpublish$/.test(path) && req.method === "POST") {
        const parts = path.split("/"); result = {data: await moderationMutation(req, "Events", parts[3], "unpublish", "events.mutate")};
      } else if (path === "/v1/organizations" && req.method === "GET") result = await listCollection(req, "Organizations", "organizations.read", ["name", "category", "createdBy", "createdAt", "defaultEventVisibility"]);
      else if (/^\/v1\/organizations\/[^/]+\/suspend$/.test(path) && req.method === "POST") {
        const parts = path.split("/"); result = {data: await moderationMutation(req, "Organizations", parts[3], "suspend", "organizations.mutate")};
      } else if (path === "/v1/audit-logs" && req.method === "GET") result = await listCollection(req, "admin_audit_logs", "audit.read", ["actorUid", "actorEmail", "actorRoles", "action", "targetType", "targetId", "reason", "requestId", "createdAt"], "createdAt");
      else if (path === "/v1/jobs" && req.method === "GET") result = await listCollection(req, "admin_jobs", "audit.read", ["type", "status", "targetUid", "requestedBy", "createdAt", "startedAt", "completedAt", "errorCode"], "createdAt");
      else fail(404, "NOT_FOUND", "Admin API route not found.");
      rateLimit(result.actor?.uid || req.ip);
      json(res, 200, {data: result.data, meta: {nextPageToken: result.nextPageToken || null}}, req.requestId);
    } catch (error) {
      const known = error instanceof AdminError;
      const status = known ? error.status : 500;
      if (!known) console.error("adminApi", req.requestId, error);
      res.status(status).json({error: {code: known ? error.code : "INTERNAL", message: known ? error.message : "An internal error occurred.", details: known ? error.details || null : null, requestId: req.requestId}});
    }
  });
}

module.exports = {createAdminApi};
