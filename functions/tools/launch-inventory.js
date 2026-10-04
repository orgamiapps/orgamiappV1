"use strict";
// Read-only inventory. Never writes schedules, contacts, counters or archives.
const {schedule} = require("../events/schedule");
const {buildRoster, metrics, allDocuments} = require("../events/roster");
const {contactExposure} = require("../events/public-contact-privacy");
async function main() {
  const project = process.argv.find((value) => value.startsWith("--project="))?.slice(10);
  if (!project) throw Error("An explicit --project=<Firebase project ID> is required.");
  process.env.GCLOUD_PROJECT = project;
  const admin = require("../firebase-admin-compat");
  const db = admin.firestore();
  const events = await allDocuments(db.collection("Events"));
  const output = {project, generatedAt: new Date().toISOString(), readOnly: true, events: [],
    publicContactPrivacy: {publicEventsWithHiddenContact: 0, hiddenContactFields: 0}};
  for (const event of events) {
    const documents = await Promise.all(["RegisterAttendance", "Tickets", "Attendance", "HistoricalAttendance"].map((collection) =>
      allDocuments(db.collection(collection).where("eventId", "==", event.id))));
    const rows = buildRoster(...documents.map((list) => list.map((doc) => ({id: doc.id, ...doc.data()}))));
    const privacy = contactExposure(event.id, event.data());
    if (privacy.publiclyReadable && privacy.hiddenContactFieldCount > 0) {
      output.publicContactPrivacy.publicEventsWithHiddenContact++;
      output.publicContactPrivacy.hiddenContactFields += privacy.hiddenContactFieldCount;
    }
    output.events.push({eventId: event.id, revision: event.get("eventRevision") || 0, contactPrivacy: privacy,
      scheduleQuality: schedule(event.data()).quality,
      registrationRecords: documents[0].length, ticketRecords: documents[1].length,
      attendanceRecords: documents[2].length, archivedRecords: documents[3].length,
      storedConfirmed: event.get("confirmedRegistrationCount") ?? null,
      projected: metrics(rows, event.data())});
  }
  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
  await db.terminate();
}
main().catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
