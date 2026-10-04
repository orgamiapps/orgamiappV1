const {publicOrigin} = require("./public-web/origin");
/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const {
  PLACES_RATE_LIMIT,
  PLACES_RATE_WINDOW_MS,
  enforceSharedPlacesRateLimit,
} = require("./places/rate-limit");
const {
  createMaintainPublicCommunityPage,
  createMaintainPublicEventPage,
  createPublicWeb,
} = require("./public-web/renderer");
const {
  createGetPublicTicketCheckoutStatus,
  createPublicTicketCheckout,
  createRegisterPublicEvent,
  createReleaseExpiredTicketReservations,
  createStripeWebhook,
} = require("./public-web/checkout");
const {
  createCancelPublicRegistrationV1,
  createAnonymizeExpiredGuestContacts,
  createClaimPublicRegistrationV1,
  createExportOrganizerEventRegistrationsV1,
  createFollowPublicEventOrganizerV1,
  createGetOrganizerEventRegistrationsV1,
  createGetPublicRegistrationStatusV2,
  createResendPublicRegistrationConfirmationV1,
  createStartPublicRegistrationV2,
  createUpdatePublicRegistrationEmailV1,
} = require("./public-web/accountless");
const {
  createDeliverOutboundMessage,
  createRetryOutboundMessages,
} = require("./communications/delivery");
const {createEventWizardFunctions} = require("./events/wizard");
const {createStartPublicRegistrationV3} = require("./events/registration-v3");
const {createLaunchOperations} = require("./events/launch-operations");

const GOOGLE_PLACES_API_KEY = defineSecret("GOOGLE_PLACES_API_KEY");
const placesRateWindows = new Map();

async function requirePlacesCaller(req, {allowAnonymous = false} = {}) {
  const uid = req.auth?.uid;
  const provider = req.auth?.token?.firebase?.sign_in_provider;
  if (!uid || (provider === "anonymous" && !allowAnonymous)) {
    throw new HttpsError(
        "unauthenticated",
        "A signed-in account is required to search for locations.",
    );
  }

  if (process.env.ATTENDUS_TEST_IN_MEMORY_RATE_LIMIT === "true") {
    const now = Date.now();
    const current = placesRateWindows.get(uid);
    if (!current || now - current.startedAt >= PLACES_RATE_WINDOW_MS) {
      placesRateWindows.set(uid, {startedAt: now, count: 1});
      return uid;
    }
    if (current.count >= PLACES_RATE_LIMIT) {
      throw new HttpsError(
          "resource-exhausted",
          "Too many location searches. Please wait a moment and try again.",
      );
    }
    current.count += 1;
    return uid;
  }
  await enforceSharedPlacesRateLimit(
      admin.firestore(),
      uid,
      Date.now(),
      provider === "anonymous" ? 20 : PLACES_RATE_LIMIT,
  );
  return uid;
}

function placesKey() {
  const value = GOOGLE_PLACES_API_KEY.value().trim();
  if (!value) {
    throw new HttpsError(
        "failed-precondition",
        "Location search is not configured.",
    );
  }
  return value;
}

async function timeZoneForCoordinates(latitude, longitude) {
  try {
    const query = new URLSearchParams({
      location: `${latitude},${longitude}`,
      timestamp: String(Math.floor(Date.now() / 1000)),
      key: placesKey(),
    });
    const body = await googleMapsRequest(
        `https://maps.googleapis.com/maps/api/timezone/json?${query}`,
    );
    return body.status === "OK" ? String(body.timeZoneId || "") : "";
  } catch (error) {
    logger.warn("Time zone enrichment was unavailable", {
      latitude,
      longitude,
      message: error.message,
    });
    return "";
  }
}

async function googleMapsRequest(url, options = {}) {
  let response;
  try {
    response = await fetch(url, {
      ...options,
      signal: AbortSignal.timeout(8000),
    });
  } catch (error) {
    logger.error("Google Maps request failed", {error: String(error)});
    throw new HttpsError(
        "unavailable",
        "The location service is temporarily unavailable.",
    );
  }

  let body = {};
  try {
    body = await response.json();
  } catch (_) {
    // The status code below still provides a stable client-facing error.
  }
  if (!response.ok) {
    logger.error("Google Maps API rejected a request", {
      status: response.status,
      message: body?.error?.message || body?.error_message || "Unknown error",
    });
    if (response.status === 429) {
      throw new HttpsError(
          "resource-exhausted",
          "Location search quota was reached. Please try again shortly.",
      );
    }
    if (response.status === 400) {
      throw new HttpsError("invalid-argument", "Invalid location request.");
    }
    if (response.status === 403) {
      throw new HttpsError(
          "failed-precondition",
          "Location search is not available. Check Maps billing and API configuration.",
      );
    }
    throw new HttpsError(
        "unavailable",
        "The location service could not complete the request.",
    );
  }
  return body;
}

function validateSessionToken(value) {
  const token = typeof value === "string" ? value.trim() : "";
  if (token.length < 8 || token.length > 128) {
    throw new HttpsError("invalid-argument", "A valid session token is required.");
  }
  return token;
}

/**
 * Authenticated Google Places autocomplete proxy.
 * Input: {query, sessionToken, useCase: "event"|"groupCity", locationBias?}
 */
exports.placesAutocomplete = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 15,
      invoker: "public",
      enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
      secrets: [GOOGLE_PLACES_API_KEY],
    },
    async (req) => {
      const query = typeof req.data?.query === "string" ? req.data.query.trim() : "";
      const sessionToken = validateSessionToken(req.data?.sessionToken);
      const useCase = req.data?.useCase;
      if (useCase !== "event" && useCase !== "groupCity" &&
          useCase !== "discoveryCity") {
        throw new HttpsError(
            "invalid-argument",
            "A valid location search use case is required.",
        );
      }
      await requirePlacesCaller(req, {allowAnonymous: useCase === "discoveryCity"});
      if (query.length < 3 || query.length > 200) {
        throw new HttpsError(
            "invalid-argument",
            "Enter at least three characters to search.",
        );
      }

      const requestBody = {
        input: query,
        sessionToken,
        includeQueryPredictions: false,
        languageCode: "en",
      };
      if (useCase === "groupCity" || useCase === "discoveryCity") {
        requestBody.includedPrimaryTypes = useCase === "discoveryCity" && /\d/.test(query) ?
          ["postal_code"] : ["(cities)"];
        requestBody.includedRegionCodes = ["us"];
      } else {
        const bias = req.data?.locationBias;
        const lat = Number(bias?.latitude);
        const lng = Number(bias?.longitude);
        if (bias !== undefined && (typeof bias?.latitude !== "number" || typeof bias?.longitude !== "number" || !Number.isFinite(lat) || !Number.isFinite(lng) ||
          lat < -90 || lat > 90 || lng < -180 || lng > 180)) {
          throw new HttpsError("invalid-argument", "Invalid location bias.");
        }
        if (bias !== undefined) {
          requestBody.locationBias = {
            circle: {
              center: {latitude: lat, longitude: lng},
              radius: 50000,
            },
          };
        }
      }

      const body = await googleMapsRequest(
          "https://places.googleapis.com/v1/places:autocomplete",
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-Goog-Api-Key": placesKey(),
              "X-Goog-FieldMask": [
                "suggestions.placePrediction.placeId",
                "suggestions.placePrediction.text.text",
                "suggestions.placePrediction.structuredFormat.mainText.text",
                "suggestions.placePrediction.structuredFormat.secondaryText.text",
              ].join(","),
            },
            body: JSON.stringify(requestBody),
          },
      );

      const predictions = (body.suggestions || [])
          .map((suggestion) => suggestion.placePrediction)
          .filter((prediction) => prediction?.placeId)
          .slice(0, 8)
          .map((prediction) => ({
            placeId: String(prediction.placeId),
            description: String(prediction.text?.text || ""),
            primaryText: String(prediction.structuredFormat?.mainText?.text || ""),
            secondaryText: String(prediction.structuredFormat?.secondaryText?.text || ""),
          }));
      return {predictions};
    },
);

/** Input: {placeId, sessionToken}. */
exports.placeDetails = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 15,
      invoker: "public",
      enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
      secrets: [GOOGLE_PLACES_API_KEY],
    },
    async (req) => {
      const useCase = req.data?.useCase || "event";
      if (!["event", "groupCity", "discoveryCity"].includes(useCase)) {
        throw new HttpsError("invalid-argument", "Invalid location use case.");
      }
      await requirePlacesCaller(req, {allowAnonymous: useCase === "discoveryCity"});
      const placeId = typeof req.data?.placeId === "string" ? req.data.placeId.trim() : "";
      const sessionToken = validateSessionToken(req.data?.sessionToken);
      if (!placeId || placeId.length > 256) {
        throw new HttpsError("invalid-argument", "A valid place ID is required.");
      }

      const query = new URLSearchParams({sessionToken, languageCode: "en"});
      const body = await googleMapsRequest(
          `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}?${query}`,
          {
            headers: {
              "X-Goog-Api-Key": placesKey(),
              "X-Goog-FieldMask": "id,displayName,formattedAddress,location,addressComponents",
            },
          },
      );
      const latitude = Number(body.location?.latitude);
      const longitude = Number(body.location?.longitude);
      if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
        throw new HttpsError("not-found", "That place has no map location.");
      }

      let city = "";
      let regionCode = "";
      let countryCode = "";
      let streetNumber = "";
      let route = "";
      let postalCode = "";
      for (const component of body.addressComponents || []) {
        const types = component.types || [];
        if (!city && ["locality", "postal_town", "administrative_area_level_2"]
            .some((type) => types.includes(type))) {
          city = String(component.longText || component.shortText || "");
        }
        if (types.includes("administrative_area_level_1")) {
          regionCode = String(component.shortText || component.longText || "");
        }
        if (types.includes("country")) {
          countryCode = String(component.shortText || component.longText || "");
        }
        if (types.includes("street_number")) {
          streetNumber = String(component.longText || component.shortText || "");
        }
        if (types.includes("route")) {
          route = String(component.longText || component.shortText || "");
        }
        if (types.includes("postal_code")) {
          postalCode = String(component.longText || component.shortText || "");
        }
      }
      if (useCase === "discoveryCity" && countryCode !== "US") {
        throw new HttpsError("invalid-argument", "Choose a location in the United States.");
      }
      const eventTimeZone = useCase === "event" ?
        await timeZoneForCoordinates(latitude, longitude) : "";
      return {
        placeId: String(body.id || placeId),
        displayName: String(body.displayName?.text || ""),
        formattedAddress: String(body.formattedAddress || ""),
        city,
        regionCode,
        countryCode,
        streetAddress: [streetNumber, route].filter(Boolean).join(" "),
        postalCode,
        eventTimeZone,
        latitude,
        longitude,
      };
    },
);

/** Input: {latitude, longitude}. */
exports.reverseGeocode = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 15,
      invoker: "public",
      enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
      secrets: [GOOGLE_PLACES_API_KEY],
    },
    async (req) => {
      const useCase = req.data?.useCase || "event";
      if (!["event", "discoveryCity"].includes(useCase)) {
        throw new HttpsError("invalid-argument", "Invalid location use case.");
      }
      await requirePlacesCaller(req, {allowAnonymous: useCase === "discoveryCity"});
      const latitude = Number(req.data?.latitude);
      const longitude = Number(req.data?.longitude);
      if (typeof req.data?.latitude !== "number" || typeof req.data?.longitude !== "number" || !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
        latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
        throw new HttpsError("invalid-argument", "Valid coordinates are required.");
      }
      const query = new URLSearchParams({
        latlng: `${latitude},${longitude}`,
        key: placesKey(),
      });
      const body = await googleMapsRequest(
          `https://maps.googleapis.com/maps/api/geocode/json?${query}`,
      );
      if (body.status !== "OK" || !body.results?.length) {
        if (body.status === "ZERO_RESULTS") {
          throw new HttpsError("not-found", "No address was found for that pin.");
        }
        logger.error("Reverse geocoding failed", {
          status: body.status,
          message: body.error_message,
        });
        throw new HttpsError(
            "failed-precondition",
            "Address lookup is not configured or unavailable.",
        );
      }
      let city = "";
      let regionCode = "";
      let countryCode = "";
      let streetNumber = "";
      let route = "";
      let postalCode = "";
      for (const component of body.results[0].address_components || []) {
        const types = component.types || [];
        if (!city && ["locality", "postal_town", "administrative_area_level_2"]
            .some((type) => types.includes(type))) {
          city = String(component.long_name || component.short_name || "");
        }
        if (types.includes("administrative_area_level_1")) {
          regionCode = String(component.short_name || component.long_name || "");
        }
        if (types.includes("country")) {
          countryCode = String(component.short_name || component.long_name || "");
        }
        if (types.includes("street_number")) {
          streetNumber = String(component.long_name || component.short_name || "");
        }
        if (types.includes("route")) {
          route = String(component.long_name || component.short_name || "");
        }
        if (types.includes("postal_code")) {
          postalCode = String(component.long_name || component.short_name || "");
        }
      }
      if (useCase === "discoveryCity" && countryCode !== "US") {
        throw new HttpsError("invalid-argument", "Discovery is currently available in the United States.");
      }
      const eventTimeZone = useCase === "event" ?
        await timeZoneForCoordinates(latitude, longitude) : "";
      return {
        placeId: String(body.results[0].place_id || ""),
        formattedAddress: String(body.results[0].formatted_address || ""),
        city,
        regionCode,
        countryCode,
        streetAddress: [streetNumber, route].filter(Boolean).join(" "),
        postalCode,
        eventTimeZone,
        latitude,
        longitude,
      };
    },
);

// Initialize Firebase Admin SDK
const admin = require("./firebase-admin-compat");
const {
  createProcessUserAnalyticsRecompute,
  processUserAnalyticsRecompute,
  requestUserAnalyticsRecompute,
  reconcileEventUserAnalytics,
} = require("./analytics/user-analytics");
exports.processUserAnalyticsRecomputeV2 =
  createProcessUserAnalyticsRecompute(admin);

// Separate, secured Windows administrator API. The desktop client uses Firebase
// Auth ID tokens over HTTPS and never receives Admin SDK or Stripe credentials.
const {createAdminApi} = require("./admin/api");
const {createMetricsAggregator} = require("./admin/metrics");
const {createAdminDispatchHandlers} = require("./notifications/admin-dispatch");
exports.adminApi = createAdminApi(admin);
exports.aggregateAdminMetricsDaily = createMetricsAggregator(admin);
const adminDispatch = createAdminDispatchHandlers({admin});

exports.sendCustomNotifications = onCall(
    {region: "us-central1", enforceAppCheck: true, maxInstances: 5},
    adminDispatch.sendCustomNotifications,
);

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({maxInstances: 10});

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });

/**
 * Deliver pending push notifications created by the app.
 * The client enqueues docs in `pendingPushNotifications` with fields:
 * - receiverId, senderId, title, body, type, conversationId, fcmToken
 * This trigger sends via FCM and deletes the doc upon success.
 */
exports.dispatchPendingPush = onDocumentCreated("pendingPushNotifications/{docId}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data();
  try {
    const token = data.fcmToken;
    const title = data.title || "Attendus";
    const body = data.body || "New notification";
    const isolation = await require("./communications/qualification-isolation").interceptQualification(admin.firestore(), {
      actorUid: data.senderId, recipientUid: data.receiverId, conversationId: data.conversationId, eventId: data.eventId,
    }, `pending:${snap.id}`, {title, body, type: data.type || "message", conversationId: data.conversationId || null});
    if (isolation.mode !== "normal") {
      await snap.ref.set({status: `qualification_${isolation.mode}`, updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
      return;
    }
    if (!token || typeof token !== "string" || token.length < 10) {
      logger.warn("No valid fcmToken, removing pending push", {id: snap.id});
      await snap.ref.delete();
      return;
    }

    const message = {
      token,
      notification: {title, body},
      data: {
        type: String(data.type || "message"),
        conversationId: String(data.conversationId || ""),
        senderId: String(data.senderId || ""),
        receiverId: String(data.receiverId || ""),
        recipientUid: String(data.receiverId || ""),
      },
      android: {
        priority: "high",
        notification: {channelId: "attendus_channel"},
      },
      apns: {
        payload: {aps: {sound: "default"}},
      },
    };

    if (!await require("./notifications/push-tokens").canDeliverPush(admin.firestore(), data.receiverId, token)) {
      await snap.ref.delete();
      return;
    }
    const id = await admin.messaging().send(message);
    logger.info("Push sent", {fcmMessageId: id, to: data.receiverId});

    await snap.ref.delete();
  } catch (err) {
    logger.error("Failed to dispatch push", {id: snap.id, error: err});
    await snap.ref.set({status: "error", error: String(err && err.message || err), updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
  }
});

/**
 * Callable: generateUserBadgePass
 * Input: { uid: string, platform: 'apple'|'google' }
 * Output: { url: string }
 *
 * This function returns a URL that initiates adding a pass to the user's wallet.
 * - Apple Wallet: Generates a PKPass file and returns a download URL
 * - Google Wallet: Creates a JWT Save URL for Google Pay
 */
exports.generateUserBadgePass = onCall({region: "us-central1",
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
  secrets: [require("./attendance/arrival").SIGNING_KEY],
}, async (req) => {
  const attendance = require("./attendance/v2");
  const uid = attendance.requireFullAccount(req);
  if (req.data?.uid && req.data.uid !== uid) {
    throw new HttpsError("permission-denied", "You can only request your own pass.");
  }
  await attendance.enforceRateLimit(admin.firestore(), uid, "attendance_pass_issue");
  const arrival = require("./attendance/arrival");
  const pass = await arrival.issuePass(admin.firestore(), uid, {kind: "identity"}, {fullAccount: true});
  const response = await arrival.passResponse(admin.firestore(), pass);
  const url = req.data?.platform === "apple" ? response.appleWalletUrl : response.googleWalletUrl;
  if (!url) throw new HttpsError("failed-precondition", "Wallet delivery is not configured.");
  return {url};
});

/**
 * Aggregate attendance data when a new attendance record is created
 * Updates event_analytics collection with aggregated data
 */
/**
 * Trigger AI insights generation when analytics data is updated
 * This function runs when event_analytics documents are updated
 */
exports.triggerAIInsights = require("./analytics/insights").createTriggerAIInsights(admin);
exports.triggerAIInsightsV2 = require("./analytics/insights").createTriggerAIInsightsV2(admin);

/**
 * Aggregate user analytics when event_analytics changes
 * This maintains a single user_analytics/{userId} document with all aggregated data
 * Dramatically reduces client-side queries from N+1 to 1
 */
exports.aggregateUserAnalyticsV2 = onDocumentWritten({
  document: "event_analytics/{eventId}",
  region: "us-central1",
  retry: true,
}, async (event) => {
  try {
    return await reconcileEventUserAnalytics(admin, event.params.eventId, {reason: "event_analytics_write"});
  } catch (error) {
    logger.error("Error requesting aggregate user analytics", {
      eventId: event.params.eventId,
      error: String(error),
    });
    throw error;
  }
});

/**
 * Initialize user analytics when a new event is created
 */
exports.updateUserAnalyticsOnEventCreateV2 = onDocumentCreated({
  document: "Events/{eventId}",
  region: "us-central1",
  retry: true,
}, async (event) => {
  const eventData = event.data?.data();
  if (!eventData) return {skipped: true, reason: "missing_event_snapshot"};
  const userId = eventData.customerUid;
  if (!userId) return {skipped: true, reason: "missing_owner"};

  try {
    return await reconcileEventUserAnalytics(admin, event.params.eventId, {
      reason: "event_create", expectedOwner: userId, initialize: true,
    });
  } catch (error) {
    logger.error("Error initializing analytics for new event", {
      eventId: event.params.eventId,
      userId,
      error: String(error),
    });
    throw error;
  }
});

/**
 * Update user analytics when an event is deleted
 */
exports.updateUserAnalyticsOnEventDeleteV2 = onDocumentDeleted({
  document: "Events/{eventId}",
  region: "us-central1",
  retry: true,
}, async (event) => {
  const eventData = event.data?.data();
  const userId = eventData?.customerUid;
  const eventId = event.params.eventId;
  if (!userId) return {skipped: true, reason: "missing_owner"};

  try {
    return await reconcileEventUserAnalytics(admin, eventId, {
      reason: "event_delete", expectedOwner: userId, deleted: true,
    });
  } catch (error) {
    logger.error("Error requesting analytics after event deletion", {
      eventId,
      userId,
      error: String(error),
    });
    throw error;
  }
});

/**
 * Send scheduled notifications
 * Runs every minute to check for notifications that need to be sent
 */
exports.sendScheduledNotifications = onSchedule({
  schedule: "every 1 minutes",
  region: "us-central1",
}, async (_event) => {
  try {
    logger.info("Checking for scheduled notifications...");

    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    // Get notifications that are due to be sent
    const scheduledNotifications = await db.collection("scheduledNotifications")
        .where("scheduledTime", "<=", now)
        .where("sent", "==", false)
        .limit(100)
        .get();

    if (scheduledNotifications.empty) {
      logger.info("No scheduled notifications to send");
      return;
    }

    const batch = db.batch();
    const messaging = admin.messaging();

    for (const doc of scheduledNotifications.docs) {
      const notification = doc.data();

      try {
        // Get user's FCM token
        const userDoc = await db.collection("users").doc(notification.userId).get();
        if (!userDoc.exists) {
          logger.warn(`User ${notification.userId} not found, skipping notification`);
          continue;
        }

        const userData = userDoc.data();
        const fcmToken = userData.fcmToken;

        if (!fcmToken) {
          logger.warn(`No FCM token for user ${notification.userId}`);
          continue;
        }

        // Send push notification
        const message = {
          token: fcmToken,
          notification: {
            title: notification.title,
            body: notification.body,
          },
          data: {
            type: notification.type,
            eventId: notification.eventId || "",
            eventTitle: notification.eventTitle || "",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
          android: {
            notification: {
              channelId: "attendus_channel",
              priority: "high",
              defaultSound: true,
              defaultVibrateTimings: true,
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: 1,
              },
            },
          },
        };

        await messaging.send(message);
        logger.info(`Sent notification to user ${notification.userId}`);

        // Mark as sent
        batch.update(doc.ref, {
          sent: true,
          sentAt: now,
        });

        // Save to user's notifications collection
        const userNotificationRef = db.collection("users")
            .doc(notification.userId)
            .collection("notifications")
            .doc();

        batch.set(userNotificationRef, {
          title: notification.title,
          body: notification.body,
          type: notification.type,
          eventId: notification.eventId,
          eventTitle: notification.eventTitle,
          createdAt: now,
          isRead: false,
          data: notification.data || {},
        });
      } catch (error) {
        logger.error(`Error sending notification ${doc.id}:`, error);

        // Mark as failed
        batch.update(doc.ref, {
          sent: false,
          error: error.message,
          retryCount: (notification.retryCount || 0) + 1,
        });
      }
    }

    await batch.commit();
    logger.info(`Processed ${scheduledNotifications.docs.length} scheduled notifications`);
  } catch (error) {
    logger.error("Error in sendScheduledNotifications:", error);
  }
});

/**
 * Callable function to fully delete a user's account and related data.
 * Requires the caller to be authenticated. Deletes:
 * - Auth user
 * - Firestore docs in `Customers/{uid}`, `users/{uid}` and common related collections
 * - Related documents in Tickets, Attendance, Conversations, Messages, Comments
 */
exports.deleteUserAccount = onCall({region: "us-central1"}, async (request) => {
  const db = admin.firestore();
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new Error("UNAUTHENTICATED: User must be signed in to delete account.");
  }

  // Helper to batch delete a query
  async function batchDeleteQuery(query, batchSize = 300) {
    const snap = await query.get();
    if (snap.empty) return 0;
    let deleted = 0;
    const batches = [];
    let batch = db.batch();
    let opCount = 0;
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
      opCount++;
      deleted++;
      if (opCount === batchSize) {
        batches.push(batch.commit());
        batch = db.batch();
        opCount = 0;
      }
    }
    if (opCount > 0) batches.push(batch.commit());
    await Promise.all(batches);
    return deleted;
  }

  // Delete subcollection documents for a user document
  async function deleteAllSubcollections(docRef) {
    const subs = [
      "notifications",
      "settings",
      "notificationSettings",
      "followers",
      "following",
    ];
    for (const name of subs) {
      const subQuery = docRef.collection(name).limit(500);
      // Repeat until empty
      // eslint-disable-next-line no-constant-condition
      while (true) {
        const snap = await subQuery.get();
        if (snap.empty) break;
        const batch = db.batch();
        snap.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
      }
    }
  }

  try {
    // 1) Delete user-owned docs across top-level collections
    await batchDeleteQuery(db.collection("Tickets").where("customerUid", "==", uid));
    await batchDeleteQuery(db.collection("Attendance").where("customerUid", "==", uid));
    await batchDeleteQuery(db.collection("Messages").where("senderId", "==", uid));
    await batchDeleteQuery(db.collection("Messages").where("receiverId", "==", uid));
    await batchDeleteQuery(db.collection("Comments").where("userId", "==", uid));

    // Conversations by participantIds array
    await batchDeleteQuery(db.collection("Conversations").where("participantIds", "arrayContains", uid));

    // 2) Delete user docs in Customers and users + their subcollections
    const customersRef = db.collection("Customers").doc(uid);
    const usersRef = db.collection("users").doc(uid);
    await deleteAllSubcollections(customersRef);
    await deleteAllSubcollections(usersRef);
    await customersRef.delete().catch(() => {});
    await usersRef.delete().catch(() => {});

    // 3) Finally, delete the auth user
    await admin.auth().deleteUser(uid);

    return {status: "ok"};
  } catch (err) {
    logger.error("Error deleting user account:", err);
    throw new Error("INTERNAL: Failed to delete account. Please try again later.");
  }
});

/**
 * Send new event notifications to users within specified distance and group members
 * Triggered when a new event is created
 */
exports.sendNewEventNotifications = onDocumentCreated("Events/{eventId}", async (event) => {
  try {
    const currentEvent = await event.data.ref.get();
    const eventData = currentEvent.data();
    const eventId = event.data.id;

    if (!currentEvent.exists || !["active", "scheduled"].includes(eventData?.status)) {
      return;
    }

    logger.info(`Sending new event notifications for event ${eventId}`);

    const db = admin.firestore();

    // Check if this is a group/organization event
    if (eventData.organizationId) {
      await notifyGroupMembersOfNewEvent(eventData.organizationId, eventId, eventData, db);
    }

    // Continue with location-based notifications if location is provided
    if (!require("./notifications/legacy-delivery").canNotifyNearby(eventData)) {
      return;
    }

    const eventLocation = eventData.eventLocation;

    // Get all users
    const usersSnapshot = await db.collection("users").get();

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;

      // Check user's notification settings
      const settingsDoc = await db.collection("users")
          .doc(userId)
          .collection("notificationSettings")
          .doc("settings")
          .get();

      let shouldSendNewEventNotification = true;
      let distance = 15; // Default 15 miles

      if (settingsDoc.exists) {
        const settings = settingsDoc.data();
        shouldSendNewEventNotification = settings.newEvents !== false;
        distance = settings.newEventsDistance || 15;
      }

      if (!shouldSendNewEventNotification) {
        continue;
      }

      // Check if user has location and is within distance
      if (userData.location && eventLocation) {
        const userLocation = userData.location;
        const distanceInKm = calculateDistance(
            userLocation.latitude, userLocation.longitude,
            eventLocation.latitude, eventLocation.longitude,
        );

        if (distanceInKm <= distance) {
          // Send immediate notification
          await sendNotificationToUser(userId, {
            type: "new_event",
            title: "New Event Near You",
            body: `"${eventData.eventTitle || "Event"}" is happening near you!`,
            eventId: eventId,
            eventTitle: eventData.eventTitle || "Event",
          }, db, `new-event:${eventId}`, {path: currentEvent.ref.path, fields: {private: false, status: eventData.status}});
        }
      }
    }

    logger.info(`Sent new event notifications for event ${eventId}`);
  } catch (error) {
    logger.error("Error sending new event notifications:", error);
  }
});

/**
 * Send ticket update notifications
 * Triggered when a ticket is created or event is updated
 */
exports.sendTicketUpdateNotifications = onDocumentCreated("Tickets/{ticketId}", async (event) => {
  try {
    const ticketData = event.data.data();
    const ticketId = event.data.id;

    if (!ticketData) {
      return;
    }

    const userId = ticketData.customerUid;
    const eventId = ticketData.eventId;

    logger.info(`Sending ticket update notification for ticket ${ticketId}`);

    const db = admin.firestore();

    // Check user's notification settings
    const settingsDoc = await db.collection("users")
        .doc(userId)
        .collection("notificationSettings")
        .doc("settings")
        .get();

    let shouldSendTicketNotification = true;

    if (settingsDoc.exists) {
      const settings = settingsDoc.data();
      shouldSendTicketNotification = settings.ticketUpdates !== false;
    }

    if (shouldSendTicketNotification) {
      // Send notification for new ticket
      await sendNotificationToUser(userId, {
        type: "ticket_update",
        title: "Ticket Confirmed",
        body: `You've successfully registered for "${ticketData.eventTitle || "Event"}"`,
        eventId: eventId,
        eventTitle: ticketData.eventTitle || "Event",
      }, db, `ticket-created:${ticketId}`);
    }
  } catch (error) {
    logger.error("Error sending ticket update notification:", error);
  }
});

/**
 * Send event update notifications
 * Triggered when an event is updated
 */
exports.sendEventUpdateNotifications = onDocumentUpdated("Events/{eventId}", async (event) => {
  try {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const eventId = event.params.eventId;

    if (!beforeData || !afterData) {
      return;
    }
    if (beforeData.status === "pending_approval" && ["scheduled", "active"].includes(afterData.status)) {
      await exports.sendNewEventNotifications.run({data: event.data.after, params: event.params, id: event.id});
    }

    // Check if important fields have changed
    const beforeLocation = beforeData.location || beforeData.eventLocation;
    const afterLocation = afterData.location || afterData.eventLocation;
    const beforeDateTime = beforeData.selectedDateTime || beforeData.eventDateTime;
    const afterDateTime = afterData.selectedDateTime || afterData.eventDateTime;
    const beforeTitle = beforeData.title || beforeData.eventTitle;
    const afterTitle = afterData.title || afterData.eventTitle;
    const hasLocationChanged = JSON.stringify(beforeLocation) !== JSON.stringify(afterLocation);
    const hasDateTimeChanged = beforeDateTime?.toDate().getTime() !==
      afterDateTime?.toDate().getTime();
    const hasTitleChanged = beforeTitle !== afterTitle;
    const hasScheduleChanged = beforeData.eventDurationMinutes !== afterData.eventDurationMinutes || beforeData.eventTimeZone !== afterData.eventTimeZone;

    if (!hasLocationChanged && !hasDateTimeChanged && !hasTitleChanged && !hasScheduleChanged) {
      return; // No important changes
    }

    const db = admin.firestore();
    const revisionJob = db.collection("EventAnnouncements").doc(`reschedule_${eventId}_${afterData.eventRevision || 0}`);
    const legacyId = require("./events/roster").key(`${eventId}:${event.id}`);
    await db.runTransaction(async (transaction) => {
      const job = db.collection("EventAnnouncements").doc(`legacy_change_${legacyId}`);
      const [modern, previous] = await Promise.all([transaction.get(revisionJob), transaction.get(job)]);
      if ((modern.exists && beforeData.eventRevision !== afterData.eventRevision) || previous.exists) return;
      transaction.create(job, {
        eventId, actorUid: afterData.customerUid, audience: "active",
        title: `Event updated: ${afterTitle || "Event"}`,
        body: `The organizer updated the event. Review the current details at ${publicOrigin()}/event/${eventId}`,
        templateId: hasLocationChanged || hasDateTimeChanged || hasScheduleChanged ? "event_rescheduled" : "event_announcement",
        eventSnapshot: require("./events/lifecycle-snapshot").lifecycleSnapshot(afterData),
        status: "queued", createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  } catch (error) {
    logger.error("Error sending event update notifications:", error);
  }
});

// Organizer feedback received (notify event creator)
const communityNotifications = require("./community/notifications").createCommunityNotifications(admin);
exports.notifyOrganizerOnFeedback = communityNotifications.notifyOrganizerOnFeedback;
exports.notifyOrgAdminsOnJoinRequest = communityNotifications.notifyOrgAdminsOnJoinRequest;
exports.notifyOrgMembershipChanges = communityNotifications.notifyOrgMembershipChanges;
exports.notifyOrgJoinRequestDecision = communityNotifications.notifyOrgJoinRequestDecision;

// Messaging: mentions-only notifications (basic @username detection)
// Kept during rollout so older deployments do not require destructive deletion.
// Message and mention delivery now share the deduplicated recipient pipeline.
exports.sendMentionNotifications = onDocumentCreated("Messages/{messageId}", async () => {});

/**
 * Helper function to notify group members of new event
 */
async function notifyGroupMembersOfNewEvent(organizationId, eventId, eventData, db) {
  try {
    logger.info(`Notifying group members about new event ${eventId} in organization ${organizationId}`);

    // Get all members of the organization
    const membersSnapshot = await db.collection("Organizations")
        .doc(organizationId)
        .collection("Members")
        .where("status", "==", "approved")
        .get();

    if (membersSnapshot.empty) {
      logger.info(`No approved members found for organization ${organizationId}`);
      return;
    }

    // Get organization details for better notification message
    const orgDoc = await db.collection("Organizations").doc(organizationId).get();
    const orgName = orgDoc.exists ? (orgDoc.data().name || "your group") : "your group";

    logger.info(`Found ${membersSnapshot.docs.length} members to notify`);

    // Notify each member (except the event creator)
    for (const memberDoc of membersSnapshot.docs) {
      const memberId = memberDoc.id;

      // Skip the event creator
      if (memberId === eventData.customerUid || memberId === eventData.createdBy) {
        continue;
      }

      // Check user's notification settings
      const settingsDoc = await db.collection("users")
          .doc(memberId)
          .collection("notificationSettings")
          .doc("settings")
          .get();

      let shouldSendGroupEventNotification = true;

      if (settingsDoc.exists) {
        const settings = settingsDoc.data();
        // Check if user has disabled new event notifications or organization updates
        shouldSendGroupEventNotification = settings.newEvents !== false && settings.organizationUpdates !== false;
      }

      if (!shouldSendGroupEventNotification) {
        logger.info(`User ${memberId} has disabled group event notifications`);
        continue;
      }

      // Send notification
      await sendNotificationToUser(memberId, {
        type: "group_event",
        title: "New Event in " + orgName,
        body: `"${eventData.title || eventData.eventTitle || "New Event"}" has been created in ${orgName}`,
        eventId: eventId,
        eventTitle: eventData.title || eventData.eventTitle || "New Event",
        data: {
          organizationId: organizationId,
          organizationName: orgName,
        },
      }, db, `group-event:${eventId}`, [
        {path: memberDoc.ref.path, fields: {status: "approved"}},
        {path: `Events/${eventId}`, fields: {organizationId, status: eventData.status}},
      ]);

      logger.info(`Notified member ${memberId} about new group event`);
    }

    logger.info(`Completed notifying group members about event ${eventId}`);
  } catch (error) {
    logger.error("Error notifying group members of new event:", error);
  }
}

/**
 * Helper function to calculate distance between two points
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth's radius in kilometers
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon/2) * Math.sin(dLon/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return R * c;
}

/**
 * Helper function to send notification to user
 */
const sendLegacyNotification = require("./notifications/legacy-delivery").createLegacyNotificationSender(admin);
async function sendNotificationToUser(userId, notificationData, db, sourceKey, condition = null) {
  return sendLegacyNotification(userId, notificationData, db,
      sourceKey || JSON.stringify([notificationData.type, notificationData.eventId || "", notificationData.title, notificationData.body, notificationData.data || {}]), condition);
}

/**
 * Scheduled function to send post-event feedback notifications
 * Runs 1 hour after each event ends
 */
exports.sendPostEventFeedbackNotifications = onSchedule({
  schedule: "every 1 hours",
  timeZone: "UTC",
}, async (_event) => {
  try {
    const db = admin.firestore();
    const now = new Date();

    // Get all events that ended 1 hour ago
    const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000);

    const eventsQuery = await db.collection("Events")
        .where("selectedDateTime", "<=", oneHourAgo)
        .get();

    logger.info(`Found ${eventsQuery.docs.length} events that ended 1 hour ago`);

    for (const eventDoc of eventsQuery.docs) {
      const eventData = eventDoc.data();
      const eventId = eventDoc.id;
      const eventEndTime = new Date(eventData.selectedDateTime.toDate().getTime() +
        (eventData.eventDuration || 2) * 60 * 60 * 1000); // Add event duration

      // Check if it's been exactly 1 hour since event ended
      const timeSinceEventEnd = now.getTime() - eventEndTime.getTime();
      const oneHourInMs = 60 * 60 * 1000;

      if (Math.abs(timeSinceEventEnd - oneHourInMs) > 5 * 60 * 1000) { // Within 5 minutes
        continue;
      }

      // Get all attendees for this event
      const attendeesQuery = await db.collection("Attendance")
          .where("eventId", "==", eventId)
          .get();

      logger.info(`Found ${attendeesQuery.docs.length} attendees for event ${eventId}`);

      for (const attendeeDoc of attendeesQuery.docs) {
        const attendeeData = attendeeDoc.data();
        const userId = attendeeData.customerUid;

        if (!userId || userId === "manual" || userId === "without_login") {
          continue; // Skip anonymous/manual attendees
        }

        // Check if user has already submitted feedback
        const feedbackQuery = await db.collection("event_feedback")
            .where("eventId", "==", eventId)
            .where("userId", "==", userId)
            .get();

        if (!feedbackQuery.empty) {
          logger.info(`User ${userId} already submitted feedback for event ${eventId}`);
          continue;
        }

        // Check user's notification settings
        const userDoc = await db.collection("users").doc(userId).get();
        if (!userDoc.exists) {
          continue;
        }

        const userData = userDoc.data();
        const notificationSettings = userData.notificationSettings || {};

        if (notificationSettings.eventFeedback === false) {
          logger.info(`User ${userId} has disabled event feedback notifications`);
          continue;
        }

        // Send feedback notification
        await sendNotificationToUser(userId, {
          title: "How was your event?",
          body: `Rate your experience at "${eventData.title}" and help us improve!`,
          type: "event_feedback",
          eventId: eventId,
          eventTitle: eventData.title,
          data: {
            action: "open_feedback",
            eventId: eventId,
          },
        }, db);

        logger.info(`Sent feedback notification to user ${userId} for event ${eventId}`);
      }
    }

    logger.info("Completed sending post-event feedback notifications");
  } catch (error) {
    logger.error("Error sending post-event feedback notifications:", error);
  }
});

/**
 * Cloud Function to aggregate feedback data when new feedback is submitted
 */
/**
 * Send push notifications for new messages
 * Triggered when a new message is created
 */
exports.sendMessageNotifications = onDocumentCreated({document: "Messages/{messageId}", retry: true}, async (event) => {
  await require("./messaging/notifications").deliverMessageNotifications(admin.firestore(), admin.messaging(), event);
});

// These operations require Firebase Auth. App Check remains governed by the
// existing client rollout; enabling enforcement before web activation blocks users.
exports.getOrCreateDirectConversationV2 = onCall({region: "us-central1", maxInstances: 20}, (request) =>
  require("./messaging/service").getOrCreateDirect(admin.firestore(), request));
exports.sendConversationMessageV2 = onCall({region: "us-central1", maxInstances: 40}, (request) =>
  require("./messaging/service").sendMessage(admin.firestore(), request));
exports.markConversationReadV2 = onCall({region: "us-central1", maxInstances: 20}, (request) =>
  require("./messaging/service").markRead(admin.firestore(), request));

/**
 * Callable function to submit UGC reports (users/messages/comments/events)
 * Body: { type: 'user'|'message'|'comment'|'event', targetUserId?, contentId?, reason?, details? }
 */
exports.submitUserReport = onCall({region: "us-central1", enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true"}, async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid || request.auth.token?.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("unauthenticated", "Sign in to submit a report.");
  }

  const {type, targetUserId, contentId, reason, details} = request.data || {};
  if (!["user", "message", "comment", "event"].includes(type) ||
      (!targetUserId && !contentId) || String(reason || "").length > 1000 || String(details || "").length > 4000) {
    throw new HttpsError("invalid-argument", "A valid report subject and bounded reason are required.");
  }

  const db = admin.firestore();
  await require("./public-web/accountless").enforceRateLimit(db, uid, "user_report");
  const doc = {
    type: String(type),
    reporterUserId: uid,
    reporterUid: uid,
    targetUid: targetUserId ? String(targetUserId) : null,
    eventId: type === "event" && contentId ? String(contentId) : null,
    targetUserId: targetUserId ? String(targetUserId) : null,
    contentId: contentId ? String(contentId) : null,
    reason: reason ? String(reason) : null,
    details: details ? String(details) : null,
    status: "open",
    createdAt: admin.firestore.Timestamp.now(),
  };
  const report = db.collection("reports").doc();
  await db.runTransaction(async (transaction) => {
    await require("./account/mutation-guard").requireActiveAccounts(db, transaction, uid);
    transaction.create(report, doc);
  });
  return {status: "ok", reportId: report.id};
});

/**
 * Admin-only function: set admin claim by email (call after securing your own admin)
 */
exports.setAdminByEmail = onCall({region: "us-central1"}, async (req) => {
  const caller = req.auth?.token;
  if (!caller || caller.admin !== true) {
    throw new HttpsError("permission-denied", "Administrators only");
  }
  const callerRole = await admin.firestore().collection("admin_roles").doc(req.auth.uid).get();
  if (!callerRole.exists || callerRole.get("active") !== true ||
      !(callerRole.get("roles") || []).includes("super_admin")) {
    throw new HttpsError("permission-denied", "Super administrators only");
  }
  const {email, enabled, reason, confirmed} = req.data || {};
  if (!email || typeof enabled !== "boolean" || confirmed !== true ||
      typeof reason !== "string" || reason.trim().length < 10 || reason.length > 500) {
    throw new HttpsError(
        "invalid-argument",
        "{ email, enabled, confirmed: true, reason (10-500 chars) } required",
    );
  }
  const user = await admin.auth().getUserByEmail(email);
  const existingClaims = user.customClaims || {};
  await admin.auth().setCustomUserClaims(user.uid, {...existingClaims, admin: enabled});
  await admin.firestore().collection("admin_audit_logs").doc().create({
    actorUid: req.auth.uid,
    actorEmail: req.auth.token.email || null,
    actorRoles: callerRole.get("roles"),
    action: "admin.coarse-claim.update",
    targetType: "account",
    targetId: user.uid,
    reason: reason.trim(),
    requestId: `legacy-${Date.now()}`,
    before: {admin: existingClaims.admin === true},
    after: {admin: enabled},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return {status: "ok"};
});

// ============================================================================
// TICKET PAYMENT FUNCTIONS
// ============================================================================

// Initialize Stripe with your secret key
// You need to set this in Firebase Functions config:
// firebase functions:config:set stripe.secret_key="your_stripe_secret_key"
const Stripe = require("stripe");
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY || "sk_test_YOUR_TEST_KEY", {
  apiVersion: "2023-10-16",
});

/**
 * Create a payment intent for ticket purchase
 */
exports.createTicketPaymentIntent = onCall({region: "us-central1"}, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new Error("UNAUTHENTICATED");

  const {
    eventId,
    ticketId,
    amount,
    currency = "usd",
    customerUid,
    customerName,
    customerEmail,
    creatorUid,
    eventTitle,
  } = req.data || {};

  // Validate input
  if (!eventId || !amount || !customerEmail || !creatorUid || !eventTitle) {
    throw new Error("INVALID_ARGUMENT: Missing required fields");
  }

  if (amount <= 0) {
    throw new Error("INVALID_ARGUMENT: Invalid amount");
  }

  try {
    // Create payment intent with Stripe
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amount, // Amount should already be in cents
      currency: currency,
      metadata: {
        eventId: eventId,
        ticketId: ticketId || "",
        customerUid: customerUid,
        customerName: customerName,
        customerEmail: customerEmail,
        creatorUid: creatorUid,
        eventTitle: eventTitle,
      },
      receipt_email: customerEmail,
      description: `Ticket for ${eventTitle}`,
    });

    // Create a payment record in Firestore
    const db = admin.firestore();
    const paymentDoc = {
      id: paymentIntent.id,
      eventId: eventId,
      eventTitle: eventTitle,
      ticketId: ticketId || null,
      customerUid: customerUid,
      customerName: customerName,
      customerEmail: customerEmail,
      creatorUid: creatorUid,
      amount: amount / 100, // Store in dollars
      currency: currency,
      paymentIntentId: paymentIntent.id,
      status: "pending",
      createdAt: admin.firestore.Timestamp.now(),
      metadata: {
        stripeCustomerId: paymentIntent.customer || null,
      },
    };

    await db.collection("TicketPayments").doc(paymentIntent.id).set(paymentDoc);

    return {
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
    };
  } catch (error) {
    logger.error("Error creating payment intent:", error);
    throw new Error(`INTERNAL: ${error.message}`);
  }
});

// ============================================================================
// AI-POWERED NATURAL LANGUAGE EVENT SEARCH (LLAMA 3 VIA HUGGING FACE)
// ============================================================================

/**
 * Simple rule-based query parsing fallback for server-side processing
 * Returns an object like:
 * {
 *   categories: string[],
 *   keywords: string[],
 *   nearMe: boolean,
 *   radiusKm: number,
 *   dateRange: { start?: string, end?: string }
 * }
 */
exports.aiSearchEvents = require("./discovery/natural-search").createNaturalSearch(admin);

/**
 * Confirm ticket payment and issue the ticket
 */
exports.confirmTicketPayment = onCall({region: "us-central1"}, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new Error("UNAUTHENTICATED");

  const {paymentIntentId, ticketId, eventId} = req.data || {};

  if (!paymentIntentId || !eventId) {
    throw new Error("INVALID_ARGUMENT: Missing required fields");
  }

  try {
    const db = admin.firestore();

    // Retrieve the payment intent from Stripe
    const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);

    if (paymentIntent.status !== "succeeded") {
      throw new Error("Payment not successful");
    }

    // Update the payment record
    await db.collection("TicketPayments").doc(paymentIntentId).update({
      status: "completed",
      completedAt: admin.firestore.Timestamp.now(),
    });

    // If ticketId is provided, update the ticket
    if (ticketId) {
      await db.collection("Tickets").doc(ticketId).update({
        isPaid: true,
        paymentIntentId: paymentIntentId,
        paidAt: admin.firestore.Timestamp.now(),
      });
    }

    // Update event issued tickets count
    await db.collection("Events").doc(eventId).update({
      issuedTickets: admin.firestore.FieldValue.increment(1),
    });

    return {status: "success"};
  } catch (error) {
    logger.error("Error confirming payment:", error);
    throw new Error(`INTERNAL: ${error.message}`);
  }
});

/**
 * Create a payment intent for upgrading a ticket to skip-the-line
 */
exports.createTicketUpgradePaymentIntent = onCall({region: "us-central1"}, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new Error("UNAUTHENTICATED");

  const {
    ticketId,
    amount,
    currency = "usd",
    customerUid,
    customerName,
    customerEmail,
    eventTitle,
  } = req.data || {};

  // Validate input
  if (!ticketId || !amount || !customerEmail || !eventTitle) {
    throw new Error("INVALID_ARGUMENT: Missing required fields");
  }

  if (amount <= 0) {
    throw new Error("INVALID_ARGUMENT: Invalid amount");
  }

  try {
    const db = admin.firestore();

    // Verify the ticket exists and belongs to the user
    const ticketDoc = await db.collection("Tickets").doc(ticketId).get();

    if (!ticketDoc.exists) {
      throw new Error("Ticket not found");
    }

    const ticketData = ticketDoc.data();

    if (ticketData.customerUid !== uid) {
      throw new Error("PERMISSION_DENIED: You can only upgrade your own tickets");
    }

    if (ticketData.isSkipTheLine) {
      throw new Error("ALREADY_EXISTS: Ticket is already upgraded");
    }

    if (ticketData.isUsed) {
      throw new Error("FAILED_PRECONDITION: Cannot upgrade used tickets");
    }

    // Create payment intent with Stripe
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amount, // Amount should already be in cents
      currency: currency,
      metadata: {
        type: "ticket_upgrade",
        ticketId: ticketId,
        eventId: ticketData.eventId,
        customerUid: customerUid,
        customerName: customerName,
        customerEmail: customerEmail,
        eventTitle: eventTitle,
      },
      receipt_email: customerEmail,
      description: `Skip-the-Line Upgrade for ${eventTitle}`,
    });

    // Create a payment record in Firestore
    const paymentDoc = {
      id: paymentIntent.id,
      type: "ticket_upgrade",
      ticketId: ticketId,
      eventId: ticketData.eventId,
      eventTitle: eventTitle,
      customerUid: customerUid,
      customerName: customerName,
      customerEmail: customerEmail,
      amount: amount / 100, // Store in dollars
      currency: currency,
      paymentIntentId: paymentIntent.id,
      status: "pending",
      createdAt: admin.firestore.Timestamp.now(),
    };

    await db.collection("TicketUpgradePayments").doc(paymentIntent.id).set(paymentDoc);

    return {
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
    };
  } catch (error) {
    logger.error("Error creating upgrade payment intent:", error);
    throw new Error(`INTERNAL: ${error.message}`);
  }
});

/**
 * Webhook handler for Stripe events
 */
exports.stripeWebhook = onCall({region: "us-central1"}, async (req) => {
  const sig = req.rawRequest.headers["stripe-signature"];
  const endpointSecret = process.env.STRIPE_WEBHOOK_SECRET || "whsec_YOUR_WEBHOOK_SECRET";

  let event;

  try {
    event = stripe.webhooks.constructEvent(req.rawRequest.rawBody, sig, endpointSecret);
  } catch (err) {
    logger.error("Webhook signature verification failed:", err);
    throw new Error(`INVALID_ARGUMENT: ${err.message}`);
  }

  const db = admin.firestore();

  // Handle the event
  switch (event.type) {
    case "payment_intent.succeeded": {
      const paymentIntent = event.data.object;

      // Update payment status in Firestore
      await db.collection("TicketPayments").doc(paymentIntent.id).update({
        status: "completed",
        completedAt: admin.firestore.Timestamp.now(),
      });

      // Check if this is an upgrade payment
      const {type, ticketId} = paymentIntent.metadata;

      if (type === "ticket_upgrade") {
        // Handle ticket upgrade
        await db.collection("Tickets").doc(ticketId).update({
          isSkipTheLine: true,
          upgradedAt: admin.firestore.Timestamp.now(),
          upgradePaymentIntentId: paymentIntent.id,
        });

        await db.collection("TicketUpgradePayments").doc(paymentIntent.id).update({
          status: "completed",
          completedAt: admin.firestore.Timestamp.now(),
        });

        logger.info("Ticket upgrade succeeded:", paymentIntent.id);
      } else {
        // Handle regular ticket purchase
        if (ticketId) {
          await db.collection("Tickets").doc(ticketId).update({
            isPaid: true,
            paymentIntentId: paymentIntent.id,
            paidAt: admin.firestore.Timestamp.now(),
          });
        }

        logger.info("Payment succeeded:", paymentIntent.id);
      }

      break;
    }

    case "payment_intent.payment_failed": {
      const failedPayment = event.data.object;

      await db.collection("TicketPayments").doc(failedPayment.id).update({
        status: "failed",
        metadata: {
          failureReason: failedPayment.last_payment_error?.message || "Unknown error",
        },
      });

      logger.error("Payment failed:", failedPayment.id);
      break;
    }

    default:
      logger.info("Unhandled event type:", event.type);
  }

  return {received: true};
});

/**
 * Create a payment intent for featuring an event (existing functionality)
 */
exports.createFeaturePaymentIntent = onCall({region: "us-central1"}, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new Error("UNAUTHENTICATED");

  const {
    eventId,
    durationDays,
    customerUid,
    amount,
    currency = "usd",
  } = req.data || {};

  // Validate input
  if (!eventId || !durationDays || !amount || !customerUid) {
    throw new Error("INVALID_ARGUMENT: Missing required fields");
  }

  try {
    // Create payment intent with Stripe
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amount, // Amount should already be in cents
      currency: currency,
      metadata: {
        eventId: eventId,
        durationDays: durationDays.toString(),
        customerUid: customerUid,
        type: "feature_event",
      },
      description: `Feature event for ${durationDays} days`,
    });

    // Create a payment record in Firestore
    const db = admin.firestore();
    const paymentDoc = {
      id: paymentIntent.id,
      eventId: eventId,
      customerUid: customerUid,
      amount: amount / 100, // Store in dollars
      currency: currency,
      durationDays: durationDays,
      paymentIntentId: paymentIntent.id,
      status: "pending",
      type: "feature_event",
      createdAt: admin.firestore.Timestamp.now(),
    };

    await db.collection("FeaturePayments").doc(paymentIntent.id).set(paymentDoc);

    return {
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
    };
  } catch (error) {
    logger.error("Error creating feature payment intent:", error);
    throw new Error(`INTERNAL: ${error.message}`);
  }
});

/**
 * Confirm feature payment after successful Stripe payment
 */
exports.confirmFeaturePayment = onCall({region: "us-central1"}, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new Error("UNAUTHENTICATED");

  const {paymentIntentId, eventId, durationDays, untilEvent} = req.data || {};

  if (!paymentIntentId || !eventId || !durationDays) {
    throw new Error("INVALID_ARGUMENT: Missing required fields");
  }

  try {
    const db = admin.firestore();

    // Retrieve the payment intent from Stripe
    const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);

    if (paymentIntent.status !== "succeeded") {
      throw new Error("Payment not successful");
    }

    // Update the payment record
    await db.collection("FeaturePayments").doc(paymentIntentId).update({
      status: "completed",
      completedAt: admin.firestore.Timestamp.now(),
    });

    // Calculate feature end date
    let featureEndDate;
    if (untilEvent) {
      // Get event date
      const eventDoc = await db.collection("Events").doc(eventId).get();
      const eventData = eventDoc.data();
      featureEndDate = eventData.selectedDateTime;
    } else {
      // Add duration days from now
      featureEndDate = new Date();
      featureEndDate.setDate(featureEndDate.getDate() + durationDays);
    }

    // Update event to be featured
    await db.collection("Events").doc(eventId).update({
      isFeatured: true,
      featureEndDate: admin.firestore.Timestamp.fromDate(featureEndDate),
    });

    return {status: "success"};
  } catch (error) {
    logger.error("Error confirming feature payment:", error);
    throw new Error(`INTERNAL: ${error.message}`);
  }
});

// ============================================================================
// SUBSCRIPTION TIER MANAGEMENT FUNCTIONS
// ============================================================================

/**
 * Reset Monthly Event Limits for Basic Tier Users
 * Runs on the 1st day of each month at midnight UTC
 */
/**
 * Apply Scheduled Plan Changes
 * Runs every 6 hours to check for and apply scheduled tier changes
 */
exports.applyScheduledPlanChanges = onSchedule({
  schedule: "0 */6 * * *", // Every 6 hours
  timeZone: "UTC",
  region: "us-central1",
}, async (_event) => {
  logger.info("🔄 Checking for scheduled plan changes...");

  try {
    const db = admin.firestore();
    const now = new Date();

    // Get all subscriptions with scheduled plan changes
    const subscriptionsSnapshot = await db
        .collection("subscriptions")
        .where("scheduledPlanId", "!=", null)
        .get();

    if (subscriptionsSnapshot.empty) {
      logger.info("No scheduled plan changes found");
      return null;
    }

    logger.info(`Found ${subscriptionsSnapshot.docs.length} subscriptions with scheduled changes`);

    let appliedCount = 0;
    const batch = db.batch();

    for (const doc of subscriptionsSnapshot.docs) {
      const data = doc.data();
      const scheduledStartDate = data.scheduledPlanStartDate?.toDate();

      // Check if scheduled date has passed
      if (scheduledStartDate && now >= scheduledStartDate) {
        const scheduledPlanId = data.scheduledPlanId;

        // Determine new tier and pricing
        const isBasic = scheduledPlanId.includes("basic");
        const tier = isBasic ? "basic" : "premium";

        // Price determination
        const BASIC_PRICES = [500, 2500, 4000];
        const PREMIUM_PRICES = [2000, 10000, 17500];
        const prices = isBasic ? BASIC_PRICES : PREMIUM_PRICES;

        let priceAmount; let billingDays; let interval;

        if (scheduledPlanId.includes("6month")) {
          priceAmount = prices[1];
          billingDays = 180;
          interval = "6months";
        } else if (scheduledPlanId.includes("yearly")) {
          priceAmount = prices[2];
          billingDays = 365;
          interval = "year";
        } else {
          priceAmount = prices[0];
          billingDays = 30;
          interval = "month";
        }

        // Update subscription
        batch.update(doc.ref, {
          planId: scheduledPlanId,
          tier: tier,
          priceAmount: priceAmount,
          interval: interval,
          currentPeriodStart: admin.firestore.Timestamp.fromDate(scheduledStartDate),
          currentPeriodEnd: admin.firestore.Timestamp.fromDate(
              new Date(scheduledStartDate.getTime() + billingDays * 24 * 60 * 60 * 1000),
          ),
          scheduledPlanId: null,
          scheduledPlanStartDate: null,
          updatedAt: admin.firestore.Timestamp.now(),
        });

        appliedCount++;
        logger.info(`✓ Applied scheduled plan change for user: ${doc.id} to ${tier} tier`);
      }
    }

    if (appliedCount > 0) {
      await batch.commit();
    }

    logger.info(`✅ Applied ${appliedCount} scheduled plan changes`);
    return {success: true, count: appliedCount, timestamp: admin.firestore.Timestamp.now()};
  } catch (error) {
    logger.error("❌ Error applying scheduled plan changes:", error);
    throw error;
  }
});

/**
 * Send Monthly Usage Reminder to Basic Users
 * Runs on the 25th of each month at 10 AM UTC
 * Reminds users who have used 4+ events about upcoming reset
 */
exports.sendBasicTierUsageReminder = onSchedule({
  schedule: "0 10 25 * *", // 10 AM UTC on the 25th
  timeZone: "UTC",
  region: "us-central1",
}, async (_event) => {
  logger.info("📢 Sending monthly usage reminders to Basic tier users...");

  try {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    // Get Basic tier users who have used 4+ events (approaching limit)
    const subscriptionsSnapshot = await db
        .collection("subscriptions")
        .where("tier", "==", "basic")
        .where("status", "==", "active")
        .where("eventsCreatedThisMonth", ">=", 4)
        .get();

    if (subscriptionsSnapshot.empty) {
      logger.info("No users approaching event limit");
      return null;
    }

    logger.info(`Found ${subscriptionsSnapshot.docs.length} users to remind`);

    let reminderCount = 0;

    // Create notifications for users
    for (const doc of subscriptionsSnapshot.docs) {
      const userId = doc.data().userId || doc.id;
      const eventsUsed = doc.data().eventsCreatedThisMonth;
      const remaining = Math.max(0, 5 - eventsUsed);
      const month = new Date(_event.scheduleTime || now.toDate()).toISOString().slice(0, 7);
      const deliveryKey = `usage-reminder:${month}`;

      try {
        const reminderRef = db.collection("notifications").doc(`usage_${require("./events/roster").key(`${userId}:${month}`)}`);
        await db.runTransaction(async (tx) => {
          const [existing, deleting] = await Promise.all([tx.get(reminderRef), tx.get(db.collection("account_deletion_jobs").doc(userId))]);
          if (existing.exists || deleting.exists) return;
          if ((await require("./communications/qualification-isolation").qualificationDecision(db, {recipientUid: userId}, tx)).mode !== "normal") return;
          tx.create(reminderRef, {
          userId: userId,
          title: remaining === 0 ? "Monthly Event Limit Reached" : "Event Limit Almost Reached",
          message: remaining === 0 ?
            "Your 5-event monthly limit has been reached. It will reset on the 1st. Upgrade to Premium for unlimited events!" :
            `You have ${remaining} event${remaining !== 1 ? "s" : ""} remaining this month. Your limit resets on the 1st.`,
          type: "usage_reminder",
          read: false,
          createdAt: now,
          data: {
            eventsUsed: eventsUsed,
            remaining: remaining,
            upgradeUrl: "/premium-upgrade",
          },
          });
        });

        // Send push notification if user has FCM token
        await sendNotificationToUser(userId, {
          type: "usage_reminder",
          title: remaining === 0 ? "Monthly Event Limit Reached" : "Event Limit Almost Reached",
          body: remaining === 0 ?
            "Your 5-event monthly limit has been reached. It will reset on the 1st." :
            `You have ${remaining} event${remaining !== 1 ? "s" : ""} remaining this month.`,
          data: {
            eventsUsed: eventsUsed,
            remaining: remaining,
          },
        }, db, deliveryKey);

        reminderCount++;
      } catch (error) {
        logger.error(`Error sending reminder to user ${userId}:`, error);
      }
    }

    logger.info(`✅ Sent reminders to ${reminderCount} users`);
    return {success: true, count: reminderCount, timestamp: now};
  } catch (error) {
    logger.error("❌ Error sending usage reminders:", error);
    throw error;
  }
});

/**
 * Backfill User Analytics
 * Callable function to migrate existing users to the new user_analytics system
 * Run once to populate user_analytics for all users with events
 */
exports.backfillUserAnalyticsV2 = onCall({region: "us-central1"}, async (req) => {
  try {
    // Require admin auth (check if caller has admin custom claim)
    if (!req.auth || req.auth.token.admin !== true) {
      throw new HttpsError("permission-denied", "Administrator access required");
    }
    const role = await admin.firestore().collection("admin_roles").doc(req.auth.uid).get();
    if (!role.exists || role.get("active") !== true ||
        !(role.get("roles") || []).some((item) => item === "super_admin" || item === "analyst")) {
      throw new HttpsError("permission-denied", "Analyst or super administrator role required");
    }
    const {reason, confirmed} = req.data || {};
    if (confirmed !== true || typeof reason !== "string" ||
        reason.trim().length < 10 || reason.length > 500) {
      throw new HttpsError(
          "invalid-argument",
          "{ confirmed: true, reason (10-500 chars) } required",
      );
    }
    await admin.firestore().collection("admin_audit_logs").doc().create({
      actorUid: req.auth.uid,
      actorEmail: req.auth.token.email || null,
      actorRoles: role.get("roles"),
      action: "analytics.backfill.requested",
      targetType: "user_analytics",
      targetId: "all-event-creators",
      reason: reason.trim(),
      requestId: `backfill-${Date.now()}`,
      before: null,
      after: {status: "started"},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info("Starting user analytics backfill...");
    const db = admin.firestore();

    // Get all unique event creators
    const eventsSnapshot = await db.collection("Events").get();
    const userIds = new Set();

    eventsSnapshot.docs.forEach((doc) => {
      const customerUid = doc.data().customerUid;
      if (customerUid) {
        userIds.add(customerUid);
      }
    });

    logger.info(`Found ${userIds.size} unique event creators to process`);

    let successCount = 0;
    let errorCount = 0;

    // Process each user
    for (const userId of userIds) {
      try {
        logger.info(`Processing user: ${userId}`);
        await requestUserAnalyticsRecompute(admin, userId, "admin_backfill");
        const processingResult = await processUserAnalyticsRecompute(
            admin,
            userId,
        );
        logger.info("Backfilled analytics for user", {
          userId,
          ...processingResult,
        });

        successCount++;
      } catch (userError) {
        logger.error(`Error processing user ${userId}:`, userError);
        errorCount++;
      }
    }

    const result = {
      success: true,
      totalUsers: userIds.size,
      successCount: successCount,
      errorCount: errorCount,
      timestamp: admin.firestore.Timestamp.now(),
    };

    logger.info(`✅ Backfill complete: ${successCount} succeeded, ${errorCount} failed`);
    return result;
  } catch (error) {
    logger.error("❌ Error in backfillUserAnalytics:", error);
    throw error;
  }
});

// ============================================================================
// SAFETY-FIRST PAYMENT CONTAINMENT
// ============================================================================
// These final exports intentionally override the legacy handlers above. The
// legacy clients trusted caller-supplied amounts and entitlement targets. They
// remain unavailable until the server-authoritative payment module and signed,
// idempotent Stripe webhook have completed staging verification.

function paymentTemporarilyUnavailable(req) {
  const uid = req.auth?.uid;
  const provider = req.auth?.token?.firebase?.sign_in_provider;
  if (!uid || provider === "anonymous") {
    throw new HttpsError("unauthenticated", "A signed-in account is required.");
  }
  throw new HttpsError(
      "failed-precondition",
      "Paid checkout is temporarily unavailable while Attendus completes a security upgrade.",
  );
}

const disabledPaymentCallableOptions = {
  region: "us-central1",
  enforceAppCheck: true,
  maxInstances: 2,
};

exports.createTicketPaymentIntent = onCall(
    disabledPaymentCallableOptions,
    paymentTemporarilyUnavailable,
);
exports.confirmTicketPayment = onCall(
    disabledPaymentCallableOptions,
    paymentTemporarilyUnavailable,
);
exports.createTicketUpgradePaymentIntent = onCall(
    disabledPaymentCallableOptions,
    paymentTemporarilyUnavailable,
);
exports.createFeaturePaymentIntent = onCall(
    disabledPaymentCallableOptions,
    paymentTemporarilyUnavailable,
);
exports.confirmFeaturePayment = onCall(
    disabledPaymentCallableOptions,
    paymentTemporarilyUnavailable,
);

exports.stripeWebhook = createStripeWebhook(admin);

exports.applyScheduledPlanChanges = onSchedule({
  schedule: "0 */6 * * *",
  timeZone: "UTC",
  region: "us-central1",
}, async () => {
  logger.warn(
      "Scheduled plan mutation is disabled until Stripe is authoritative.",
  );
  return {disabled: true};
});

// The final export replaces the legacy best-effort deletion handler above with
// an idempotent erasure job that removes subcollections and Storage objects,
// anonymizes financial records, and deletes Authentication last.
const {createDeleteUserAccount} = require("./account/deletion");
exports.deleteUserAccount = createDeleteUserAccount();

const {createIssueFreeTicket} = require("./tickets/issuance");
exports.issueFreeTicket = createIssueFreeTicket();

const {createSubmitGuestAttendance} = require("./guest/attendance");
exports.submitGuestAttendance = createSubmitGuestAttendance(admin);

const {
  createAggregateProductFunnelDaily,
  createRecordProductFunnelEvent,
} = require("./product/funnel");
exports.recordProductFunnelEvent = createRecordProductFunnelEvent(admin);
exports.aggregateProductFunnelDaily = createAggregateProductFunnelDaily(admin);

const {
  createGetDiscoveryHome,
  createGetDiscoveryHomeV2,
  createMaintainDiscoveryMetadata,
  createSavedEventCounter,
  createSearchDiscoveryEvents,
  createSearchDiscoveryEventsV2,
} = require("./discovery/marketplace");
exports.getDiscoveryHomeV1 = createGetDiscoveryHome(admin);
exports.getDiscoveryHomeV2 = createGetDiscoveryHomeV2(admin);
exports.searchDiscoveryEventsV1 = createSearchDiscoveryEvents(admin);
exports.searchDiscoveryEventsV2 = createSearchDiscoveryEventsV2(admin);
exports.maintainDiscoveryMetadataV1 = createMaintainDiscoveryMetadata(admin);
exports.updateDiscoverySaveCountV1 = createSavedEventCounter(admin);

const {
  createDeliverDiscoveryNotifications,
  createQueueDiscoveryNotifications,
} = require("./discovery/notifications");
exports.queueDiscoveryNotificationsV1 = createQueueDiscoveryNotifications(admin);
exports.deliverDiscoveryNotificationsV1 = createDeliverDiscoveryNotifications(admin);
exports.publicWeb = createPublicWeb(admin);
exports.maintainPublicEventPageV1 = createMaintainPublicEventPage(admin);
exports.maintainPublicCommunityPageV1 = createMaintainPublicCommunityPage(admin);
exports.registerPublicEventV1 = createRegisterPublicEvent(admin);
exports.createPublicTicketCheckoutV1 = createPublicTicketCheckout(admin);
exports.getPublicTicketCheckoutStatusV1 =
  createGetPublicTicketCheckoutStatus(admin);
exports.releaseExpiredTicketReservationsV1 =
  createReleaseExpiredTicketReservations(admin);
exports.startPublicRegistrationV2 = createStartPublicRegistrationV2(admin);
exports.getPublicRegistrationStatusV2 = createGetPublicRegistrationStatusV2(admin);
exports.cancelPublicRegistrationV1 = createCancelPublicRegistrationV1(admin);
exports.anonymizeExpiredGuestContactsV1 =
  createAnonymizeExpiredGuestContacts(admin);
exports.claimPublicRegistrationV1 = createClaimPublicRegistrationV1(admin);
exports.resendPublicRegistrationConfirmationV1 =
  createResendPublicRegistrationConfirmationV1(admin);
exports.updatePublicRegistrationEmailV1 =
  createUpdatePublicRegistrationEmailV1(admin);
exports.getOrganizerEventRegistrationsV1 =
  createGetOrganizerEventRegistrationsV1(admin);
exports.exportOrganizerEventRegistrationsV1 =
  createExportOrganizerEventRegistrationsV1(admin);
exports.followPublicEventOrganizerV1 = createFollowPublicEventOrganizerV1(admin);
exports.deliverOutboundMessageV1 = createDeliverOutboundMessage(admin);
exports.retryOutboundMessagesV1 = createRetryOutboundMessages(admin);
exports.resolveOutboundDeliveryUnknownV1 = require("./communications/delivery").createResolveOutboundDeliveryUnknownV1(admin);
exports.startPublicRegistrationV3 = createStartPublicRegistrationV3(admin);

const eventWizardFunctions = createEventWizardFunctions(admin);
const launchOperations = createLaunchOperations(admin);
exports.setEventStaffV1 = launchOperations.setEventStaffV1;
exports.getEventCapabilitiesV1 = launchOperations.getEventCapabilitiesV1;
exports.listMyAdmissionsV1 = launchOperations.listMyAdmissionsV1;
exports.listEventRosterV2 = launchOperations.listEventRosterV2;
exports.previewEventAnnouncementV1 = launchOperations.previewEventAnnouncementV1;
exports.sendEventAnnouncementV1 = launchOperations.sendEventAnnouncementV1;
exports.getEventAnnouncementV1 = launchOperations.getEventAnnouncementV1;
exports.previewEventCancellationV1 = launchOperations.previewEventCancellationV1;
exports.cancelEventV1 = launchOperations.cancelEventV1;
exports.deleteEmptyEventV1 = launchOperations.deleteEmptyEventV1;
exports.createEventExportV2 = launchOperations.createEventExportV2;
exports.getEventExportV2 = launchOperations.getEventExportV2;
exports.refreshRosterEvent = launchOperations.refreshRosterEvent;
exports.refreshRosterCorrection = launchOperations.refreshRosterCorrection;
exports.refreshRosterRegisterAttendance = launchOperations.refreshRosterRegisterAttendance;
exports.refreshRosterAttendance = launchOperations.refreshRosterAttendance;
exports.refreshRosterTickets = launchOperations.refreshRosterTickets;
exports.refreshRosterHistoricalAttendance = launchOperations.refreshRosterHistoricalAttendance;
exports.refreshRosterCustomers = launchOperations.refreshRosterCustomers;
exports.refreshRosterGuestAttendees = launchOperations.refreshRosterGuestAttendees;
exports.deliverEventAnnouncement = launchOperations.deliverEventAnnouncement;
exports.generateEventExport = launchOperations.generateEventExport;
exports.retryEventOperations = launchOperations.retryEventOperations;
const attendanceHistory = require("./account/attendance-history").createAttendanceHistory(admin);
exports.archiveRecordedAttendance = attendanceHistory.archiveRecordedAttendance;
exports.getAttendanceHistoryV1 = attendanceHistory.getAttendanceHistoryV1;
exports.getAttendanceHistoryIdentityV1 = attendanceHistory.getAttendanceHistoryIdentityV1;
exports.correctAttendanceHistoryV1 = attendanceHistory.correctAttendanceHistoryV1;
exports.resumeAccountDeletion = require("./account/deletion").createResumeAccountDeletion();
exports.previewEventChangeV1 = eventWizardFunctions.previewEventChangeV1;
exports.saveEventDraftV1 = eventWizardFunctions.saveEventDraftV1;
exports.listEventDraftsV1 = eventWizardFunctions.listEventDraftsV1;
exports.archiveEventDraftV1 = eventWizardFunctions.archiveEventDraftV1;
exports.deleteEventDraftV1 = eventWizardFunctions.deleteEventDraftV1;
exports.duplicateEventToDraftV1 = eventWizardFunctions.duplicateEventToDraftV1;
exports.createEditEventDraftV1 = eventWizardFunctions.createEditEventDraftV1;
exports.listEventTemplatesV1 = eventWizardFunctions.listEventTemplatesV1;
exports.saveEventTemplateV1 = eventWizardFunctions.saveEventTemplateV1;
exports.deleteEventTemplateV1 = eventWizardFunctions.deleteEventTemplateV1;
exports.publishEventDraftV1 = eventWizardFunctions.publishEventDraftV1;
exports.decideEventRegistrationV1 = eventWizardFunctions.decideEventRegistrationV1;

const {
  createEndCheckInSession,
  createGetPersonalPass,
  createMintVenueCredential,
  createResolveCheckInCredential,
  createStartCheckInSession,
  createSubmitCheckIn,
  createVoidAttendance,
} = require("./attendance/v2");
exports.startCheckInSession = createStartCheckInSession(admin);
exports.endCheckInSession = createEndCheckInSession(admin);
exports.mintVenueCredential = createMintVenueCredential(admin);
exports.resolveCheckInCredential = createResolveCheckInCredential(admin);
exports.submitCheckIn = createSubmitCheckIn(admin);
exports.voidAttendance = createVoidAttendance(admin);
exports.getPersonalAttendancePass = createGetPersonalPass(admin);

// The scheduled-reminder V2 implementation intentionally overrides the
// legacy minute worker above while its versioned reconciliation triggers are
// verified independently in production.
const {
  createScheduledReminderFunctions,
} = require("./notifications/scheduled-reminders");
const scheduledReminderFunctions = createScheduledReminderFunctions(admin);
exports.sendScheduledNotifications =
  scheduledReminderFunctions.sendScheduledNotifications;
exports.reconcileEventRemindersV2 =
  scheduledReminderFunctions.reconcileEventRemindersV2;
exports.reconcileTicketRemindersV2 =
  scheduledReminderFunctions.reconcileTicketRemindersV2;
exports.reconcileReminderSettingsV2 =
  scheduledReminderFunctions.reconcileReminderSettingsV2;

// Smart Arrival and session-independent Wallet admission credentials.
const arrivalFunctions = require("./attendance/arrival").createArrivalFunctions(admin);
exports.maintainSmartArrivalBoundary = arrivalFunctions.maintainSmartArrivalBoundary;
exports.getSmartArrivalCandidates = arrivalFunctions.getSmartArrivalCandidates;
exports.getAttendancePass = arrivalFunctions.getAttendancePass;
exports.getAttendanceOfflineKit = arrivalFunctions.getAttendanceOfflineKit;
exports.getAttendanceScanContext = arrivalFunctions.getAttendanceScanContext;
exports.getAttendanceControl = arrivalFunctions.getAttendanceControl;
exports.setAttendanceControl = arrivalFunctions.setAttendanceControl;
const walletFunctions = require("./attendance/wallet").createWalletFunctions(admin);
exports.attendanceWallet = walletFunctions.attendanceWallet;
exports.reconcileAttendanceEventPasses = walletFunctions.reconcileAttendanceEventPasses;
exports.reconcileAttendanceRegistrationPasses = walletFunctions.reconcileAttendanceRegistrationPasses;
exports.reconcileAttendanceTicketPasses = walletFunctions.reconcileAttendanceTicketPasses;
exports.reconcileAttendanceAccountPasses = walletFunctions.reconcileAttendanceAccountPasses;
exports.refreshAttendanceWallets = walletFunctions.refreshAttendanceWallets;
exports.queueAttendanceWalletDelivery = walletFunctions.queueAttendanceWalletDelivery;
exports.deliverAttendanceWallets = walletFunctions.deliverAttendanceWallets;

exports.guestAttendanceWeb = require("./attendance/guest-web").createGuestAttendanceWeb(admin);

// Server-authoritative community, quiz, and retry-safe legacy analytics operations.
const communityOperations = require("./community/operations").createCommunityOperations(admin);
exports.communityMutationV1 = communityOperations.communityMutationV1;
const liveQuizFunctions = require("./quiz/service").createLiveQuizFunctions(admin);
exports.quizMutationV1 = liveQuizFunctions.quizMutationV1;
exports.quizReadV1 = liveQuizFunctions.quizReadV1;
const legacyAnalytics = require("./analytics/legacy-operations").createLegacyAnalyticsOperations(admin);
exports.aggregateAttendanceData = legacyAnalytics.aggregateAttendanceData;
exports.aggregateFeedbackData = legacyAnalytics.aggregateFeedbackData;
exports.resetMonthlyEventLimits = legacyAnalytics.resetMonthlyEventLimits;
const pushTokenOperations = require("./notifications/push-tokens").createPushTokenOperations(admin);
exports.registerPushTokenV1 = pushTokenOperations.registerPushTokenV1;
exports.revokePushTokenV1 = pushTokenOperations.revokePushTokenV1;

// Cross-account profile access returns bounded public cards, never raw Customers.
const publicProfiles = require("./profiles/public-profiles").createPublicProfileOperations(admin);
exports.getPublicProfilesV1 = publicProfiles.getPublicProfilesV1;
exports.searchPublicProfilesV1 = publicProfiles.searchPublicProfilesV1;
exports.checkUsernameAvailabilityV1 = publicProfiles.checkUsernameAvailabilityV1;
exports.lookupEventStaffAccountV1 = require("./profiles/staff-lookup").createLookupEventStaffAccountV1(admin);
