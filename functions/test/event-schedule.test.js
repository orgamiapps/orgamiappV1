"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {schedule, calendar} = require("../events/schedule");
test("exact minutes win over rounded legacy hours across midnight", () => {
  const event = {selectedDateTime: "2030-01-01T23:30:00Z", eventDurationMinutes: 90,
    eventDuration: 2, eventTimeZone: "America/Chicago"};
  assert.equal(schedule(event).end.toISOString(), "2030-01-02T01:00:00.000Z");
  assert.equal(schedule(event).quality, "exact");
  assert.equal(schedule({...event, selectedDateTime: {toDate: () => new Date(event.selectedDateTime)}})
      .end.getTime(), schedule(event).end.getTime());
});
test("ambiguous legacy schedules are not assigned invented end times", () => {
  assert.equal(schedule({selectedDateTime: "2030-01-01Z"}).end, null);
  assert.equal(schedule({eventTimeZone: "not/a-zone"}).timeZone, "UTC");
});
test("calendar retains UID, revision, exact time and safe folded Unicode", () => {
  const ics = calendar({selectedDateTime: "2030-03-10T07:30:00Z", eventDurationMinutes: 90,
    title: "Gathering, " + "é".repeat(90), eventRevision: 3},
  {uid: "registration-1@attendus.app", method: "CANCEL"});
  assert.match(ics, /UID:registration-1@attendus.app/);
  assert.match(ics, /DTEND:20300310T090000Z/);
  assert.match(ics, /SEQUENCE:3/);
  assert.match(ics, /STATUS:CANCELLED/);
  for (const line of ics.split("\r\n")) assert.ok(Buffer.byteLength(line) <= 75);
});
