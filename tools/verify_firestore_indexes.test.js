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

test("unexpected TTL and extra field indexes cannot silently survive promotion", () => {
  const result = inspect(manifest, [], [{
    name: "projects/demo/databases/(default)/collectionGroups/Followers/fields/userId",
    ttlConfig: {state: "ACTIVE"},
    indexConfig: {indexes: [
      {queryScope: "COLLECTION_GROUP", state: "READY", fields: [{fieldPath: "userId", order: "ASCENDING"}]},
      {queryScope: "COLLECTION_GROUP", state: "READY", fields: [{fieldPath: "userId", order: "DESCENDING"}]},
    ]},
  }]);
  assert.equal(result.extra.length, 2);
  assert.ok(result.extra.some((entry) => entry.startsWith("ttl:")));
});

test("required TTL is unavailable until ACTIVE even when field indexes are ready", () => {
  const ttlManifest = {indexes: [], fieldOverrides: [{collectionGroup: "Tokens", fieldPath: "expiresAt", indexes: [], ttl: true}]};
  const field = {name: "projects/demo/databases/(default)/collectionGroups/Tokens/fields/expiresAt", indexConfig: {indexes: []}, ttlConfig: {state: "CREATING"}};
  assert.equal(inspect(ttlManifest, [], [field]).pending.length, 1);
  field.ttlConfig.state = "ACTIVE";
  assert.deepEqual(inspect(ttlManifest, [], [field]), {missing: [], pending: [], terminal: [], extra: []});
});
