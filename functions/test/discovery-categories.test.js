"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {DISCOVERY_CATEGORIES, inferDiscoveryCategories, validCategoryIds} =
  require("../discovery/category-catalog");
const {applyV2Filters} = require("../discovery/marketplace");

test("discovery catalog has 15 stable unique categories", () => {
  assert.equal(DISCOVERY_CATEGORIES.length, 15);
  assert.equal(new Set(DISCOVERY_CATEGORIES.map((item) => item.id)).size, 15);
});

test("inference maps legacy categories and relevant text deterministically", () => {
  const result = inferDiscoveryCategories({
    categories: ["Entertainment"],
    title: "Live jazz concert downtown",
    description: "An evening of music",
  });
  assert.equal(result.primaryDiscoveryCategoryId, "music-nightlife");
  assert.equal(result.discoveryCategorySource, "inferred");
  assert.ok(result.discoveryCategoryIds.length <= 3);
});

test("organizer-confirmed categories are preserved and normalized", () => {
  const result = inferDiscoveryCategories({
    discoveryCategorySource: "organizer",
    primaryDiscoveryCategoryId: "food-drink",
    discoveryCategoryIds: ["food-drink", "music-nightlife", "invalid", "arts-culture"],
    categories: ["Technology"],
  });
  assert.deepEqual(result.discoveryCategoryIds,
      ["food-drink", "music-nightlife", "arts-culture"]);
  assert.equal(result.primaryDiscoveryCategoryId, "food-drink");
  assert.deepEqual(validCategoryIds(["food-drink", "food-drink", "invalid"]), ["food-drink"]);
});

test("V2 selected category is a hard eligibility constraint", () => {
  const events = [
    {id: "music", discoveryCategoryIds: ["music-nightlife"], selectedDateTime: new Date().toISOString(), ticketsEnabled: false},
    {id: "food", discoveryCategoryIds: ["food-drink"], selectedDateTime: new Date().toISOString(), ticketsEnabled: false},
  ];
  assert.deepEqual(
      applyV2Filters(events, {selectedCategoryId: "food-drink"}, new Date()).map((item) => item.id),
      ["food"],
  );
});
