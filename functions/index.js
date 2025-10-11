/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onDocumentCreated, onDocumentUpdated, onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

// Initialize Firebase Admin SDK
const admin = require("firebase-admin");
admin.initializeApp();
// Optional Twilio setup for SMS sending
let twilioClient = null;
try {
  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  if (accountSid && authToken) {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const twilio = require('twilio');
    twilioClient = twilio(accountSid, authToken);
    logger.info('Twilio client initialized');
  } else {
    logger.info('Twilio not configured; SMS sending will be skipped');
  }
} catch (e) {
  logger.error('Failed to initialize Twilio', e);
}

/**
 * Callable: sendCustomNotifications
 * Input: { userIds: string[], title: string, body: string, type?: string, data?: object }
 * Behavior: Saves to users/{uid}/notifications and sends FCM if token exists.
 */
exports.sendCustomNotifications = onCall({ region: 'us-central1' }, async (req) => {
  try {
    const caller = req.auth?.uid || 'anonymous';
    const { userIds, title, body, type = 'custom', data = {} } = req.data || {};
    if (!Array.isArray(userIds) || userIds.length === 0 || !title || !body) {
      throw new Error("INVALID_ARGUMENT: { userIds[], title, body } required");
    }

    const db = admin.firestore();
    const messaging = admin.messaging();
    const now = admin.firestore.Timestamp.now();

    const results = [];
    let sentCount = 0;
    for (const userId of userIds) {
      try {
        // Save to Firestore first
        const notificationRef = await db.collection('users').doc(userId).collection('notifications').add({
          title,
          body,
          type,
          createdAt: now,
          isRead: false,
          data,
          createdBy: caller,
        });

        // Attempt to push via FCM
        const userDoc = await db.collection('users').doc(userId).get();
        const token = userDoc.exists ? userDoc.data().fcmToken : null;
        if (token) {
          const message = {
            token,
            notification: { title, body },
            data: {
              type: String(type),
              notificationId: notificationRef.id,
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
              ...Object.entries(data || {}).reduce((acc, [k, v]) => {
                acc[String(k)] = String(v);
                return acc;
              }, {}),
            },
            android: { notification: { channelId: 'orgami_channel', priority: 'high', defaultSound: true, defaultVibrateTimings: true } },
            apns: { payload: { aps: { sound: 'default', badge: 1 } } },
          };
          await messaging.send(message);
        }
        sentCount++;
        results.push({ userId, status: 'ok' });
      } catch (e) {
        logger.error('Failed notifying user', { userId, error: e });
        results.push({ userId, status: 'error', error: String(e?.message || e) });
      }
    }

    // Write a history record
    await db.collection('notification_history').add({
      type: 'in_app',
      title,
      message: body,
      totalRecipients: userIds.length,
      successCount: sentCount,
      timestamp: now,
      meta: { createdBy: caller, type },
    });
    return { status: 'ok', results };
  } catch (err) {
    logger.error('sendCustomNotifications failed', err);
    throw new Error(`INTERNAL: ${err.message}`);
  }
});

/**
 * Callable: sendBulkSms
 * Input: { phoneNumbers: string[], message: string, meta?: { eventId?, label? } }
 * Uses Twilio if configured; otherwise no-ops and records history entry.
 */
exports.sendBulkSms = onCall({ region: 'us-central1' }, async (req) => {
  try {
    const { phoneNumbers, message, meta = {} } = req.data || {};
    if (!Array.isArray(phoneNumbers) || phoneNumbers.length === 0 || !message) {
      throw new Error('INVALID_ARGUMENT: { phoneNumbers[], message } required');
    }

    const db = admin.firestore();
    const fromNumber = process.env.TWILIO_FROM_NUMBER;

    let sent = 0;
    let failed = 0;
    const failures = [];

    if (twilioClient && fromNumber) {
      // Best-effort sequential send to stay within free-tier limits; batch if needed later
      for (const to of phoneNumbers) {
        try {
          await twilioClient.messages.create({ to, from: fromNumber, body: message });
          sent++;
        } catch (e) {
          failed++;
          failures.push({ to, error: String(e?.message || e) });
        }
      }
    } else {
      // No-op fallback in dev; treat as unsent but not erroring loudly
      logger.info('Twilio not configured; skipping actual SMS send');
    }

    // Record a history doc for observability
    await db.collection('notification_history').add({
      type: 'sms',
      message,
      totalRecipients: phoneNumbers.length,
      successCount: sent,
      failureCount: failed,
      failures: failures.slice(0, 10),
      meta,
      timestamp: admin.firestore.Timestamp.now(),
    });

    return { status: 'ok', total: phoneNumbers.length, sent, failed };
  } catch (err) {
    logger.error('sendBulkSms failed', err);
    throw new Error(`INTERNAL: ${err.message}`);
  }
});

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
    const title = data.title || "AttendUs";
    const body = data.body || "New notification";
    if (!token || typeof token !== 'string' || token.length < 10) {
      logger.warn("No valid fcmToken, removing pending push", { id: snap.id });
      await snap.ref.delete();
      return;
    }

    const message = {
      token,
      notification: { title, body },
      data: {
        type: String(data.type || 'message'),
        conversationId: String(data.conversationId || ''),
        senderId: String(data.senderId || ''),
        receiverId: String(data.receiverId || ''),
      },
      android: {
        priority: 'high',
        notification: { channelId: 'attendus_channel' },
      },
      apns: {
        payload: { aps: { sound: 'default' } },
      },
    };

    const id = await admin.messaging().send(message);
    logger.info("Push sent", { fcmMessageId: id, to: data.receiverId });

    await snap.ref.delete();
  } catch (err) {
    logger.error("Failed to dispatch push", { id: snap.id, error: err });
    await snap.ref.set({ status: 'error', error: String(err && err.message || err), updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
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
exports.generateUserBadgePass = onCall({ region: "us-central1" }, async (req) => {
  try {
    const { uid, platform } = req.data || {};
    if (!uid || !platform) {
      throw new Error("INVALID_ARGUMENT: { uid, platform } required");
    }

    // Get user data from Firestore
    const userData = await getUserData(uid);
    if (!userData) {
      throw new Error("USER_NOT_FOUND: Unable to find user data");
    }

    let url;
    if (platform === 'apple') {
      url = await generateApplePassUrl(uid, userData);
    } else if (platform === 'google') {
      url = await generateGoogleSaveUrl(uid, userData);
    } else {
      throw new Error("INVALID_ARGUMENT: platform must be 'apple' or 'google'");
    }

    logger.info("Generated wallet link", { uid, platform });
    return { url };
  } catch (err) {
    logger.error("generateUserBadgePass failed", err);
    throw new Error(`INTERNAL: Failed to generate wallet pass link: ${err.message}`);
  }
});

// ---- Helper function to get user data ----
async function getUserData(uid) {
  try {
    const db = admin.firestore();
    
    // Get user badge data
    const badgeDoc = await db.collection('UserBadges').doc(uid).get();
    if (!badgeDoc.exists) {
      return null;
    }
    
    return badgeDoc.data();
  } catch (error) {
    logger.error('Error getting user data:', error);
    return null;
  }
}

// ---- Apple Wallet (PKPass) Implementation ----
// Generates a PKPass file and uploads it to Firebase Storage
const archiver = require('archiver');
const { v4: uuidv4 } = require('uuid');

async function generateApplePassUrl(uid, userData) {
  try {
    const bucket = admin.storage().bucket();
    const passId = uuidv4();
    const fileName = `passes/${passId}.pkpass`;
    
    // Create pass.json content
    const passData = {
      formatVersion: 1,
      passTypeIdentifier: 'pass.com.attendus.badge',
      serialNumber: uid,
      teamIdentifier: 'ATTENDUS',
      organizationName: 'AttendUs',
      description: 'AttendUs Member Badge',
      logoText: 'AttendUs',
      foregroundColor: 'rgb(255, 255, 255)',
      backgroundColor: 'rgb(70, 144, 226)',
      generic: {
        primaryFields: [
          {
            key: 'level',
            label: 'Badge Level',
            value: userData.badgeLevel || 'Member'
          }
        ],
        secondaryFields: [
          {
            key: 'name',
            label: 'Name',
            value: userData.userName || 'AttendUs Member'
          },
          {
            key: 'member-since',
            label: 'Member Since',
            value: userData.memberSince ? new Date(userData.memberSince.toDate()).getFullYear().toString() : '2024'
          }
        ],
        auxiliaryFields: [
          {
            key: 'events-created',
            label: 'Events Created',
            value: userData.eventsCreated?.toString() || '0'
          },
          {
            key: 'events-attended',
            label: 'Events Attended', 
            value: userData.eventsAttended?.toString() || '0'
          }
        ]
      },
      barcodes: [
        {
          message: userData.badgeQrData || `attendus-badge-${uid}`,
          format: 'PKBarcodeFormatQR',
          messageEncoding: 'iso-8859-1'
        }
      ]
    };

    // Create a zip archive for the pass
    const archive = archiver('zip', { zlib: { level: 9 } });
    const file = bucket.file(fileName);
    const stream = file.createWriteStream({
      metadata: {
        contentType: 'application/vnd.apple.pkpass',
        cacheControl: 'public, max-age=3600'
      }
    });

    archive.pipe(stream);
    
    // Add pass.json to the archive
    archive.append(JSON.stringify(passData, null, 2), { name: 'pass.json' });
    
    // Add a simple manifest.json (for basic pass structure)
    const manifest = {
      'pass.json': 'placeholder-checksum'
    };
    archive.append(JSON.stringify(manifest), { name: 'manifest.json' });
    
    // Finalize the archive
    await archive.finalize();
    
    // Wait for upload to complete
    await new Promise((resolve, reject) => {
      stream.on('error', reject);
      stream.on('finish', resolve);
    });

    // Generate a signed URL for the pass
    const [url] = await file.getSignedUrl({
      action: 'read',
      expires: Date.now() + 3600000, // 1 hour
    });

    return url;
    
  } catch (error) {
    logger.error('Error generating Apple pass:', error);
    // Return a fallback URL that will show a helpful error message
    return `data:text/plain,Error generating Apple Wallet pass. Please try again later.`;
  }
}

// ---- Google Wallet Implementation ----
// Creates a proper Google Wallet generic pass using the Google Wallet API
const jwt = require('jsonwebtoken');
const { GoogleAuth } = require('google-auth-library');

async function generateGoogleSaveUrl(uid, userData) {
  try {
    const badgeLevel = userData.badgeLevel || 'Member';
    const userName = userData.userName || 'AttendUs Member';
    const eventsCreated = userData.eventsCreated || 0;
    const eventsAttended = userData.eventsAttended || 0;
    const memberSince = userData.memberSince ? new Date(userData.memberSince.toDate()).getFullYear() : 2024;

    // First, let's create the generic pass class and object
    await createGoogleWalletClass();
    
    // Create object ID using a clean format
    const objectId = `attendus-badge-${uid}`.replace(/[^a-zA-Z0-9-_.~]/g, '');
    const issuerId = process.env.GOOGLE_WALLET_ISSUER_ID || '3388000000022295094';
    const classId = `${issuerId}.attendus_member_badge_class`;
    const fullObjectId = `${issuerId}.${objectId}`;

    // Create the generic object for this specific user
    await createGoogleWalletObject(fullObjectId, classId, userData);

    // Create JWT for Save to Google Pay
    const iat = Math.floor(Date.now() / 1000);
    const exp = iat + 3600; // 1 hour expiry

    const payload = {
      iss: process.env.GOOGLE_CLIENT_EMAIL || admin.credential.cert().client_email,
      aud: 'google',
      typ: 'savetowallet',
      iat: iat,
      exp: exp,
      payload: {
        genericObjects: [
          {
            id: fullObjectId
          }
        ]
      }
    };

    // Get the private key from service account
    const privateKey = process.env.GOOGLE_PRIVATE_KEY?.replace(/\\n/g, '\n') || 
                      admin.credential.cert().private_key;
    
    if (!privateKey) {
      throw new Error('Google Wallet private key not configured');
    }

    const token = jwt.sign(payload, privateKey, {
      algorithm: 'RS256',
      header: { 
        typ: 'JWT',
        alg: 'RS256'
      }
    });

    const saveUrl = `https://pay.google.com/gp/v/save/${token}`;
    logger.info('Generated Google Wallet save URL', { uid, saveUrl: saveUrl.substring(0, 100) + '...' });
    
    return saveUrl;
    
  } catch (error) {
    logger.error('Error generating Google Wallet pass:', error);
    // Fallback to a more helpful error message
    return `data:text/plain,Google Wallet integration requires additional setup. Please contact support for assistance.`;
  }
}

// Create Google Wallet generic pass class
async function createGoogleWalletClass() {
  try {
    const issuerId = process.env.GOOGLE_WALLET_ISSUER_ID || '3388000000022295094';
    const classId = `${issuerId}.attendus_member_badge_class`;

    // Initialize Google Auth
    const auth = new GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/wallet_object.issuer']
    });

    const authClient = await auth.getClient();
    const { google } = require('googleapis');
    
    const walletobjects = google.walletobjects({
      version: 'v1',
      auth: authClient
    });

    const genericClass = {
      id: classId,
      classTemplateInfo: {
        cardTemplateOverride: {
          cardRowTemplateInfos: [
            {
              oneItem: {
                item: {
                  firstValue: {
                    fields: [
                      {
                        fieldPath: 'object.textModulesData["scan_instruction"]'
                      }
                    ]
                  }
                }
              }
            },
            {
              twoItems: {
                startItem: {
                  firstValue: {
                    fields: [
                      {
                        fieldPath: 'object.textModulesData["level"]'
                      }
                    ]
                  }
                },
                endItem: {
                  firstValue: {
                    fields: [
                      {
                        fieldPath: 'object.textModulesData["validity"]'
                      }
                    ]
                  }
                }
              }
            },
            {
              oneItem: {
                item: {
                  firstValue: {
                    fields: [
                      {
                        fieldPath: 'object.textModulesData["member_info"]'
                      }
                    ]
                  }
                }
              }
            },
            {
              oneItem: {
                item: {
                  firstValue: {
                    fields: [
                      {
                        fieldPath: 'object.textModulesData["stats"]'
                      }
                    ]
                  }
                }
              }
            }
          ]
        }
      }
    };

    // Try to create the class (it's okay if it already exists)
    try {
      await walletobjects.genericclass.insert({
        resource: genericClass
      });
      logger.info('Google Wallet class created successfully');
    } catch (error) {
      if (error.code === 409) {
        logger.info('Google Wallet class already exists');
      } else {
        throw error;
      }
    }
  } catch (error) {
    logger.error('Error creating Google Wallet class:', error);
    // Don't throw here, let the main function handle it
  }
}

// Create Google Wallet generic object for specific user
async function createGoogleWalletObject(objectId, classId, userData) {
  try {
    const auth = new GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/wallet_object.issuer']
    });

    const authClient = await auth.getClient();
    const { google } = require('googleapis');
    
    const walletobjects = google.walletobjects({
      version: 'v1',
      auth: authClient
    });

    const badgeLevel = userData.badgeLevel || 'Member';
    const userName = userData.userName || 'AttendUs Member';
    const eventsCreated = userData.eventsCreated || 0;
    const eventsAttended = userData.eventsAttended || 0;
    const memberSince = userData.memberSince ? new Date(userData.memberSince.toDate()).getFullYear() : 2024;

    const genericObject = {
      id: objectId,
      classId: classId,
      logo: {
        sourceUri: {
          uri: 'https://firebasestorage.googleapis.com/v0/b/orgami-66nxok.appspot.com/o/app_assets%2FinAppLogo.png?alt=media'
        }
      },
      cardTitle: {
        defaultValue: {
          language: 'en-US',
          value: 'ATTENDUS'
        }
      },
      header: {
        defaultValue: {
          language: 'en-US',
          value: 'EVENT BADGE'
        }
      },
      subheader: {
        defaultValue: {
          language: 'en-US',
          value: userName
        }
      },
      // Use silver gradient colors to match the professional badge
      hexBackgroundColor: '#C0C0C0',
      textModulesData: [
        {
          id: 'scan_instruction',
          header: 'SCAN TO ACTIVATE',
          body: 'Valid for all your tickets'
        },
        {
          id: 'level',
          header: 'Badge Level',
          body: badgeLevel
        },
        {
          id: 'member_info',
          header: 'Member Details',
          body: `${userName} • Since ${memberSince}`
        },
        {
          id: 'stats',
          header: 'Activity Stats',
          body: `${eventsCreated} Events Created • ${eventsAttended} Attended`
        },
        {
          id: 'validity',
          header: 'Valid',
          body: memberSince.toString()
        }
      ],
      linksModuleData: {
        uris: [
          {
            uri: 'https://attendus.app',
            description: 'AttendUs App',
            id: 'app_link'
          }
        ]
      },
      barcode: {
        type: 'QR_CODE',
        value: userData.badgeQrData || `attendus://user/${userData.uid || 'unknown'}`,
        alternateText: `AttendUs Member: ${userName}`,
        renderEncoding: 'UTF_8'
      },
      heroImage: {
        sourceUri: {
          uri: 'https://firebasestorage.googleapis.com/v0/b/orgami-66nxok.appspot.com/o/app_assets%2FinAppLogo.png?alt=media'
        },
        contentDescription: {
          defaultValue: {
            language: 'en-US',
            value: 'AttendUs Professional Badge'
          }
        }
      }
    };

    // Try to create the object, or update if it exists
    try {
      await walletobjects.genericobject.insert({
        resource: genericObject
      });
      logger.info('Google Wallet object created successfully');
    } catch (error) {
      if (error.code === 409) {
        // Object exists, try to update it
        await walletobjects.genericobject.update({
          resourceId: objectId,
          resource: genericObject
        });
        logger.info('Google Wallet object updated successfully');
      } else {
        throw error;
      }
    }
  } catch (error) {
    logger.error('Error creating Google Wallet object:', error);
    throw error;
  }
}

/**
 * Aggregate attendance data when a new attendance record is created
 * Updates event_analytics collection with aggregated data
 */
exports.aggregateAttendanceData = onDocumentCreated("Attendance/{docId}",
    async (event) => {
      try {
        const attendanceData = event.data.data();
        const eventId = attendanceData.eventId;
        const customerUid = attendanceData.customerUid;
        const attendanceDateTime = attendanceData.attendanceDateTime.toDate();

        logger.info("Processing attendance for event:", eventId);

        // Get hour bucket for hourlySignIns (e.g., '10:00')
        const hour = attendanceDateTime.getHours();
        const hourStr = hour.toString().padStart(2, "0");
        const hourBucket = `${hourStr}:00`;

        // Use a transaction to ensure atomic updates
        const db = admin.firestore();
        await db.runTransaction(async (transaction) => {
          const analyticsRef = db.collection("event_analytics").doc(eventId);
          const analyticsDoc = await transaction.get(analyticsRef);

          // Get current analytics data or initialize if doesn't exist
          const analyticsData = analyticsDoc.exists ? analyticsDoc.data() : {
            totalAttendees: 0,
            hourlySignIns: {},
            repeatAttendees: 0,
            dropoutRate: 0,
            lastUpdated: admin.firestore.Timestamp.now(),
          };

          // Increment total attendees
          analyticsData.totalAttendees += 1;

          // Update hourly sign-ins
          if (!analyticsData.hourlySignIns[hourBucket]) {
            analyticsData.hourlySignIns[hourBucket] = 0;
          }
          analyticsData.hourlySignIns[hourBucket] += 1;

          // Count repeat attendees (same customerUid across host's events)
          if (customerUid && customerUid !== "manual") {
            // Get all events by the same host
            const eventsQuery = await db.collection("Events")
                .where("customerUid", "==", attendanceData.customerUid)
                .get();

            const hostEventIds = eventsQuery.docs.map((doc) => doc.id);

            // Count past sign-ins by this customerUid across host's events
            const pastAttendancesQuery = await db.collection("Attendance")
                .where("customerUid", "==", customerUid)
                .where("eventId", "in", hostEventIds)
                .get();

            // Count unique events this customer has attended
            // (excluding current event)
            const attendedEvents = new Set();
            pastAttendancesQuery.docs.forEach((doc) => {
              const data = doc.data();
              if (data.eventId !== eventId) {
                attendedEvents.add(data.eventId);
              }
            });

            analyticsData.repeatAttendees = attendedEvents.size;
          }

          // Calculate dropout rate
          // Get pre-registered count for this event
          const preRegisteredQuery = await db.collection("Attendance")
              .where("eventId", "==", eventId)
              .where("customerUid", "==", "pre-registered")
              .get();

          const preRegisteredCount = preRegisteredQuery.size;

          if (preRegisteredCount > 0) {
            analyticsData.dropoutRate = ((preRegisteredCount -
                analyticsData.totalAttendees) / preRegisteredCount) * 100;
          } else {
            analyticsData.dropoutRate = 0;
          }

          // Update lastUpdated timestamp
          analyticsData.lastUpdated = admin.firestore.Timestamp.now();

          // Write the updated analytics data
          transaction.set(analyticsRef, analyticsData, {merge: true});

          logger.info("Successfully updated analytics for event:", eventId);
        });

        logger.info("Attendance aggregation completed for event:", eventId);
      } catch (error) {
        logger.error("Error in aggregateAttendanceData function:", error);
        throw error;
      }
    });

/**
 * Trigger AI insights generation when analytics data is updated
 * This function runs when event_analytics documents are updated
 */
exports.triggerAIInsights = onDocumentUpdated("event_analytics/{docId}",
    async (event) => {
      try {
        const eventId = event.params.docId;
        const beforeData = event.data.before.data();
        const afterData = event.data.after.data();

        logger.info("Checking if AI insights should be generated for event:", eventId);

        // Only trigger if there's significant new data
        const beforeAttendees = (beforeData && beforeData.totalAttendees) || 0;
        const afterAttendees = (afterData && afterData.totalAttendees) || 0;

        if (afterAttendees > beforeAttendees && afterAttendees >= 5) {
          logger.info("Generating AI insights for event:", eventId);
          
          // Trigger AI insights generation
          await generateAIInsights(eventId);
        } else {
          logger.info("Insufficient new data for AI insights generation");
        }
      } catch (error) {
        logger.error("Error in triggerAIInsights function:", error);
        throw error;
      }
    });

/**
 * Generate AI insights for an event
 */
async function generateAIInsights(eventId) {
  try {
    const db = admin.firestore();
    
    // Get analytics data
    const analyticsDoc = await db.collection("event_analytics").doc(eventId).get();
    if (!analyticsDoc.exists) {
      logger.info("No analytics data found for event:", eventId);
      return;
    }

    const analyticsData = analyticsDoc.data();

    // Get comments for sentiment analysis
    const commentsQuery = await db.collection("Comments")
        .where("eventId", "==", eventId)
        .get();

    const comments = commentsQuery.docs.map(doc => doc.data());

    // Get attendees for detailed analysis
    const attendeesQuery = await db.collection("Attendance")
        .where("eventId", "==", eventId)
        .get();

    const attendees = attendeesQuery.docs.map(doc => doc.data());

    // Perform AI analysis
    const peakHoursAnalysis = analyzePeakHours(analyticsData.hourlySignIns || {});
    const sentimentAnalysis = analyzeSentiment(comments);
    const optimizations = generateOptimizations(analyticsData, peakHoursAnalysis, sentimentAnalysis);
    const dropoutAnalysis = analyzeDropoutPatterns(analyticsData, attendees);
    const repeatAttendeeAnalysis = analyzeRepeatAttendees(analyticsData, attendees);

    // Save AI insights
    const aiInsights = {
      peakHoursAnalysis,
      sentimentAnalysis,
      optimizationPredictions: optimizations,
      dropoutAnalysis,
      repeatAttendeeAnalysis,
      lastUpdated: admin.firestore.Timestamp.now(),
    };

    await db.collection("ai_insights").doc(eventId).set(aiInsights);
    logger.info("AI insights generated and saved for event:", eventId);

  } catch (error) {
    logger.error("Error generating AI insights:", error);
    throw error;
  }
}

/**
 * Analyze peak hours from hourly sign-ins data
 */
function analyzePeakHours(hourlySignIns) {
  if (!hourlySignIns || Object.keys(hourlySignIns).length === 0) {
    return {
      peakHour: null,
      peakCount: 0,
      recommendation: "Insufficient data for peak hour analysis",
      confidence: 0.0,
    };
  }

  const sortedHours = Object.entries(hourlySignIns)
    .sort((a, b) => a[0].localeCompare(b[0]));

  let peakHour = '';
  let peakCount = 0;
  let totalSignIns = 0;

  for (const [hour, count] of sortedHours) {
    const countNum = parseInt(count);
    totalSignIns += countNum;
    if (countNum > peakCount) {
      peakCount = countNum;
      peakHour = hour;
    }
  }

  const confidence = totalSignIns > 0 ? peakCount / totalSignIns : 0.0;

  let recommendation = '';
  if (peakHour) {
    const hour = parseInt(peakHour.split(':')[0]);
    if (hour >= 9 && hour <= 11) {
      recommendation = "Morning events (9-11 AM) show highest engagement. Consider scheduling future events during this time.";
    } else if (hour >= 12 && hour <= 14) {
      recommendation = "Lunch time (12-2 PM) is your peak period. Lunch-and-learn events could be highly successful.";
    } else if (hour >= 17 && hour <= 19) {
      recommendation = "Evening hours (5-7 PM) are most popular. After-work events align well with attendee preferences.";
    } else {
      recommendation = `Peak attendance at ${peakHour}. Consider this timing for future events.`;
    }
  }

  return {
    peakHour,
    peakCount,
    recommendation,
    confidence,
    totalSignIns,
    hourlyDistribution: hourlySignIns,
  };
}

/**
 * Analyze sentiment from comments
 */
function analyzeSentiment(comments) {
  if (!comments || comments.length === 0) {
    return {
      positiveRatio: 0.0,
      negativeRatio: 0.0,
      neutralRatio: 1.0,
      overallSentiment: "neutral",
      recommendation: "No comments available for sentiment analysis",
      confidence: 0.0,
    };
  }

  const positiveKeywords = [
    'great', 'awesome', 'amazing', 'excellent', 'fantastic', 'wonderful',
    'good', 'nice', 'love', 'enjoy', 'happy', 'satisfied', 'impressed',
    'outstanding', 'brilliant', 'perfect', 'best', 'favorite', 'recommend'
  ];

  const negativeKeywords = [
    'bad', 'terrible', 'awful', 'horrible', 'disappointing', 'poor',
    'worst', 'hate', 'dislike', 'boring', 'waste', 'useless', 'frustrated',
    'angry', 'annoyed', 'confused', 'difficult', 'problem', 'issue'
  ];

  let positiveCount = 0;
  let negativeCount = 0;
  let neutralCount = 0;

  for (const comment of comments) {
    const text = (comment.text || '').toLowerCase();
    if (!text) continue;

    let positiveScore = 0;
    let negativeScore = 0;

    for (const keyword of positiveKeywords) {
      if (text.includes(keyword)) positiveScore++;
    }

    for (const keyword of negativeKeywords) {
      if (text.includes(keyword)) negativeScore++;
    }

    if (positiveScore > negativeScore) {
      positiveCount++;
    } else if (negativeScore > positiveScore) {
      negativeCount++;
    } else {
      neutralCount++;
    }
  }

  const total = positiveCount + negativeCount + neutralCount;
  const positiveRatio = total > 0 ? positiveCount / total : 0.0;
  const negativeRatio = total > 0 ? negativeCount / total : 0.0;
  const neutralRatio = total > 0 ? neutralCount / total : 0.0;

  let overallSentiment = "neutral";
  if (positiveRatio > 0.6) {
    overallSentiment = "positive";
  } else if (negativeRatio > 0.6) {
    overallSentiment = "negative";
  }

  let recommendation = '';
  if (overallSentiment === "positive") {
    recommendation = "Excellent feedback! Attendees are highly satisfied. Consider expanding similar event formats.";
  } else if (overallSentiment === "negative") {
    recommendation = "Address attendee concerns. Consider gathering more detailed feedback to improve future events.";
  } else {
    recommendation = "Mixed feedback received. Consider implementing feedback surveys to better understand attendee needs.";
  }

  return {
    positiveRatio,
    negativeRatio,
    neutralRatio,
    overallSentiment,
    recommendation,
    confidence: total > 0 ? 0.8 : 0.0,
    totalComments: total,
    positiveCount,
    negativeCount,
    neutralCount,
  };
}

/**
 * Generate optimization predictions
 */
function generateOptimizations(analyticsData, peakHoursAnalysis, sentimentAnalysis) {
  const optimizations = [];

  const totalAttendees = analyticsData.totalAttendees || 0;
  const dropoutRate = analyticsData.dropoutRate || 0.0;
  const repeatAttendees = analyticsData.repeatAttendees || 0;

  // Peak hours optimization
  if (peakHoursAnalysis.peakHour) {
    const hour = parseInt(peakHoursAnalysis.peakHour.split(':')[0]);
    
    if (hour >= 9 && hour <= 11) {
      optimizations.push({
        type: "timing",
        title: "Optimize Event Timing",
        description: "Shift events to morning hours (9-11 AM) for +35% attendance",
        impact: "High",
        confidence: peakHoursAnalysis.confidence || 0.0,
        implementation: "Schedule future events during peak morning hours",
      });
    } else if (hour >= 17 && hour <= 19) {
      optimizations.push({
        type: "timing",
        title: "Evening Event Strategy",
        description: "Leverage evening peak (5-7 PM) for +25% attendance",
        impact: "Medium",
        confidence: peakHoursAnalysis.confidence || 0.0,
        implementation: "Focus on after-work events and networking sessions",
      });
    }
  }

  // Weekend optimization
  if (totalAttendees > 0) {
    optimizations.push({
      type: "scheduling",
      title: "Weekend Events",
      description: "Shift to weekends for +40% attendance potential",
      impact: "High",
      confidence: 0.7,
      implementation: "Schedule events on Saturdays or Sundays",
    });
  }

  // Dropout rate optimization
  if (dropoutRate > 20) {
    optimizations.push({
      type: "engagement",
      title: "Reduce Dropout Rate",
      description: "Implement reminder system to reduce dropout by 30%",
      impact: "Medium",
      confidence: 0.8,
      implementation: "Send SMS/email reminders 24h and 1h before events",
    });
  }

  // Repeat attendee optimization
  if (repeatAttendees > 0 && totalAttendees > 0) {
    const repeatRate = (repeatAttendees / totalAttendees) * 100;
    if (repeatRate < 30) {
      optimizations.push({
        type: "retention",
        title: "Increase Repeat Attendance",
        description: "Implement loyalty program for +50% repeat attendance",
        impact: "High",
        confidence: 0.6,
        implementation: "Create member benefits and early access programs",
      });
    }
  }

  // Sentiment-based optimizations
  if (sentimentAnalysis.overallSentiment === "negative") {
    optimizations.push({
      type: "feedback",
      title: "Improve Event Quality",
      description: "Address feedback to improve satisfaction by 40%",
      impact: "High",
      confidence: 0.9,
      implementation: "Conduct post-event surveys and implement feedback",
    });
  }

  return optimizations;
}

/**
 * Analyze dropout patterns
 */
function analyzeDropoutPatterns(analyticsData, attendees) {
  const dropoutRate = analyticsData.dropoutRate || 0.0;
  const totalAttendees = analyticsData.totalAttendees || 0;

  let recommendation = '';
  if (dropoutRate > 50) {
    recommendation = "High dropout rate detected. Consider improving event marketing and reminder systems.";
  } else if (dropoutRate > 25) {
    recommendation = "Moderate dropout rate. Implement better engagement strategies.";
  } else {
    recommendation = "Low dropout rate. Your event planning is effective!";
  }

  return {
    dropoutRate,
    recommendation,
    severity: dropoutRate > 50 ? "High" : dropoutRate > 25 ? "Medium" : "Low",
    totalAttendees,
    confidence: 0.8,
  };
}

/**
 * Analyze repeat attendee patterns
 */
function analyzeRepeatAttendees(analyticsData, attendees) {
  const repeatAttendees = analyticsData.repeatAttendees || 0;
  const totalAttendees = analyticsData.totalAttendees || 0;

  const repeatRate = totalAttendees > 0 ? (repeatAttendees / totalAttendees) * 100 : 0.0;

  let recommendation = '';
  if (repeatRate > 50) {
    recommendation = "Excellent repeat attendance! Your events have strong community building.";
  } else if (repeatRate > 25) {
    recommendation = "Good repeat attendance. Consider loyalty programs to increase retention.";
  } else {
    recommendation = "Low repeat attendance. Focus on building community and improving event quality.";
  }

  return {
    repeatRate,
    repeatAttendees,
    totalAttendees,
    recommendation,
    confidence: 0.8,
  };
}

/**
 * Send scheduled notifications
 * Runs every minute to check for notifications that need to be sent
 */
exports.sendScheduledNotifications = onSchedule({
  schedule: "every 1 minutes",
  region: "us-central1",
}, async (event) => {
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
 * Send event reminder notifications
 * Triggered when a new event is created or updated
 */
exports.sendEventReminders = onDocumentCreated("Events/{eventId}", async (event) => {
  try {
    const eventData = event.data.data();
    const eventId = event.data.id;
    
    if (!eventData || !eventData.eventDateTime) {
      return;
    }

    const eventTime = eventData.eventDateTime.toDate();
    const now = new Date();
    
    // Only schedule reminders for future events
    if (eventTime <= now) {
      return;
    }

    logger.info(`Scheduling reminders for event ${eventId}`);

    const db = admin.firestore();
    
    // Get all users who should receive notifications
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

      let shouldSendReminder = true;
      let reminderTime = 60; // Default 1 hour

      if (settingsDoc.exists) {
        const settings = settingsDoc.data();
        shouldSendReminder = settings.eventReminders !== false;
        reminderTime = settings.reminderTime || 60;
      }

      if (!shouldSendReminder) {
        continue;
      }

      // Check if user has a ticket for this event or is the creator
      const hasTicket = await checkUserHasTicket(userId, eventId, db);
      const isCreator = eventData.customerUid === userId;

      if (!hasTicket && !isCreator) {
        continue; // Skip if user has no ticket and is not the creator
      }

      // Calculate reminder time
      const reminderDateTime = new Date(eventTime.getTime() - (reminderTime * 60 * 1000));
      
      // Only schedule if reminder time is in the future
      if (reminderDateTime > now) {
        await db.collection("scheduledNotifications").add({
          type: "event_reminder",
          eventId: eventId,
          eventTitle: eventData.eventTitle || "Event",
          eventTime: eventData.eventDateTime,
          scheduledTime: admin.firestore.Timestamp.fromDate(reminderDateTime),
          title: "Event Reminder",
          body: `Your event "${eventData.eventTitle || "Event"}" starts in ${reminderTime} minutes`,
          userId: userId,
          createdAt: admin.firestore.Timestamp.now(),
          sent: false,
        });
      }
    }

    logger.info(`Scheduled reminders for event ${eventId}`);

  } catch (error) {
    logger.error("Error scheduling event reminders:", error);
  }
});

/**
 * Send new event notifications to users within specified distance and group members
 * Triggered when a new event is created
 */
exports.sendNewEventNotifications = onDocumentCreated("Events/{eventId}", async (event) => {
  try {
    const eventData = event.data.data();
    const eventId = event.data.id;
    
    if (!eventData) {
      return;
    }

    logger.info(`Sending new event notifications for event ${eventId}`);

    const db = admin.firestore();
    
    // Check if this is a group/organization event
    if (eventData.organizationId) {
      await notifyGroupMembersOfNewEvent(eventData.organizationId, eventId, eventData, db);
    }
    
    // Continue with location-based notifications if location is provided
    if (!eventData.eventLocation) {
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
          eventLocation.latitude, eventLocation.longitude
        );

        if (distanceInKm <= distance) {
          // Send immediate notification
          await sendNotificationToUser(userId, {
            type: "new_event",
            title: "New Event Near You",
            body: `"${eventData.eventTitle || "Event"}" is happening near you!`,
            eventId: eventId,
            eventTitle: eventData.eventTitle || "Event",
          }, db);
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
      }, db);
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
    const eventId = event.data.id;
    
    if (!beforeData || !afterData) {
      return;
    }

    // Check if important fields have changed
    const hasLocationChanged = JSON.stringify(beforeData.eventLocation) !== JSON.stringify(afterData.eventLocation);
    const hasDateTimeChanged = beforeData.eventDateTime.toDate().getTime() !== afterData.eventDateTime.toDate().getTime();
    const hasTitleChanged = beforeData.eventTitle !== afterData.eventTitle;

    if (!hasLocationChanged && !hasDateTimeChanged && !hasTitleChanged) {
      return; // No important changes
    }

    logger.info(`Sending event update notifications for event ${eventId}`);

    const db = admin.firestore();
    
    // Get all users who have tickets for this event
    const ticketsSnapshot = await db.collection("Tickets")
      .where("eventId", "==", eventId)
      .get();

    for (const ticketDoc of ticketsSnapshot.docs) {
      const ticketData = ticketDoc.data();
      const userId = ticketData.customerUid;
      
      // Check user's notification settings
      const settingsDoc = await db.collection("users")
        .doc(userId)
        .collection("settings")
        .doc("notifications")
        .get();

      // respect user toggle for event changes (fallback to true)
      const settings = settingsDoc.exists ? settingsDoc.data() : {};
      const shouldSendEventChange = settings.eventChanges !== false;
      if (!shouldSendEventChange) continue;

      let updateMessage = "Event details have been updated";
      if (hasLocationChanged) {
        updateMessage = "Event location has changed";
      } else if (hasDateTimeChanged) {
        updateMessage = "Event date/time has changed";
      } else if (hasTitleChanged) {
        updateMessage = "Event title has been updated";
      }

      await sendNotificationToUser(userId, {
        type: "event_changes",
        title: "Event Updated",
        body: `${updateMessage}: "${afterData.eventTitle || "Event"}"`,
        eventId: eventId,
        eventTitle: afterData.eventTitle || "Event",
      }, db);
    }

    logger.info(`Sent event update notifications for event ${eventId}`);

  } catch (error) {
    logger.error("Error sending event update notifications:", error);
  }
});

// Organizer feedback received (notify event creator)
exports.notifyOrganizerOnFeedback = onDocumentCreated("event_feedback/{docId}", async (event) => {
  try {
    const feedback = event.data.data();
    const eventId = feedback.eventId;
    const db = admin.firestore();

    const eventDoc = await db.collection("Events").doc(eventId).get();
    if (!eventDoc.exists) return;
    const eventData = eventDoc.data();
    const creatorId = eventData.customerUid || eventData.createdBy;
    if (!creatorId) return;

    // respect organizerFeedback toggle
    const settingsDoc = await db.collection("users").doc(creatorId).collection("settings").doc("notifications").get();
    const settings = settingsDoc.exists ? settingsDoc.data() : {};
    if (settings.organizerFeedback === false) return;

    await sendNotificationToUser(creatorId, {
      type: "organizer_feedback",
      title: "New feedback received",
      body: `Your event "${eventData.title || eventData.eventTitle || "Event"}" received new feedback`,
      eventId: eventId,
      eventTitle: eventData.title || eventData.eventTitle || "Event",
    }, db);
  } catch (error) {
    logger.error("Error notifying organizer on feedback:", error);
  }
});

// Organization: notify admins on new join request
exports.notifyOrgAdminsOnJoinRequest = onDocumentCreated("Organizations/{orgId}/JoinRequests/{userId}", async (event) => {
  try {
    const orgId = event.params.orgId;
    const db = admin.firestore();
    // Find admin members
    const membersSnap = await db.collection("Organizations").doc(orgId).collection("Members")
      .where("role", "in", ["Admin", "Owner"]).get();
    for (const m of membersSnap.docs) {
      const adminId = m.id;
      const settingsDoc = await db.collection("users").doc(adminId).collection("settings").doc("notifications").get();
      const settings = settingsDoc.exists ? settingsDoc.data() : {};
      if (settings.organizationUpdates === false) continue;
      await sendNotificationToUser(adminId, {
        type: "org_update",
        title: "New join request",
        body: "A user requested to join your organization",
        data: { organizationId: orgId },
      }, db);
    }
  } catch (error) {
    logger.error("Error notifying org admins on join request:", error);
  }
});

// Organization: notify requester on approval/decline and members on role changes
exports.notifyOrgMembershipChanges = onDocumentWritten("Organizations/{orgId}/Members/{userId}", async (event) => {
  try {
    const orgId = event.params.orgId;
    const userId = event.params.userId;
    const db = admin.firestore();

    const afterExists = event.data.after.exists;
    const beforeData = event.data.before.exists ? event.data.before.data() : null;
    const afterData = afterExists ? event.data.after.data() : null;

    // If status changed to approved/declined, inform the user
    if (afterExists && beforeData && beforeData.status !== afterData.status) {
      const settingsDoc = await db.collection("users").doc(userId).collection("settings").doc("notifications").get();
      const settings = settingsDoc.exists ? settingsDoc.data() : {};
      if (settings.organizationUpdates !== false) {
        const approved = afterData.status === "approved";
        await sendNotificationToUser(userId, {
          type: "org_update",
          title: approved ? "Join request approved" : "Join request updated",
          body: approved ? "You have been approved to join the organization" : `Your status is now ${afterData.status}`,
          data: { organizationId: orgId },
        }, db);
      }
    }

    // If role changes, notify the user
    if (afterExists && beforeData && beforeData.role !== afterData.role) {
      const settingsDoc = await db.collection("users").doc(userId).collection("settings").doc("notifications").get();
      const settings = settingsDoc.exists ? settingsDoc.data() : {};
      if (settings.organizationUpdates !== false) {
        await sendNotificationToUser(userId, {
          type: "org_update",
          title: "Role changed",
          body: `Your role is now ${afterData.role}`,
          data: { organizationId: orgId },
        }, db);
      }
    }
  } catch (error) {
    logger.error("Error notifying org membership changes:", error);
  }
});

// Messaging: mentions-only notifications (basic @username detection)
exports.sendMentionNotifications = onDocumentCreated("Messages/{messageId}", async (event) => {
  try {
    const msg = event.data.data();
    const db = admin.firestore();
    const content = (msg.content || "").toString();
    const receiverId = msg.receiverId;
    const senderId = msg.senderId;
    if (!content.includes("@")) return;

    // Very basic: if content contains receiver's @username, notify as mention
    const receiverDoc = await db.collection("Customers").doc(receiverId).get();
    if (!receiverDoc.exists) return;
    const username = receiverDoc.data().username;
    if (!username || !content.includes(`@${username}`)) return;

    const settingsDoc = await db.collection("users").doc(receiverId).collection("settings").doc("notifications").get();
    const settings = settingsDoc.exists ? settingsDoc.data() : {};
    if (settings.messageMentions === false) return;

    const conversationId = `${Math.min(senderId, receiverId)}_${Math.max(senderId, receiverId)}`;
    await sendNotificationToUser(receiverId, {
      type: "message_mention",
      title: "You were mentioned",
      body: content.length > 50 ? content.substring(0,50) + "..." : content,
      data: { conversationId },
    }, db);
  } catch (error) {
    logger.error("Error sending mention notifications:", error);
  }
});

/**
 * Helper function to check if user has a ticket for an event
 */
async function checkUserHasTicket(userId, eventId, db) {
  try {
    const ticketQuery = await db.collection("Tickets")
      .where("customerUid", "==", userId)
      .where("eventId", "==", eventId)
      .limit(1)
      .get();
    
    return !ticketQuery.empty;
  } catch (error) {
    logger.error("Error checking user ticket:", error);
    return false;
  }
}

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
      }, db);
      
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
async function sendNotificationToUser(userId, notificationData, db) {
  try {
    // Always save to user's notifications collection first (even if no FCM token)
    const notificationRef = await db.collection("users")
      .doc(userId)
      .collection("notifications")
      .add({
        title: notificationData.title,
        body: notificationData.body,
        type: notificationData.type,
        eventId: notificationData.eventId || null,
        eventTitle: notificationData.eventTitle || null,
        createdAt: admin.firestore.Timestamp.now(),
        isRead: false,
        data: notificationData.data || {},
      });
    
    logger.info(`Saved notification ${notificationRef.id} for user ${userId}`);

    // Get user's FCM token
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      logger.warn(`User ${userId} not found, notification saved but push not sent`);
      return;
    }

    const userData = userDoc.data();
    const fcmToken = userData.fcmToken;

    if (!fcmToken) {
      logger.warn(`No FCM token for user ${userId}, notification saved but push not sent`);
      return;
    }

    // Send push notification
    const messaging = admin.messaging();
    const message = {
      token: fcmToken,
      notification: {
        title: notificationData.title,
        body: notificationData.body,
      },
      data: {
        type: notificationData.type,
        eventId: notificationData.eventId || "",
        eventTitle: notificationData.eventTitle || "",
        conversationId: (notificationData.data && notificationData.data.conversationId) ? notificationData.data.conversationId : "",
        organizationId: (notificationData.data && notificationData.data.organizationId) ? notificationData.data.organizationId : "",
        notificationId: notificationRef.id,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        notification: {
          channelId: "orgami_channel",
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
    logger.info(`Sent push notification to user ${userId}`);

  } catch (error) {
    logger.error(`Error sending notification to user ${userId}:`, error);
  }
}

/**
 * Scheduled function to send post-event feedback notifications
 * Runs 1 hour after each event ends
 */
exports.sendPostEventFeedbackNotifications = onSchedule({
  schedule: "every 1 hours",
  timeZone: "UTC",
}, async (event) => {
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
exports.aggregateFeedbackData = onDocumentCreated("event_feedback/{docId}",
    async (event) => {
      try {
        const feedbackData = event.data.data();
        const eventId = feedbackData.eventId;
        const rating = feedbackData.rating;
        const isAnonymous = feedbackData.isAnonymous;

        logger.info("Processing feedback for event:", eventId);

        // Use a transaction to ensure atomic updates
        const db = admin.firestore();
        await db.runTransaction(async (transaction) => {
          const analyticsRef = db.collection("event_analytics").doc(eventId);
          const analyticsDoc = await transaction.get(analyticsRef);

          // Get current analytics data or initialize if doesn't exist
          const analyticsData = analyticsDoc.exists ? analyticsDoc.data() : {
            totalAttendees: 0,
            hourlySignIns: {},
            repeatAttendees: 0,
            dropoutRate: 0,
            lastUpdated: admin.firestore.Timestamp.now(),
          };

          // Initialize feedback analytics if doesn't exist
          if (!analyticsData.feedbackAnalytics) {
            analyticsData.feedbackAnalytics = {
              averageRating: 0,
              totalRatings: 0,
              ratingDistribution: {},
              sentiment: "neutral",
              commentSummaries: [],
              anonymousCount: 0,
              namedCount: 0,
            };
          }

          const feedbackAnalytics = analyticsData.feedbackAnalytics;

          // Update rating statistics
          const totalRatings = feedbackAnalytics.totalRatings + 1;
          const totalRatingSum = (feedbackAnalytics.averageRating * feedbackAnalytics.totalRatings) + rating;
          feedbackAnalytics.averageRating = totalRatingSum / totalRatings;
          feedbackAnalytics.totalRatings = totalRatings;

          // Update rating distribution
          if (!feedbackAnalytics.ratingDistribution[rating]) {
            feedbackAnalytics.ratingDistribution[rating] = 0;
          }
          feedbackAnalytics.ratingDistribution[rating] += 1;

          // Update anonymous/named counts
          if (isAnonymous) {
            feedbackAnalytics.anonymousCount += 1;
          } else {
            feedbackAnalytics.namedCount += 1;
          }

          // Update sentiment based on average rating
          if (feedbackAnalytics.averageRating >= 4.0) {
            feedbackAnalytics.sentiment = "positive";
          } else if (feedbackAnalytics.averageRating >= 3.0) {
            feedbackAnalytics.sentiment = "neutral";
          } else {
            feedbackAnalytics.sentiment = "negative";
          }

          // Update comment summaries (simplified - in production you might use ML)
          if (feedbackData.comment) {
            const commentSummary = feedbackData.comment.length > 100 
                ? feedbackData.comment.substring(0, 100) + "..."
                : feedbackData.comment;
            
            if (feedbackAnalytics.commentSummaries.length < 10) {
              feedbackAnalytics.commentSummaries.push(commentSummary);
            }
          }

          analyticsData.lastUpdated = admin.firestore.Timestamp.now();

          // Update the document
          transaction.set(analyticsRef, analyticsData, { merge: true });

          logger.info(`Updated feedback analytics for event ${eventId}`);
        });

      } catch (error) {
        logger.error("Error aggregating feedback data:", error);
      }
    });

/**
 * Send push notifications for new messages
 * Triggered when a new message is created
 */
exports.sendMessageNotifications = onDocumentCreated("Messages/{messageId}", async (event) => {
  try {
    const messageData = event.data.data();
    const messageId = event.data.id;
    
    if (!messageData) {
      return;
    }

    const senderId = messageData.senderId;
    const receiverId = messageData.receiverId;
    const content = messageData.content;

    logger.info(`Sending message notification for message ${messageId}`);

    const db = admin.firestore();
    
    // Get sender's info
    const senderDoc = await db.collection("Customers").doc(senderId).get();
    if (!senderDoc.exists) {
      logger.warn(`Sender ${senderId} not found`);
      return;
    }

    const senderData = senderDoc.data();
    const senderName = senderData.name || "Someone";

    // Get receiver's FCM token
    const receiverDoc = await db.collection("users").doc(receiverId).get();
    if (!receiverDoc.exists) {
      logger.warn(`Receiver ${receiverId} not found`);
      return;
    }

    const receiverData = receiverDoc.data();
    const fcmToken = receiverData.fcmToken;

    if (!fcmToken) {
      logger.warn(`No FCM token for receiver ${receiverId}`);
      return;
    }

    // Check receiver's notification settings (new schema in notificationSettings/settings)
    let shouldSendMessageNotification = true;
    try {
      const settingsDocNew = await db.collection("users")
        .doc(receiverId)
        .collection("notificationSettings")
        .doc("settings")
        .get();
      if (settingsDocNew.exists) {
        const s = settingsDocNew.data();
        if (s && s.messagesAll === false) {
          shouldSendMessageNotification = false;
        }
      }
    } catch (e) {
      // Fallback to legacy settings location
      const settingsDocLegacy = await db.collection("users")
        .doc(receiverId)
        .collection("settings")
        .doc("notifications")
        .get();
      if (settingsDocLegacy.exists) {
        const s = settingsDocLegacy.data();
        shouldSendMessageNotification = s.messageNotifications !== false;
      }
    }

    if (!shouldSendMessageNotification) {
      logger.info(`User ${receiverId} has disabled message notifications`);
      return;
    }

    // Send push notification
    const messaging = admin.messaging();
    const message = {
      token: fcmToken,
      notification: {
        title: senderName,
        body: content.length > 50 ? content.substring(0, 50) + "..." : content,
      },
      data: {
        type: "new_message",
        senderId: senderId,
        senderName: senderName,
        messageId: messageId,
        conversationId: `${Math.min(senderId, receiverId)}_${Math.max(senderId, receiverId)}`,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        notification: {
          channelId: "orgami_channel",
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
    logger.info(`Sent message notification to user ${receiverId}`);

    // Save to receiver's notifications collection
    await db.collection("users")
      .doc(receiverId)
      .collection("notifications")
      .add({
        title: senderName,
        body: content,
        type: "new_message",
        senderId: senderId,
        senderName: senderName,
        messageId: messageId,
        conversationId: `${Math.min(senderId, receiverId)}_${Math.max(senderId, receiverId)}`,
        createdAt: admin.firestore.Timestamp.now(),
        isRead: false,
      });

  } catch (error) {
    logger.error("Error sending message notification:", error);
  }
});

/**
 * Callable function to submit UGC reports (users/messages/comments/events)
 * Body: { type: 'user'|'message'|'comment'|'event', targetUserId?, contentId?, reason?, details? }
 */
exports.submitUserReport = onCall({region: "us-central1"}, async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new Error("UNAUTHENTICATED: User must be signed in to report.");
  }

  const { type, targetUserId, contentId, reason, details } = request.data || {};
  if (!type) {
    throw new Error("INVALID_ARGUMENT: 'type' is required");
  }

  const db = admin.firestore();
  const doc = {
    type: String(type),
    reporterUserId: uid,
    targetUserId: targetUserId ? String(targetUserId) : null,
    contentId: contentId ? String(contentId) : null,
    reason: reason ? String(reason) : null,
    details: details ? String(details) : null,
    status: "open",
    createdAt: admin.firestore.Timestamp.now(),
  };
  await db.collection("reports").add(doc);
  return { status: "ok" };
});

/**
 * Admin-only function: set admin claim by email (call after securing your own admin)
 */
exports.setAdminByEmail = onCall({ region: "us-central1" }, async (req) => {
  const caller = req.auth?.token;
  if (!caller || caller.admin !== true) {
    throw new Error("PERMISSION_DENIED: Admins only");
  }
  const { email, admin } = req.data || {};
  if (!email || typeof admin !== 'boolean') {
    throw new Error("INVALID_ARGUMENT: { email, admin } required");
  }
  const user = await admin.auth().getUserByEmail(email);
  await admin.auth().setCustomUserClaims(user.uid, { admin });
  return { status: "ok" };
});

// ============================================================================
// TICKET PAYMENT FUNCTIONS
// ============================================================================

// Initialize Stripe with your secret key
// You need to set this in Firebase Functions config:
// firebase functions:config:set stripe.secret_key="your_stripe_secret_key"
const Stripe = require('stripe');
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY || 'sk_test_YOUR_TEST_KEY', {
  apiVersion: '2023-10-16',
});

/**
 * Create a payment intent for ticket purchase
 */
exports.createTicketPaymentIntent = onCall({ region: "us-central1" }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new Error("UNAUTHENTICATED");

  const {
    eventId,
    ticketId,
    amount,
    currency = 'usd',
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
        ticketId: ticketId || '',
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
      status: 'pending',
      createdAt: admin.firestore.Timestamp.now(),
      metadata: {
        stripeCustomerId: paymentIntent.customer || null,
      },
    };

    await db.collection('TicketPayments').doc(paymentIntent.id).set(paymentDoc);

    return {
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
    };
  } catch (error) {
    logger.error('Error creating payment intent:', error);
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
function parseQuerySimple(query) {
  const queryLower = (String(query) || '').toLowerCase();
  
  // Extract keywords (remove common words)
  const commonWords = new Set(['the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'near', 'me', 'find', 'search', 'event', 'events']);
  const keywords = queryLower
    .split(/[^a-z0-9]+/)
    .filter(word => word.length > 2 && !commonWords.has(word))
    .slice(0, 5);

  // Detect categories based on keywords
  const categoryMap = {
    'book': ['book club', 'reading'],
    'read': ['book club', 'reading'],
    'music': ['music', 'concert'],
    'concert': ['music', 'concert'],
    'sport': ['sports'],
    'fitness': ['sports', 'fitness'],
    'tech': ['tech', 'technology'],
    'technology': ['tech', 'technology'],
    'network': ['networking'],
    'business': ['networking', 'business'],
    'family': ['family'],
    'kid': ['family'],
    'art': ['art'],
    'paint': ['art'],
    'food': ['food'],
    'cook': ['food'],
    'game': ['gaming'],
    'gaming': ['gaming'],
    'education': ['education'],
    'learn': ['education'],
    'workshop': ['education']
  };

  const categories = [];
  keywords.forEach(keyword => {
    if (categoryMap[keyword]) {
      categories.push(...categoryMap[keyword]);
    }
  });

  // Remove duplicates
  const uniqueCategories = [...new Set(categories)];

  // Detect location intent
  const nearMe = /near\s+me|around\s+me|close\s+by|nearby|local/i.test(query);
  
  // Extract radius if mentioned
  let radiusKm = nearMe ? 25 : 0;
  const radiusMatch = query.match(/(\d+)\s*(km|kilometers?|miles?)/i);
  if (radiusMatch) {
    const value = parseInt(radiusMatch[1]);
    radiusKm = radiusMatch[2].toLowerCase().startsWith('m') ? value * 1.6 : value; // Convert miles to km
  }

  // Basic date parsing
  const dateRange = {};
  const now = new Date();
  
  if (/today/i.test(query)) {
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    dateRange.start = today.toISOString();
    dateRange.end = new Date(today.getTime() + 24 * 60 * 60 * 1000).toISOString();
  } else if (/tomorrow/i.test(query)) {
    const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
    dateRange.start = tomorrow.toISOString();
    dateRange.end = new Date(tomorrow.getTime() + 24 * 60 * 60 * 1000).toISOString();
  } else if (/this\s+week/i.test(query)) {
    const startOfWeek = new Date(now);
    startOfWeek.setDate(now.getDate() - now.getDay());
    startOfWeek.setHours(0, 0, 0, 0);
    const endOfWeek = new Date(startOfWeek.getTime() + 7 * 24 * 60 * 60 * 1000);
    dateRange.start = startOfWeek.toISOString();
    dateRange.end = endOfWeek.toISOString();
  } else if (/weekend/i.test(query)) {
    const daysUntilSaturday = 6 - now.getDay();
    const saturday = new Date(now.getFullYear(), now.getMonth(), now.getDate() + daysUntilSaturday);
    saturday.setHours(0, 0, 0, 0);
    const sunday = new Date(saturday.getTime() + 2 * 24 * 60 * 60 * 1000);
    dateRange.start = saturday.toISOString();
    dateRange.end = sunday.toISOString();
  }

  return {
    categories: uniqueCategories,
    keywords,
    nearMe,
    radiusKm,
    dateRange,
  };
}

function kmDistance(lat1, lon1, lat2, lon2) {
  const toRad = (v) => v * Math.PI / 180;
  const R = 6371; // km
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
            Math.sin(dLon/2) * Math.sin(dLon/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Callable function: aiSearchEvents
 * Input: { query: string, lat?: number, lng?: number, limit?: number }
 * Output: { events: Event[], intent: {...} }
 */
exports.aiSearchEvents = onCall({ region: 'us-central1', timeoutSeconds: 20, memory: '512MiB' }, async (req) => {
  const uid = req.auth?.uid || null;
  const { query, lat, lng, limit } = req.data || {};
  if (!query || typeof query !== 'string') {
    throw new Error("INVALID_ARGUMENT: 'query' is required");
  }

  const db = admin.firestore();
  const intent = parseQuerySimple(query);

  // Build base timeframe: from now-3h to +60 days unless intent.dateRange provided
  const now = new Date();
  const start = intent.dateRange?.start ? new Date(intent.dateRange.start) : new Date(now.getTime() - 3 * 60 * 60 * 1000);
  const end = intent.dateRange?.end ? new Date(intent.dateRange.end) : new Date(now.getTime() + 60 * 24 * 60 * 60 * 1000);

  // Fetch a reasonable pool of upcoming public events, then filter in memory
  let q = db.collection('Events')
    .where('private', '==', false)
    .where('selectedDateTime', '>=', start)
    .where('selectedDateTime', '<=', end)
    .orderBy('selectedDateTime')
    .limit(Math.min(Number(limit) || 200, 400));

  const snap = await q.get();
  let events = snap.docs.map(d => ({ id: d.id, ...d.data() }));

  // Category filter
  const categories = (intent.categories || []).map(c => String(c).toLowerCase());
  if (categories.length > 0) {
    events = events.filter(ev => {
      const evCats = Array.isArray(ev.categories) ? ev.categories.map(c => String(c).toLowerCase()) : [];
      return evCats.some(c => categories.includes(c));
    });
  }

  // Keyword filter (title/description/location)
  const keywords = (intent.keywords || []).map(k => String(k).toLowerCase());
  if (keywords.length > 0) {
    events = events.filter(ev => {
      const t = String(ev.title || '').toLowerCase();
      const d = String(ev.description || '').toLowerCase();
      const l = String(ev.location || '').toLowerCase();
      return keywords.some(k => t.includes(k) || d.includes(k) || l.includes(k));
    });
  }

  // Location filter
  const useNearMe = intent.nearMe === true && typeof lat === 'number' && typeof lng === 'number';
  const radiusKm = useNearMe ? (intent.radiusKm || 25) : 0;
  if (useNearMe && radiusKm > 0) {
    events = events
      .map(ev => {
        const evLat = typeof ev.latitude === 'number' ? ev.latitude : null;
        const evLng = typeof ev.longitude === 'number' ? ev.longitude : null;
        const dist = (evLat != null && evLng != null) ? kmDistance(lat, lng, evLat, evLng) : Infinity;
        return { ...ev, _distanceKm: dist };
      })
      .filter(ev => ev._distanceKm <= radiusKm);
  }

  // Sort: featured first, then by (distance if applicable), then soonest date
  events.sort((a, b) => {
    const aFeat = a.isFeatured ? 1 : 0;
    const bFeat = b.isFeatured ? 1 : 0;
    if (aFeat !== bFeat) return bFeat - aFeat;
    if (useNearMe) {
      const ad = a._distanceKm ?? Infinity;
      const bd = b._distanceKm ?? Infinity;
      if (ad !== bd) return ad - bd;
    }
    const at = a.selectedDateTime && a.selectedDateTime.toDate ? a.selectedDateTime.toDate().getTime() : new Date(a.selectedDateTime).getTime();
    const bt = b.selectedDateTime && b.selectedDateTime.toDate ? b.selectedDateTime.toDate().getTime() : new Date(b.selectedDateTime).getTime();
    return at - bt;
  });

  // Trim and remove temp fields
  const maxOut = Math.min(events.length, Number(limit) || 100);
  const out = events.slice(0, maxOut).map(e => {
    const clone = { ...e };
    delete clone._distanceKm;
    // Normalize Firestore Timestamp fields to ISO strings for client compatibility
    const normalizeTs = (v) => {
      try {
        if (!v) return v;
        if (v.toDate && typeof v.toDate === 'function') return v.toDate().toISOString();
        const d = new Date(v);
        if (!isNaN(d.getTime())) return d.toISOString();
        if (v._seconds != null) {
          return new Date(v._seconds * 1000 + Math.floor((v._nanoseconds || 0) / 1e6)).toISOString();
        }
      } catch (_) {}
      return v;
    };
    clone.selectedDateTime = normalizeTs(clone.selectedDateTime);
    clone.eventGenerateTime = normalizeTs(clone.eventGenerateTime);
    clone.featureEndDate = normalizeTs(clone.featureEndDate);
    return clone;
  });

  return { events: out, intent };
});

/**
 * Confirm ticket payment and issue the ticket
 */
exports.confirmTicketPayment = onCall({ region: "us-central1" }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new Error("UNAUTHENTICATED");

  const { paymentIntentId, ticketId, eventId } = req.data || {};

  if (!paymentIntentId || !eventId) {
    throw new Error("INVALID_ARGUMENT: Missing required fields");
  }

  try {
    const db = admin.firestore();
    
    // Retrieve the payment intent from Stripe
    const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
    
    if (paymentIntent.status !== 'succeeded') {
      throw new Error("Payment not successful");
    }

    // Update the payment record
    await db.collection('TicketPayments').doc(paymentIntentId).update({
      status: 'completed',
      completedAt: admin.firestore.Timestamp.now(),
    });

    // If ticketId is provided, update the ticket
    if (ticketId) {
      await db.collection('Tickets').doc(ticketId).update({
        isPaid: true,
        paymentIntentId: paymentIntentId,
        paidAt: admin.firestore.Timestamp.now(),
      });
    }

    // Update event issued tickets count
    await db.collection('Events').doc(eventId).update({
      issuedTickets: admin.firestore.FieldValue.increment(1),
    });

    return { status: 'success' };
  } catch (error) {
    logger.error('Error confirming payment:', error);
    throw new Error(`INTERNAL: ${error.message}`);
  }
});

/**
 * Create a payment intent for upgrading a ticket to skip-the-line
 */
exports.createTicketUpgradePaymentIntent = onCall({ region: "us-central1" }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new Error("UNAUTHENTICATED");

  const {
    ticketId,
    amount,
    currency = 'usd',
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
    const ticketDoc = await db.collection('Tickets').doc(ticketId).get();
    
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
        type: 'ticket_upgrade',
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
      type: 'ticket_upgrade',
      ticketId: ticketId,
      eventId: ticketData.eventId,
      eventTitle: eventTitle,
      customerUid: customerUid,
      customerName: customerName,
      customerEmail: customerEmail,
      amount: amount / 100, // Store in dollars
      currency: currency,
      paymentIntentId: paymentIntent.id,
      status: 'pending',
      createdAt: admin.firestore.Timestamp.now(),
    };

    await db.collection('TicketUpgradePayments').doc(paymentIntent.id).set(paymentDoc);

    return {
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
    };
  } catch (error) {
    logger.error('Error creating upgrade payment intent:', error);
    throw new Error(`INTERNAL: ${error.message}`);
  }
});

/**
 * Webhook handler for Stripe events
 */
exports.stripeWebhook = onCall({ region: "us-central1" }, async (req) => {
  const sig = req.rawRequest.headers['stripe-signature'];
  const endpointSecret = process.env.STRIPE_WEBHOOK_SECRET || 'whsec_YOUR_WEBHOOK_SECRET';

  let event;

  try {
    event = stripe.webhooks.constructEvent(req.rawRequest.rawBody, sig, endpointSecret);
  } catch (err) {
    logger.error('Webhook signature verification failed:', err);
    throw new Error(`INVALID_ARGUMENT: ${err.message}`);
  }

  const db = admin.firestore();

  // Handle the event
  switch (event.type) {
    case 'payment_intent.succeeded':
      const paymentIntent = event.data.object;
      
      // Update payment status in Firestore
      await db.collection('TicketPayments').doc(paymentIntent.id).update({
        status: 'completed',
        completedAt: admin.firestore.Timestamp.now(),
      });
      
      // Check if this is an upgrade payment
      const { type, eventId, ticketId, customerUid } = paymentIntent.metadata;
      
      if (type === 'ticket_upgrade') {
        // Handle ticket upgrade
        await db.collection('Tickets').doc(ticketId).update({
          isSkipTheLine: true,
          upgradedAt: admin.firestore.Timestamp.now(),
          upgradePaymentIntentId: paymentIntent.id,
        });
        
        await db.collection('TicketUpgradePayments').doc(paymentIntent.id).update({
          status: 'completed',
          completedAt: admin.firestore.Timestamp.now(),
        });
        
        logger.info('Ticket upgrade succeeded:', paymentIntent.id);
      } else {
        // Handle regular ticket purchase
        if (ticketId) {
          await db.collection('Tickets').doc(ticketId).update({
            isPaid: true,
            paymentIntentId: paymentIntent.id,
            paidAt: admin.firestore.Timestamp.now(),
          });
        }
        
        logger.info('Payment succeeded:', paymentIntent.id);
      }
      
      break;

    case 'payment_intent.payment_failed':
      const failedPayment = event.data.object;
      
      await db.collection('TicketPayments').doc(failedPayment.id).update({
        status: 'failed',
        metadata: {
          failureReason: failedPayment.last_payment_error?.message || 'Unknown error',
        },
      });
      
      logger.error('Payment failed:', failedPayment.id);
      break;

    default:
      logger.info('Unhandled event type:', event.type);
  }

  return { received: true };
});

/**
 * Create a payment intent for featuring an event (existing functionality)
 */
exports.createFeaturePaymentIntent = onCall({ region: "us-central1" }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new Error("UNAUTHENTICATED");

  const {
    eventId,
    durationDays,
    customerUid,
    amount,
    currency = 'usd',
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
        type: 'feature_event',
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
      status: 'pending',
      type: 'feature_event',
      createdAt: admin.firestore.Timestamp.now(),
    };

    await db.collection('FeaturePayments').doc(paymentIntent.id).set(paymentDoc);

    return {
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
    };
  } catch (error) {
    logger.error('Error creating feature payment intent:', error);
    throw new Error(`INTERNAL: ${error.message}`);
  }
});

/**
 * Confirm feature payment after successful Stripe payment
 */
exports.confirmFeaturePayment = onCall({ region: "us-central1" }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new Error("UNAUTHENTICATED");

  const { paymentIntentId, eventId, durationDays, untilEvent } = req.data || {};

  if (!paymentIntentId || !eventId || !durationDays) {
    throw new Error("INVALID_ARGUMENT: Missing required fields");
  }

  try {
    const db = admin.firestore();
    
    // Retrieve the payment intent from Stripe
    const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
    
    if (paymentIntent.status !== 'succeeded') {
      throw new Error("Payment not successful");
    }

    // Update the payment record
    await db.collection('FeaturePayments').doc(paymentIntentId).update({
      status: 'completed',
      completedAt: admin.firestore.Timestamp.now(),
    });

    // Calculate feature end date
    let featureEndDate;
    if (untilEvent) {
      // Get event date
      const eventDoc = await db.collection('Events').doc(eventId).get();
      const eventData = eventDoc.data();
      featureEndDate = eventData.selectedDateTime;
    } else {
      // Add duration days from now
      featureEndDate = new Date();
      featureEndDate.setDate(featureEndDate.getDate() + durationDays);
    }

    // Update event to be featured
    await db.collection('Events').doc(eventId).update({
      isFeatured: true,
      featureEndDate: admin.firestore.Timestamp.fromDate(featureEndDate),
    });

    return { status: 'success' };
  } catch (error) {
    logger.error('Error confirming feature payment:', error);
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
exports.resetMonthlyEventLimits = onSchedule({
  schedule: '0 0 1 * *', // First day of each month at midnight UTC
  timeZone: 'UTC',
  region: 'us-central1',
}, async (event) => {
  logger.info('🔄 Starting monthly event limit reset for Basic tier users...');
  
  try {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    
    // Get all Basic tier subscriptions
    const subscriptionsSnapshot = await db
      .collection('subscriptions')
      .where('tier', '==', 'basic')
      .where('status', '==', 'active')
      .get();
    
    if (subscriptionsSnapshot.empty) {
      logger.info('No active Basic tier subscriptions found');
      return null;
    }
    
    logger.info(`Found ${subscriptionsSnapshot.docs.length} Basic tier subscriptions to reset`);
    
    const batch = db.batch();
    let resetCount = 0;
    
    subscriptionsSnapshot.forEach(doc => {
      batch.update(doc.ref, {
        eventsCreatedThisMonth: 0,
        currentMonthStart: now,
        updatedAt: now,
      });
      resetCount++;
    });
    
    await batch.commit();
    
    logger.info(`✅ Successfully reset monthly event limits for ${resetCount} Basic tier users`);
    return { success: true, count: resetCount, timestamp: now };
  } catch (error) {
    logger.error('❌ Error resetting monthly limits:', error);
    throw error;
  }
});

/**
 * Apply Scheduled Plan Changes
 * Runs every 6 hours to check for and apply scheduled tier changes
 */
exports.applyScheduledPlanChanges = onSchedule({
  schedule: '0 */6 * * *', // Every 6 hours
  timeZone: 'UTC',
  region: 'us-central1',
}, async (event) => {
  logger.info('🔄 Checking for scheduled plan changes...');
  
  try {
    const db = admin.firestore();
    const now = new Date();
    
    // Get all subscriptions with scheduled plan changes
    const subscriptionsSnapshot = await db
      .collection('subscriptions')
      .where('scheduledPlanId', '!=', null)
      .get();
    
    if (subscriptionsSnapshot.empty) {
      logger.info('No scheduled plan changes found');
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
        const isBasic = scheduledPlanId.includes('basic');
        const tier = isBasic ? 'basic' : 'premium';
        
        // Price determination
        const BASIC_PRICES = [500, 2500, 4000];
        const PREMIUM_PRICES = [2000, 10000, 17500];
        const prices = isBasic ? BASIC_PRICES : PREMIUM_PRICES;
        
        let priceAmount, billingDays, interval;
        
        if (scheduledPlanId.includes('6month')) {
          priceAmount = prices[1];
          billingDays = 180;
          interval = '6months';
        } else if (scheduledPlanId.includes('yearly')) {
          priceAmount = prices[2];
          billingDays = 365;
          interval = 'year';
        } else {
          priceAmount = prices[0];
          billingDays = 30;
          interval = 'month';
        }
        
        // Update subscription
        batch.update(doc.ref, {
          planId: scheduledPlanId,
          tier: tier,
          priceAmount: priceAmount,
          interval: interval,
          currentPeriodStart: admin.firestore.Timestamp.fromDate(scheduledStartDate),
          currentPeriodEnd: admin.firestore.Timestamp.fromDate(
            new Date(scheduledStartDate.getTime() + billingDays * 24 * 60 * 60 * 1000)
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
    return { success: true, count: appliedCount, timestamp: admin.firestore.Timestamp.now() };
  } catch (error) {
    logger.error('❌ Error applying scheduled plan changes:', error);
    throw error;
  }
});

/**
 * Send Monthly Usage Reminder to Basic Users
 * Runs on the 25th of each month at 10 AM UTC
 * Reminds users who have used 4+ events about upcoming reset
 */
exports.sendBasicTierUsageReminder = onSchedule({
  schedule: '0 10 25 * *', // 10 AM UTC on the 25th
  timeZone: 'UTC',
  region: 'us-central1',
}, async (event) => {
  logger.info('📢 Sending monthly usage reminders to Basic tier users...');
  
  try {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    
    // Get Basic tier users who have used 4+ events (approaching limit)
    const subscriptionsSnapshot = await db
      .collection('subscriptions')
      .where('tier', '==', 'basic')
      .where('status', '==', 'active')
      .where('eventsCreatedThisMonth', '>=', 4)
      .get();
    
    if (subscriptionsSnapshot.empty) {
      logger.info('No users approaching event limit');
      return null;
    }
    
    logger.info(`Found ${subscriptionsSnapshot.docs.length} users to remind`);
    
    let reminderCount = 0;
    
    // Create notifications for users
    for (const doc of subscriptionsSnapshot.docs) {
      const userId = doc.data().userId;
      const eventsUsed = doc.data().eventsCreatedThisMonth;
      const remaining = 5 - eventsUsed;
      
      try {
        // Create notification in Firestore
        await db.collection('notifications').add({
          userId: userId,
          title: remaining === 0 ? 'Monthly Event Limit Reached' : 'Event Limit Almost Reached',
          message: remaining === 0
            ? 'Your 5-event monthly limit has been reached. It will reset on the 1st. Upgrade to Premium for unlimited events!'
            : `You have ${remaining} event${remaining !== 1 ? 's' : ''} remaining this month. Your limit resets on the 1st.`,
          type: 'usage_reminder',
          read: false,
          createdAt: now,
          data: {
            eventsUsed: eventsUsed,
            remaining: remaining,
            upgradeUrl: '/premium-upgrade',
          },
        });
        
        // Send push notification if user has FCM token
        await sendNotificationToUser(userId, {
          type: 'usage_reminder',
          title: remaining === 0 ? 'Monthly Event Limit Reached' : 'Event Limit Almost Reached',
          body: remaining === 0
            ? 'Your 5-event monthly limit has been reached. It will reset on the 1st.'
            : `You have ${remaining} event${remaining !== 1 ? 's' : ''} remaining this month.`,
          data: {
            eventsUsed: eventsUsed,
            remaining: remaining,
          },
        }, db);
        
        reminderCount++;
      } catch (error) {
        logger.error(`Error sending reminder to user ${userId}:`, error);
      }
    }
    
    logger.info(`✅ Sent reminders to ${reminderCount} users`);
    return { success: true, count: reminderCount, timestamp: now };
  } catch (error) {
    logger.error('❌ Error sending usage reminders:', error);
    throw error;
  }
});
