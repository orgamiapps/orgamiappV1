"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {memoryAdmin} = require("./helpers/community-memory");
const {createPublicProfileHandlers, profileIds, searchInput, normalizedUsername} = require("../profiles/public-profiles");
const {limitProfileReads, publicProfile, requireProfileCaller} = require("../profiles/access");
const request = (data = {}, uid = "viewer") => ({auth: {uid, token: {firebase: {sign_in_provider: "password"}}}, app: {appId: "fixture"}, data});

test("known-ID profiles return only public card fields, including opted-out contacts", async () => {
  const admin = memoryAdmin({
    "Customers/other": {name: "Other Member", username: "other", email: "secret@example.test", phoneNumber: "secret-phone", age: 23,
      gender: "private", favorites: ["private-saved"], eventsCreated: 12, fcmToken: "secret-token", unknownPrivateMap: {secret: true},
      profilePictureUrl: "https://example.test/avatar.png", bannerUrl: "javascript:alert(1)", bio: "Public bio", isDiscoverable: false},
    "Customers/deleted": {name: "Deleted", isDeleted: true}, "Customers/deleting": {name: "Deleting"},
    "account_deletion_jobs/deleting": {status: "running"},
  });
  const result = await createPublicProfileHandlers(admin).get(request({userIds: ["other", "other", "missing", "deleted", "deleting"]}));
  assert.deepEqual(result, {profiles: [{uid: "other", name: "Other Member", username: "other",
    profilePictureUrl: "https://example.test/avatar.png", bannerUrl: null, bio: "Public bio", isDiscoverable: false}]});
});

test("public search is bounded, honors discoverability and rejects email lookup", async () => {
  const admin = memoryAdmin({
    "Customers/anna": {name: "Anna", username: "anna", isDiscoverable: true, email: "private@example.test"},
    "Customers/annabel": {name: "Annabel", username: "annabel", isDiscoverable: false},
    "Customers/legacy": {name: "Ann Legacy", username: "annlegacy"},
    "Customers/deleting": {name: "Ann Deleting", username: "anndeleting", isDiscoverable: true},
    "account_deletion_jobs/deleting": {status: "running"},
  });
  const handler = createPublicProfileHandlers(admin);
  assert.deepEqual((await handler.search(request({query: "@ann", limit: 2}))).profiles.map((row) => row.uid), ["anna"]);
  assert.deepEqual((await handler.search(request({query: "", limit: 50}))).profiles.map((row) => row.uid), ["anna"]);
  await assert.rejects(handler.search(request({query: "private@example.test"})), {code: "invalid-argument"});
  for (const limit of [0, 51, "20", 1.5, null]) assert.throws(() => searchInput({query: "Ann", limit}), {code: "invalid-argument"});
  assert.throws(() => profileIds(Array(51).fill("anna")), {code: "invalid-argument"});
  assert.throws(() => profileIds(["../private"]), {code: "invalid-argument"});
  assert.deepEqual(profileIds(["imported.account:123"]), ["imported.account:123"]);
  assert.throws(() => profileIds(["invalid\naccount"]), {code: "invalid-argument"});
});

test("profile reads and searches recheck current deletion and privacy state", async () => {
  const admin = memoryAdmin({"Customers/anna": {name: "Anna", username: "anna", isDiscoverable: true}});
  const original = admin.db.collection;
  function queryProxy(query) {
    return new Proxy(query, {get(target, property) {
      if (property === "get") return async () => {
        const result = await target.get();
        admin.db.values.set("Customers/anna", {name: "Anna", username: "anna", isDiscoverable: false});
        return result;
      };
      if (["where", "limit"].includes(property)) return (...args) => queryProxy(target[property](...args));
      return target[property];
    }});
  }
  admin.db.collection = (name) => name === "Customers" ? queryProxy(original(name)) : original(name);
  assert.deepEqual(await createPublicProfileHandlers(admin).search(request({query: "Anna"})), {profiles: []});
  admin.db.values.set("account_deletion_jobs/viewer", {status: "inventory"});
  await assert.rejects(createPublicProfileHandlers(admin).get(request({userIds: ["anna"]})), {code: "failed-precondition"});
});

test("opted-out profiles cannot consume the visible prefix search limit", async () => {
  const initial = {"Customers/z-visible": {name: "Anna Visible", username: "anna_visible", isDiscoverable: true}};
  for (let index = 0; index < 60; index++) initial[`Customers/a-hidden-${index}`] = {name: "Anna Hidden", username: "anna_hidden", isDiscoverable: false};
  const handler = createPublicProfileHandlers(memoryAdmin(initial));
  const result = await handler.search(request({query: "anna", limit: 1}));
  assert.deepEqual(result.profiles.map((profile) => profile.uid), ["z-visible"]);
});

test("username availability returns normalized conflicts without exposing the matching private account", async () => {
  const admin = memoryAdmin({"Customers/private-owner": {username: "reserved", isDiscoverable: false, email: "private@example.test"},
    "Customers/viewer": {username: "mine"}});
  const handler = createPublicProfileHandlers(admin);
  assert.deepEqual(await handler.username(request({username: "  ReSeRvEd  "})), {username: "reserved", available: false});
  assert.deepEqual(await handler.username(request({username: "MINE"})), {username: "mine", available: true});
  assert.deepEqual(await handler.username(request({username: "available"})), {username: "available", available: true});
  for (const name of ["ab", "has space", "a@b.com", "x".repeat(51), null]) assert.throws(() => normalizedUsername(name), {code: "invalid-argument"});
});

test("profile rate limits and auth checks fail closed with no private data reads", async () => {
  const admin = memoryAdmin();
  await limitProfileReads(admin.db, "viewer", "search", 1, 60000);
  await assert.rejects(limitProfileReads(admin.db, "viewer", "search", 1, 60000), {code: "resource-exhausted"});
  await limitProfileReads(admin.db, "viewer", "search", 1, 120000);
  assert.equal(admin.db.values.get("ProfileReadLimits/viewer").buckets.search.count, 1);
  assert.throws(() => requireProfileCaller({auth: {uid: "guest", token: {firebase: {sign_in_provider: "anonymous"}}}}), {code: "unauthenticated"});
  assert.throws(() => requireProfileCaller({}), {code: "unauthenticated"});
  const before = process.env.FUNCTIONS_EMULATOR;
  process.env.FUNCTIONS_EMULATOR = "false";
  try { assert.throws(() => requireProfileCaller({auth: request().auth}), {code: "failed-precondition"}); }
  finally { if (before === undefined) delete process.env.FUNCTIONS_EMULATOR; else process.env.FUNCTIONS_EMULATOR = before; }
});

test("public DTO cannot serialize nested profile metadata or credential-bearing URLs", () => {
  const result = publicProfile({id: "user", data: () => ({name: {email: "secret"}, bio: {phone: "secret"},
    username: ["secret"], profilePictureUrl: "https://secret:password@example.test/avatar", bannerUrl: "https://example.test/banner",
    occupation: "Private extra field"})});
  assert.deepEqual(result, {uid: "user", name: "Attendus member", username: null, profilePictureUrl: null,
    bannerUrl: "https://example.test/banner", bio: null, isDiscoverable: false});
});
