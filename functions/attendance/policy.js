"use strict";
const {HttpsError} = require("firebase-functions/v2/https");

function assertAttendanceEnabled(event) {
  if (event?.checkInPolicy?.profile === "none") {
    throw new HttpsError("failed-precondition", "Attendance tracking is disabled for this event.");
  }
}

module.exports = {assertAttendanceEnabled};
