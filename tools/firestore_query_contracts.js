"use strict";

module.exports = Object.freeze([
  ...[
    ["Feed", "createdBy", "=="], ["Feed", "moderatedBy", "=="], ["Feed", "deletedBy", "=="],
    ["Feed", "likes", "array-contains"], ["Feed", "voters", "array-contains"],
    ["Comments", "userId", "=="], ["Comments", "likes", "array-contains"],
    ["operations", "actorUid", "=="], ["AccessRequests", "userId", "=="],
  ].map(([collectionGroup, fieldPath, operator]) => ({
    collectionGroup, filters: [{fieldPath, operator, value: "string"}],
  })),
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
