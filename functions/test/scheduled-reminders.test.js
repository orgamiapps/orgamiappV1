"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  DELIVERY_GRACE_MS,
  eventChanged,
  normalizedEvent,
  normalizedSettings,
  reminderDocumentId,
  scheduleFor,
} = require("../notifications/scheduled-reminders");

test("current event fields are canonical with legacy fallbacks", () => {
  const current = normalizedEvent({
    selectedDateTime: "2026-08-04T18:00:00Z",
    title: "Current title",
    customerUid: "owner",
    status: "Active",
  });
  assert.equal(current.title, "Current title");
  assert.equal(current.startsAt.toISOString(), "2026-08-04T18:00:00.000Z");
  assert.equal(current.status, "active");

  const legacy = normalizedEvent({
    eventDateTime: "2026-08-04T19:00:00Z",
    eventTitle: "Legacy title",
    createdBy: "legacy-owner",
  });
  assert.equal(legacy.title, "Legacy title");
  assert.equal(legacy.ownerUid, "legacy-owner");
});

test("settings validate supported reminder intervals", () => {
  assert.deepEqual(normalizedSettings({eventReminders: false, reminderTime: 30}), {
    enabled: false,
    reminderMinutes: 30,
  });
  assert.equal(normalizedSettings({reminderTime: 17}).reminderMinutes, 60);
});

test("schedule uses event start minus preference and a 15 minute grace", () => {
  const now = new Date("2026-08-04T16:00:00Z");
  const result = scheduleFor({
    selectedDateTime: "2026-08-04T18:00:00Z",
    title: "Town Hall",
    customerUid: "owner",
    status: "active",
  }, {eventReminders: true, reminderTime: 60}, now);
  assert.equal(result.eligible, true);
  assert.equal(result.dueAt.toISOString(), "2026-08-04T17:00:00.000Z");
  assert.equal(
      result.deadlineAt.getTime() - result.dueAt.getTime(),
      DELIVERY_GRACE_MS,
  );
});

test("expired and cancelled events cannot schedule reminders", () => {
  const now = new Date("2026-08-04T17:16:00Z");
  const event = {
    selectedDateTime: "2026-08-04T18:00:00Z",
    title: "Town Hall",
    customerUid: "owner",
    status: "active",
  };
  assert.equal(scheduleFor(event, {reminderTime: 60}, now).reason,
      "delivery_window_expired");
  assert.equal(scheduleFor({...event, status: "cancelled"}, {}, now).reason,
      "event_unavailable");
});

test("reminder ids are deterministic and recipient-specific", () => {
  const first = reminderDocumentId("event-a", "user-a");
  assert.equal(first, reminderDocumentId("event-a", "user-a"));
  assert.notEqual(first, reminderDocumentId("event-a", "user-b"));
  assert.match(first, /^[a-f0-9]{64}$/);
});

test("only reminder-relevant event changes trigger reconciliation", () => {
  const base = {
    selectedDateTime: "2026-08-04T18:00:00Z",
    title: "Town Hall",
    customerUid: "owner",
    status: "active",
  };
  assert.equal(eventChanged(base, {...base, description: "Changed"}), false);
  assert.equal(eventChanged(base, {...base, title: "Updated"}), true);
  assert.equal(eventChanged(base, {...base, status: "cancelled"}), true);
});
