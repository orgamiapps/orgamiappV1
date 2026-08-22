"use strict";

const crypto = require("node:crypto");
const {HttpsError} = require("firebase-functions/v2/https");

const WIZARD_SCHEMA_VERSION = 2;
const QUESTION_TYPES = new Set([
  "short_text", "long_text", "single_choice", "multiple_choice", "acknowledgement",
]);
const QUESTION_TIMINGS = new Set(["registration", "check_in"]);
const REGISTRATION_MODES = new Set(["rsvp", "free_ticket", "paid_ticket"]);
const APPROVAL_MODES = new Set(["automatic", "manual"]);
const RECURRENCE_FREQUENCIES = new Set(["daily", "weekly", "weekdays", "monthly"]);
const REMINDER_PRESETS = new Set(["off", "24h", "1h", "24h_1h"]);
const CHECK_IN_PROFILES = new Set(["self_check_in", "staff_entry", "hybrid"]);
const CHECK_IN_ELIGIBILITY = new Set(["open", "registered_only", "ticket_required"]);

const TEMPLATE_CATALOG = Object.freeze([
  {id: "community_meetup", label: "Community meetup", categoryId: "community-causes",
    durationMinutes: 120, registrationMode: "rsvp", attendanceProfile: "hybrid"},
  {id: "networking", label: "Networking event", categoryId: "business-networking",
    durationMinutes: 120, registrationMode: "rsvp", attendanceProfile: "hybrid"},
  {id: "workshop", label: "Class or workshop", categoryId: "classes-workshops",
    durationMinutes: 120, registrationMode: "free_ticket", attendanceProfile: "hybrid"},
  {id: "conference", label: "Conference or panel", categoryId: "business-networking",
    durationMinutes: 240, registrationMode: "free_ticket", attendanceProfile: "staff_entry"},
  {id: "webinar", label: "Online webinar", categoryId: "technology-innovation",
    durationMinutes: 60, registrationMode: "rsvp", attendanceProfile: "self_check_in",
    locationType: "online"},
  {id: "music_social", label: "Music or social event", categoryId: "music-nightlife",
    durationMinutes: 180, registrationMode: "free_ticket", attendanceProfile: "hybrid"},
  {id: "fitness_outdoor", label: "Fitness or outdoor activity", categoryId: "sports-fitness",
    durationMinutes: 90, registrationMode: "rsvp", attendanceProfile: "hybrid"},
  {id: "fundraiser", label: "Fundraiser or volunteer event", categoryId: "community-causes",
    durationMinutes: 180, registrationMode: "rsvp", attendanceProfile: "hybrid"},
]);

function plainObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function stringValue(value, maximum = 5000) {
  return typeof value === "string" ? value.trim().slice(0, maximum) : "";
}

function optionalString(value, maximum = 5000) {
  const normalized = stringValue(value, maximum);
  return normalized || null;
}

function boundedInteger(value, minimum, maximum, fallback) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? Math.min(maximum, Math.max(minimum, parsed)) : fallback;
}

function booleanValue(value, fallback = false) {
  return typeof value === "boolean" ? value : fallback;
}

function enumValue(value, allowed, fallback) {
  const normalized = stringValue(value, 80);
  return allowed.has(normalized) ? normalized : fallback;
}

function stableId(prefix, value) {
  return `${prefix}_${crypto.createHash("sha256").update(String(value)).digest("hex").slice(0, 24)}`;
}

function timestampDate(value) {
  if (value?.toDate) return value.toDate();
  const parsed = value instanceof Date ? value : new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function normalizeQuestion(raw, index) {
  const question = plainObject(raw);
  const type = enumValue(question.type, QUESTION_TYPES, "long_text");
  const options = ["single_choice", "multiple_choice"].includes(type) ?
    [...new Set((Array.isArray(question.options) ? question.options : [])
        .map((value) => stringValue(value, 120)).filter(Boolean))].slice(0, 20) : [];
  if (["single_choice", "multiple_choice"].includes(type) && options.length < 2) {
    throw new HttpsError("invalid-argument", "Choice questions require at least two options.");
  }
  const prompt = stringValue(question.prompt || question.questionTitle, 300);
  if (!prompt) throw new HttpsError("invalid-argument", "Every attendee question needs a prompt.");
  return {
    id: stringValue(question.id, 100) || stableId("question", `${index}:${prompt}`),
    prompt,
    questionTitle: prompt,
    type,
    options,
    timing: enumValue(question.timing, QUESTION_TIMINGS, "check_in"),
    required: booleanValue(question.required),
    order: index,
    version: 2,
  };
}

function normalizeRegistration(raw) {
  const data = plainObject(raw);
  const mode = enumValue(data.mode, REGISTRATION_MODES, "rsvp");
  const capacity = data.capacity === null || data.capacity === "" || data.capacity === undefined ? null :
    boundedInteger(data.capacity, 1, 100000, null);
  if (data.capacity !== null && data.capacity !== "" && data.capacity !== undefined && capacity === null) {
    throw new HttpsError("invalid-argument", "Capacity must be a positive whole number.");
  }
  return {
    mode,
    capacity,
    approvalMode: enumValue(data.approvalMode, APPROVAL_MODES, "automatic"),
    waitlistEnabled: capacity !== null && booleanValue(data.waitlistEnabled, true),
    opensAt: optionalString(data.opensAt, 80),
    closesAt: optionalString(data.closesAt, 80),
    priceUsd: mode === "paid_ticket" ? Math.max(0, Number(data.priceUsd || 0)) : 0,
    refundTerms: mode === "paid_ticket" ? stringValue(data.refundTerms, 2000) : "",
  };
}

function normalizeCheckInPolicy(raw, registrationMode) {
  const data = plainObject(raw);
  const defaultEligibility = registrationMode === "paid_ticket" ? "ticket_required" :
    registrationMode === "free_ticket" ? "registered_only" : "open";
  return {
    version: 2,
    profile: enumValue(data.profile, CHECK_IN_PROFILES, "hybrid"),
    eligibility: enumValue(data.eligibility, CHECK_IN_ELIGIBILITY, defaultEligibility),
    opensBeforeMinutes: boundedInteger(data.opensBeforeMinutes, 0, 1440, 60),
    closesAfterMinutes: boundedInteger(data.closesAfterMinutes, 0, 1440, 60),
    allowReentry: booleanValue(data.allowReentry),
    checkoutEnabled: booleanValue(data.checkoutEnabled),
    proximityAssist: booleanValue(data.proximityAssist),
    staffFallback: booleanValue(data.staffFallback, true),
    passLockEnabled: booleanValue(data.passLockEnabled),
    needsOrganizerReview: false,
  };
}

function normalizeRecurrence(raw) {
  const data = plainObject(raw);
  if (data.enabled !== true) return {enabled: false};
  const frequency = enumValue(data.frequency, RECURRENCE_FREQUENCIES, "weekly");
  const endMode = data.endMode === "date" ? "date" : "count";
  const weekDays = [...new Set((Array.isArray(data.weekDays) ? data.weekDays : [])
      .map(Number).filter((value) => Number.isInteger(value) && value >= 1 && value <= 7))]
      .sort((a, b) => a - b);
  if (frequency === "weekdays" && weekDays.length === 0) {
    throw new HttpsError("invalid-argument", "Select at least one weekday.");
  }
  return {
    enabled: true,
    frequency,
    interval: boundedInteger(data.interval, 1, 12, 1),
    weekDays,
    endMode,
    occurrenceCount: endMode === "count" ? boundedInteger(data.occurrenceCount, 2, 52, 2) : null,
    endDate: endMode === "date" ? stringValue(data.endDate, 20) : null,
  };
}

function normalizeExperience(raw, registrationMode) {
  const data = plainObject(raw);
  const agenda = (Array.isArray(data.agenda) ? data.agenda : []).slice(0, 50).map((entry, index) => {
    const item = plainObject(entry);
    const title = stringValue(item.title, 200);
    if (!title) throw new HttpsError("invalid-argument", "Agenda items need a title.");
    return {id: stringValue(item.id, 100) || stableId("agenda", `${index}:${title}`), title,
      details: stringValue(item.details, 1000),
      offsetMinutes: boundedInteger(item.offsetMinutes, 0, 10080, 0), order: index};
  });
  return {
    agenda,
    accessibilityOptions: [...new Set((Array.isArray(data.accessibilityOptions) ?
      data.accessibilityOptions : []).map((value) => stringValue(value, 80)).filter(Boolean))].slice(0, 20),
    accessibilityDetails: stringValue(data.accessibilityDetails, 2000),
    thingsToBring: [...new Set((Array.isArray(data.thingsToBring) ? data.thingsToBring : [])
        .map((value) => stringValue(value, 160)).filter(Boolean))].slice(0, 30),
    publicContact: {
      name: stringValue(plainObject(data.publicContact).name, 160),
      email: stringValue(plainObject(data.publicContact).email, 254).toLowerCase(),
      visible: booleanValue(plainObject(data.publicContact).visible),
    },
    checkInPolicy: normalizeCheckInPolicy(data.checkInPolicy, registrationMode),
    checkInStaff: [...new Set((Array.isArray(data.checkInStaff) ? data.checkInStaff : [])
        .map((value) => stringValue(value, 128)).filter(Boolean))].slice(0, 100),
    coHosts: [...new Set((Array.isArray(data.coHosts) ? data.coHosts : [])
        .map((value) => stringValue(value, 128)).filter(Boolean))].slice(0, 25),
  };
}

function normalizeDraftForm(raw) {
  const data = plainObject(raw);
  const registration = normalizeRegistration(data.registration);
  const startAt = optionalString(data.startAt, 80);
  const endAt = optionalString(data.endAt, 80);
  return {
    title: stringValue(data.title, 160),
    description: stringValue(data.description, 10000),
    imageUrl: stringValue(data.imageUrl, 2000),
    startAt,
    endAt,
    eventTimeZone: stringValue(data.eventTimeZone, 100) || "UTC",
    locationType: data.locationType === "online" ? "online" : "in_person",
    location: stringValue(data.location, 1000),
    locationName: stringValue(data.locationName, 300),
    placeId: stringValue(data.placeId, 300),
    city: stringValue(data.city, 160),
    regionCode: stringValue(data.regionCode, 20).toUpperCase(),
    countryCode: stringValue(data.countryCode, 10).toUpperCase() || "US",
    streetAddress: stringValue(data.streetAddress, 300),
    postalCode: stringValue(data.postalCode, 30),
    latitude: Number.isFinite(Number(data.latitude)) ? Number(data.latitude) : 0,
    longitude: Number.isFinite(Number(data.longitude)) ? Number(data.longitude) : 0,
    radius: Math.max(0, Number(data.radius || 0)),
    organizationId: optionalString(data.organizationId, 128),
    private: booleanValue(data.private),
    primaryDiscoveryCategoryId: optionalString(data.primaryDiscoveryCategoryId, 100),
    discoveryCategoryIds: [...new Set((Array.isArray(data.discoveryCategoryIds) ?
      data.discoveryCategoryIds : []).map((value) => stringValue(value, 100)).filter(Boolean))].slice(0, 3),
    registration,
    questions: (Array.isArray(data.questions) ? data.questions : []).slice(0, 30)
        .map(normalizeQuestion),
    experience: normalizeExperience(data.experience, registration.mode),
    recurrence: normalizeRecurrence(data.recurrence),
    reminderPreset: enumValue(data.reminderPreset, REMINDER_PRESETS, "24h_1h"),
  };
}

function validatePublishable(form, {paidEnabled = false} = {}) {
  const errors = [];
  if (!form.title) errors.push({stage: "basics", field: "title", message: "Add an event title."});
  const start = timestampDate(form.startAt);
  const end = timestampDate(form.endAt);
  if (!start) errors.push({stage: "basics", field: "startAt", message: "Choose a valid start time."});
  if (!end || (start && end <= start)) {
    errors.push({stage: "basics", field: "endAt", message: "End time must be after start time."});
  }
  if (form.locationType === "online" && !form.location) {
    errors.push({stage: "basics", field: "location", message: "Add the online event location."});
  }
  if (form.locationType === "in_person" &&
      (!form.location || !Number.isFinite(form.latitude) || !Number.isFinite(form.longitude) ||
       (form.latitude === 0 && form.longitude === 0))) {
    errors.push({stage: "basics", field: "location", message: "Select a valid event location."});
  }
  if (!form.private && !form.primaryDiscoveryCategoryId) {
    errors.push({stage: "publish", field: "primaryDiscoveryCategoryId",
      message: "Choose a primary discovery category."});
  }
  if (form.registration.mode === "paid_ticket" && !paidEnabled) {
    errors.push({stage: "registration", field: "mode", message: "Paid ticket checkout is unavailable."});
  }
  if (form.registration.mode === "paid_ticket" && form.registration.priceUsd < 0.5) {
    errors.push({stage: "registration", field: "priceUsd", message: "Paid tickets must cost at least $0.50."});
  }
  return errors;
}

function occurrenceLimitForTier(tier) {
  if (tier === "premium") return 52;
  if (tier === "basic") return 26;
  return 12;
}

function localParts(date, timeZone) {
  const values = {};
  for (const part of new Intl.DateTimeFormat("en-US", {timeZone, hourCycle: "h23",
    year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit",
    minute: "2-digit", second: "2-digit"}).formatToParts(date)) {
    if (part.type !== "literal") values[part.type] = Number(part.value);
  }
  return values;
}

function localPartsToUtc(parts, timeZone) {
  const desired = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second || 0);
  let guess = desired;
  for (let attempt = 0; attempt < 3; attempt++) {
    const actual = localParts(new Date(guess), timeZone);
    const represented = Date.UTC(actual.year, actual.month - 1, actual.day,
        actual.hour, actual.minute, actual.second || 0);
    guess += desired - represented;
  }
  return new Date(guess);
}

function addLocalCalendarDays(parts, days) {
  const placeholder = new Date(Date.UTC(parts.year, parts.month - 1, parts.day + days,
      parts.hour, parts.minute, parts.second || 0));
  return {year: placeholder.getUTCFullYear(), month: placeholder.getUTCMonth() + 1,
    day: placeholder.getUTCDate(), hour: parts.hour, minute: parts.minute, second: parts.second || 0};
}

function addLocalCalendarMonths(parts, months) {
  const last = new Date(Date.UTC(parts.year, parts.month + months, 0)).getUTCDate();
  const placeholder = new Date(Date.UTC(parts.year, parts.month - 1 + months, 1));
  return {year: placeholder.getUTCFullYear(), month: placeholder.getUTCMonth() + 1,
    day: Math.min(parts.day, last), hour: parts.hour, minute: parts.minute, second: parts.second || 0};
}

function isoWeekday(parts) {
  const day = new Date(Date.UTC(parts.year, parts.month - 1, parts.day)).getUTCDay();
  return day === 0 ? 7 : day;
}

function generateOccurrences(startValue, recurrence, maximum, timeZone = "UTC") {
  const start = timestampDate(startValue);
  if (!start) throw new HttpsError("invalid-argument", "A valid event start time is required.");
  try {
    localParts(start, timeZone);
  } catch (_) {
    throw new HttpsError("invalid-argument", "A valid IANA event timezone is required.");
  }
  if (!recurrence?.enabled) return [start];
  const wanted = recurrence.endMode === "count" ? recurrence.occurrenceCount : maximum;
  if (recurrence.endMode === "count" && wanted > maximum) {
    throw new HttpsError("resource-exhausted",
        `Your plan supports up to ${maximum} occurrences in a rolling year.`);
  }
  const limit = Math.min(maximum, wanted || maximum);
  const endDate = recurrence.endMode === "date" ? timestampDate(`${recurrence.endDate}T23:59:59Z`) : null;
  if (recurrence.endMode === "date" && (!endDate || endDate <= start ||
      endDate.getTime() - start.getTime() > 366 * 86400000)) {
    throw new HttpsError("invalid-argument", "Choose a series end date within 12 months.");
  }
  const result = [start];
  let cursorParts = localParts(start, timeZone);
  let guard = 0;
  while (result.length < limit && guard++ < 800) {
    if (recurrence.frequency === "daily") cursorParts = addLocalCalendarDays(cursorParts, recurrence.interval);
    if (recurrence.frequency === "weekly") cursorParts = addLocalCalendarDays(cursorParts, 7 * recurrence.interval);
    if (recurrence.frequency === "monthly") cursorParts = addLocalCalendarMonths(cursorParts, recurrence.interval);
    if (recurrence.frequency === "weekdays") {
      do cursorParts = addLocalCalendarDays(cursorParts, 1);
      while (!recurrence.weekDays.includes(isoWeekday(cursorParts)));
    }
    const cursor = localPartsToUtc(cursorParts, timeZone);
    if (endDate && cursor > endDate) break;
    if (cursor.getTime() - start.getTime() > 366 * 24 * 60 * 60 * 1000) break;
    result.push(new Date(cursor.getTime()));
  }
  return result;
}

function seriesOccurrenceStart(referenceValue, sourceValue, desiredValue, timeZone = "UTC") {
  const reference = timestampDate(referenceValue);
  const source = timestampDate(sourceValue);
  const desired = timestampDate(desiredValue);
  if (!reference || !source || !desired) {
    throw new HttpsError("invalid-argument", "Valid series edit dates are required.");
  }
  const referenceParts = localParts(reference, timeZone);
  const sourceParts = localParts(source, timeZone);
  const desiredParts = localParts(desired, timeZone);
  const sourceDay = Date.UTC(sourceParts.year, sourceParts.month - 1, sourceParts.day);
  const desiredDay = Date.UTC(desiredParts.year, desiredParts.month - 1, desiredParts.day);
  const dayDelta = Math.round((desiredDay - sourceDay) / 86400000);
  const shifted = addLocalCalendarDays(referenceParts, dayDelta);
  shifted.hour = desiredParts.hour;
  shifted.minute = desiredParts.minute;
  shifted.second = desiredParts.second;
  return localPartsToUtc(shifted, timeZone);
}

function sanitizedTemplateForm(form, {includeLocation = false, includeContact = false} = {}) {
  const normalized = normalizeDraftForm(form);
  return {
    ...normalized,
    title: "",
    startAt: null,
    endAt: null,
    recurrence: {enabled: false},
    location: includeLocation ? normalized.location : "",
    locationName: includeLocation ? normalized.locationName : "",
    placeId: includeLocation ? normalized.placeId : "",
    streetAddress: includeLocation ? normalized.streetAddress : "",
    postalCode: includeLocation ? normalized.postalCode : "",
    latitude: includeLocation ? normalized.latitude : 0,
    longitude: includeLocation ? normalized.longitude : 0,
    experience: {
      ...normalized.experience,
      publicContact: includeContact ? normalized.experience.publicContact :
        {name: "", email: "", visible: false},
      checkInStaff: [],
      coHosts: [],
    },
  };
}

function sanitizedDuplicateForm(event, questions = []) {
  const raw = plainObject(event);
  const duration = boundedInteger(raw.eventDuration, 1, 168, 1);
  const start = timestampDate(raw.selectedDateTime) || new Date();
  const end = new Date(start.getTime() + duration * 3600000);
  return normalizeDraftForm({
    ...raw,
    title: raw.title ? `${raw.title} — Copy` : "",
    startAt: null,
    endAt: null,
    imageUrl: raw.imageUrl,
    location: raw.locationType === "online" ? "" : raw.location,
    locationName: raw.locationType === "online" ? "" : raw.locationName,
    eventTimeZone: raw.eventTimeZone,
    registration: raw.registrationPolicy || {
      mode: raw.ticketsEnabled ? (Number(raw.ticketPrice || 0) > 0 ? "paid_ticket" : "free_ticket") : "rsvp",
      capacity: raw.maxTickets > 0 ? raw.maxTickets : null,
      approvalMode: "automatic",
      waitlistEnabled: true,
      priceUsd: raw.ticketPrice || 0,
    },
    questions,
    experience: raw.experience || {checkInPolicy: raw.checkInPolicy,
      checkInStaff: [], coHosts: []},
    recurrence: {enabled: false},
    _discardedStart: start.toISOString(),
    _discardedEnd: end.toISOString(),
  });
}

function editableEventForm(event, questions = []) {
  const raw = plainObject(event);
  const start = timestampDate(raw.selectedDateTime) || new Date();
  const minutes = boundedInteger(raw.eventDurationMinutes, 1, 10080,
      boundedInteger(raw.eventDuration, 1, 168, 1) * 60);
  const normalized = sanitizedDuplicateForm(raw, questions);
  return normalizeDraftForm({
    ...normalized,
    title: stringValue(raw.title, 160),
    startAt: start.toISOString(),
    endAt: new Date(start.getTime() + minutes * 60000).toISOString(),
    location: stringValue(raw.location, 1000),
    locationName: stringValue(raw.locationName, 300),
    placeId: stringValue(raw.placeId, 300),
    experience: {
      ...normalized.experience,
      checkInStaff: Array.isArray(raw.checkInStaff) ? raw.checkInStaff : [],
      coHosts: Array.isArray(raw.coHosts) ? raw.coHosts : [],
    },
    recurrence: {enabled: false},
  });
}

module.exports = {
  TEMPLATE_CATALOG,
  WIZARD_SCHEMA_VERSION,
  editableEventForm,
  generateOccurrences,
  normalizeDraftForm,
  normalizeQuestion,
  occurrenceLimitForTier,
  sanitizedDuplicateForm,
  sanitizedTemplateForm,
  seriesOccurrenceStart,
  stableId,
  timestampDate,
  validatePublishable,
};
