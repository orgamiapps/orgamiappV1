/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");

// Initialize Firebase Admin SDK
const admin = require("firebase-admin");
admin.initializeApp();

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
