"use strict";

const DISCOVERY_CATEGORY_VERSION = 1;

const DISCOVERY_CATEGORIES = Object.freeze([
  {id: "music-nightlife", label: "Music & Nightlife", legacy: ["entertainment"], keywords: ["concert", "music", "dj", "nightlife", "club", "festival", "karaoke"]},
  {id: "food-drink", label: "Food & Drink", legacy: ["food & dining"], keywords: ["food", "drink", "dinner", "brunch", "tasting", "wine", "beer", "cooking"]},
  {id: "business-networking", label: "Business & Networking", legacy: ["social & networking"], keywords: ["business", "networking", "founder", "career", "professional", "entrepreneur", "startup"]},
  {id: "technology-innovation", label: "Technology & Innovation", legacy: ["technology"], keywords: ["technology", "tech", "software", "developer", "coding", "ai", "crypto", "innovation"]},
  {id: "classes-workshops", label: "Classes & Workshops", legacy: ["education & learning"], keywords: ["class", "workshop", "course", "lesson", "seminar", "training", "learn"]},
  {id: "arts-culture", label: "Arts & Culture", legacy: ["arts & culture"], keywords: ["art", "museum", "gallery", "theater", "theatre", "dance", "culture", "exhibit"]},
  {id: "film-entertainment", label: "Film & Entertainment", legacy: ["entertainment"], keywords: ["film", "movie", "cinema", "comedy", "show", "performance", "screening"]},
  {id: "sports-fitness", label: "Sports & Fitness", legacy: ["sports & fitness"], keywords: ["sport", "fitness", "run", "race", "game", "yoga", "workout", "pickleball"]},
  {id: "health-wellness", label: "Health & Wellness", legacy: [], keywords: ["health", "wellness", "meditation", "mindfulness", "healing", "nutrition", "self-care"]},
  {id: "community-causes", label: "Community & Causes", legacy: ["community & charity"], keywords: ["community", "charity", "nonprofit", "volunteer", "fundraiser", "cause", "environment"]},
  {id: "family-kids", label: "Family & Kids", legacy: [], keywords: ["family", "kids", "children", "parents", "parenting", "teen", "youth"]},
  {id: "hobbies-games", label: "Hobbies & Games", legacy: [], keywords: ["hobby", "games", "gaming", "board game", "craft", "book club", "trivia", "collecting"]},
  {id: "outdoors-adventure", label: "Outdoors & Adventure", legacy: [], keywords: ["outdoor", "adventure", "hiking", "camping", "travel", "nature", "kayak", "tour"]},
  {id: "faith-spirituality", label: "Faith & Spirituality", legacy: [], keywords: ["faith", "spiritual", "church", "religion", "worship", "bible", "prayer"]},
  {id: "seasonal-holiday", label: "Seasonal & Holiday", legacy: [], keywords: ["holiday", "seasonal", "christmas", "halloween", "new year", "easter", "thanksgiving"]},
]);

const CATEGORY_BY_ID = new Map(DISCOVERY_CATEGORIES.map((item) => [item.id, item]));

function validCategoryIds(values) {
  if (!Array.isArray(values)) return [];
  return [...new Set(values.map(String).filter((id) => CATEGORY_BY_ID.has(id)))].slice(0, 3);
}

function inferDiscoveryCategories(event = {}) {
  if (event.discoveryCategorySource === "organizer") {
    const explicit = validCategoryIds(event.discoveryCategoryIds);
    if (explicit.length) {
      const primary = CATEGORY_BY_ID.has(String(event.primaryDiscoveryCategoryId || "")) &&
        explicit.includes(String(event.primaryDiscoveryCategoryId)) ?
        String(event.primaryDiscoveryCategoryId) : explicit[0];
      return {primaryDiscoveryCategoryId: primary, discoveryCategoryIds: explicit,
        discoveryCategorySource: "organizer", discoveryCategoryVersion: DISCOVERY_CATEGORY_VERSION};
    }
  }

  const legacy = (Array.isArray(event.categories) ? event.categories : [])
      .map((value) => String(value).trim().toLowerCase());
  const text = [event.title, event.description, ...legacy]
      .filter(Boolean).join(" ").toLowerCase();
  const scored = DISCOVERY_CATEGORIES.map((category, order) => {
    let score = category.legacy.reduce((sum, value) => sum + (legacy.includes(value) ? 8 : 0), 0);
    score += category.keywords.reduce((sum, keyword) => sum + (text.includes(keyword) ? 2 : 0), 0);
    return {id: category.id, score, order};
  }).filter((item) => item.score > 0)
      .sort((left, right) => right.score - left.score || left.order - right.order);
  const ids = scored.slice(0, 3).map((item) => item.id);
  if (!ids.length) ids.push("community-causes");
  return {primaryDiscoveryCategoryId: ids[0], discoveryCategoryIds: ids,
    discoveryCategorySource: "inferred", discoveryCategoryVersion: DISCOVERY_CATEGORY_VERSION};
}

function categoryFacets(events, preferences = {}) {
  const preferred = new Set((preferences.preferredDiscoveryCategoryIds || []).map(String));
  return DISCOVERY_CATEGORIES.map((category, order) => {
    const matches = events.filter((event) => event.discoveryCategoryIds.includes(category.id));
    return {id: category.id, label: category.label, count: matches.length,
      representativeImageUrl: matches.find((event) => event.imageUrl)?.imageUrl || null,
      preferred: preferred.has(category.id), order};
  }).sort((left, right) => Number(right.preferred) - Number(left.preferred) ||
    right.count - left.count || left.order - right.order)
      .map(({preferred: _preferred, order: _order, ...facet}) => facet);
}

module.exports = {CATEGORY_BY_ID, DISCOVERY_CATEGORIES, DISCOVERY_CATEGORY_VERSION,
  categoryFacets, inferDiscoveryCategories, validCategoryIds};
