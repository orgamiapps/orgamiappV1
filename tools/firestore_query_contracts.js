"use strict";

module.exports = Object.freeze([
  {
    collectionGroup: "Followers",
    filters: [{fieldPath: "userId", operator: "==", value: "string"}],
  },
  {
    collectionGroup: "Discovery",
    filters: [{
      fieldPath: "nearbyInterestNotifications",
      operator: "==",
      value: "boolean",
    }],
  },
  {
    collectionGroup: "Members",
    filters: [{fieldPath: "userId", operator: "==", value: "string"}],
  },
  {
    collectionGroup: "Members",
    filters: [
      {fieldPath: "userId", operator: "==", value: "string"},
      {fieldPath: "status", operator: "==", value: "approved"},
    ],
  },
  {
    collectionGroup: "JoinRequests",
    filters: [{fieldPath: "userId", operator: "==", value: "string"}],
  },
  {
    collectionGroup: "Attendance",
    filters: [{fieldPath: "eventId", operator: "in", value: "string-list"}],
  },
]);
