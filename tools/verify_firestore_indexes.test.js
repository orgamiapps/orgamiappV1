"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {inspect} = require("./verify_firestore_indexes");

const manifest = {
  indexes: [],
  fieldOverrides: [{
    collectionGroup: "Followers",
    fieldPath: "userId",
    indexes: [{order: "ASCENDING", queryScope: "COLLECTION_GROUP"}],
  }],
};

test("field override verifier accepts a ready collection-group index", () => {
  const result = inspect(manifest, [], [{
    name: "projects/demo/databases/(default)/collectionGroups/Followers/fields/userId",
    indexConfig: {indexes: [{
      queryScope: "COLLECTION_GROUP",
      state: "READY",
      fields: [{fieldPath: "userId", order: "ASCENDING"}],
    }]},
  }]);
  assert.deepEqual(result.missing, []);
  assert.deepEqual(result.pending, []);
});

test("field override verifier rejects a missing collection-group index", () => {
  const result = inspect(manifest, [], []);
  assert.match(result.missing[0], /Followers\|userId/);
});
