"use strict";

// Persist the intended change in the same transaction as the event revision.
// A delayed worker must never replace it with a later revision's schedule.
function lifecycleSnapshot(event) {
  return {
    eventTitle: event.title || event.eventTitle || "Event",
    eventStart: event.selectedDateTime || event.eventDateTime || null,
    eventDurationMinutes: event.eventDurationMinutes || null,
    eventDuration: event.eventDuration || null,
    eventEnd: event.endAt || event.eventEnd || null,
    eventTimeZone: event.eventTimeZone || "UTC",
    eventRevision: Number(event.eventRevision) || 0,
    eventLocation: event.location || event.eventLocation || "",
  };
}

module.exports = {lifecycleSnapshot};
