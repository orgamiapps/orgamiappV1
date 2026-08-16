"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  activePublicEvent,
  buildSections,
  chooseFallbackRadius,
  loadPreferencesSafely,
  scoreEvent,
} = require("../discovery/marketplace");

const now = new Date("2026-08-15T12:00:00.000Z");

function event(id, distanceMiles, overrides = {}) {
  return {
    id,
    title: `Event ${id}`,
    description: "A complete local event description with enough useful information for attendees.",
    groupName: "Organizer",
    customerUid: `owner-${id}`,
    organizationId: null,
    imageUrl: "https://example.test/image.jpg",
    locationName: "Venue",
    locationType: "in_person",
    city: "Boston",
    regionCode: "MA",
    categories: ["Community"],
    selectedDateTime: "2026-08-18T12:00:00.000Z",
    distanceMiles,
    saveCount: 0,
    issuedTickets: 0,
    attendanceCount: 0,
    commentCount: 0,
    isFeatured: false,
    ...overrides,
  };
}

test("radius expansion selects 25, 50, then 100 miles deterministically", () => {
  const events = [5, 10, 20, 30, 40, 49].map((distance, index) => event(String(index), distance));
  assert.equal(chooseFallbackRadius(events, 25), 50);
  assert.equal(chooseFallbackRadius(events.slice(0, 3), 25), 100);
});

test("section building preserves first placement and removes duplicates", () => {
  const local = Array.from({length: 24}, (_, index) => event(String(index), index + 1, {
    isFeatured: index % 3 === 0,
    saveCount: 24 - index,
  }));
  const sections = buildSections(local, [], {}, 50, now);
  const ids = sections.flatMap((section) => section.events.map((item) => item.id));
  assert.equal(ids.length, new Set(ids).size);
  assert.equal(sections[0].id, "recommended");
});

test("ranking is deterministic and paid featured is not a score multiplier", () => {
  const base = event("base", 10);
  assert.equal(scoreEvent(base, {}, now), scoreEvent({...base, isFeatured: true}, {}, now));
  assert.equal(scoreEvent(base, {}, now), scoreEvent(base, {}, now));
});

test("eligibility excludes private, draft, and expired events", () => {
  const future = {private: false, status: "active", selectedDateTime: "2026-08-16T12:00:00Z"};
  assert.equal(activePublicEvent(future, now), true);
  assert.equal(activePublicEvent({...future, private: true}, now), false);
  assert.equal(activePublicEvent({...future, status: "draft"}, now), false);
  assert.equal(activePublicEvent({...future, selectedDateTime: "2026-08-01T12:00:00Z"}, now), false);
});

test("personalization failures fall back to cold-start preferences", async () => {
  const warnings = [];
  const preferences = await loadPreferencesSafely(null, {
    data: {preferredCategories: ["Community"]},
  }, async () => {
    const error = new Error("missing optional index");
    error.code = 9;
    throw error;
  }, {warn: (...values) => warnings.push(values)});
  assert.deepEqual(preferences.preferredCategories, ["Community"]);
  assert.equal(preferences.followedOrganizationIds.size, 0);
  assert.equal(warnings.length, 1);
});
