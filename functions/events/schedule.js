"use strict";

function instant(value) {
  if (value === null || value === undefined) return null;
  const date = value?.toDate ? value.toDate() : new Date(value);
  return Number.isFinite(date.getTime()) ? date : null;
}

function schedule(event) {
  const start = instant(event.selectedDateTime ?? event.eventStart ?? event.startAt);
  const exact = Number(event.eventDurationMinutes);
  const legacy = Number(event.eventDuration);
  const explicitEnd = instant(event.eventEnd ?? event.endAt);
  const minutes = exact > 0 ? exact : legacy > 0 ? legacy * 60 : null;
  const end = start && exact > 0 ? new Date(start.getTime() + exact * 60000) : explicitEnd && start && explicitEnd > start ? explicitEnd :
    start && minutes ? new Date(start.getTime() + minutes * 60000) : null;
  let timeZone = event.eventTimeZone || "UTC";
  let zoneKnown = Boolean(event.eventTimeZone);
  try { new Intl.DateTimeFormat("en", {timeZone}).format(); } catch (_) {
    timeZone = "UTC"; zoneKnown = false;
  }
  return {start, end, timeZone, quality: !start || !end ? "incomplete" :
    !zoneKnown || !(exact > 0) ? "legacy" : "exact"};
}

function calendarDate(date) {
  return date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

function calendarText(value) {
  return String(value ?? "").replaceAll("\\", "\\\\").replace(/\r?\n/g, "\\n")
      .replaceAll(",", "\\,").replaceAll(";", "\\;");
}

function calendar(event, {uid, url, method = "PUBLISH", now = new Date()} = {}) {
  const value = schedule(event);
  if (!value.start || !value.end) throw new Error("The event schedule needs an exact end time.");
  const lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Attendus//Events//EN",
    `METHOD:${method}`, "BEGIN:VEVENT", `UID:${calendarText(uid)}`,
    `SEQUENCE:${Math.max(0, Number(event.eventRevision) || 0)}`,
    `DTSTAMP:${calendarDate(now)}`, `DTSTART:${calendarDate(value.start)}`,
    `DTEND:${calendarDate(value.end)}`, `SUMMARY:${calendarText(event.title || event.eventTitle)}`,
    `LOCATION:${calendarText(event.location || event.eventLocation)}`,
    `URL:${calendarText(url)}`];
  if (method === "CANCEL") lines.push("STATUS:CANCELLED");
  lines.push("END:VEVENT", "END:VCALENDAR", "");
  // Fold at UTF-8 octet boundaries, without splitting a code point.
  return lines.map((line) => {
    let result = ""; let width = 0;
    for (const character of line) {
      const size = Buffer.byteLength(character);
      if (width + size > 75) { result += "\r\n "; width = 1; }
      result += character; width += size;
    }
    return result;
  }).join("\r\n");
}

module.exports = {instant, schedule, calendar, calendarDate, calendarText};
