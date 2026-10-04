"use strict";

// Prepare private credentials, then seed only after the frozen staging receipt
// and live deployment identity agree. Never accepts a production project.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const {createRequire} = require("node:module");
const {execFileSync} = require("node:child_process");
const fromFunctions = createRequire(path.resolve(__dirname, "../functions/package.json"));
const {validateCandidate, digest} = require("./web_release_contract");
const {captureState, verifyState} = require("./web_release_state");
const {bindingId, emailHash} = require("../functions/communications/qualification-isolation");
const projectId = "attendus-staging";
const roles = ["owner", "attendee", "unauthorized", "staff", "administrator", "deletion"];
const read = (file) => JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
const csvHeaders = ["Name", "Email", "Registration", "Attendance", "Checked in", "Checked out", "Generated at", "Event timezone", "Filters", "Row count", "Registration answers", "Attendance answers", "Snapshot ID", "Snapshot time"];
function validateLiveEnvironment(environment = process.env) {
  const emulatorVariables = ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST", "STORAGE_EMULATOR_HOST", "FIREBASE_DATABASE_EMULATOR_HOST"];
  if (emulatorVariables.some((name) => environment[name])) throw Error("Staging fixture setup cannot use emulator endpoints");
}
function privatePath(file) {
  const target = path.resolve(file), repository = path.resolve(__dirname, "..");
  if (!target.startsWith(path.join(repository, "build") + path.sep)) throw Error("Private fixture context must remain under the ignored build directory");
  execFileSync("git", ["check-ignore", "--quiet", target], {cwd: repository});
  return target;
}
function prepare(file, pointerFile) {
  const target = privatePath(file), now = new Date();
  const runId = `webqa-${now.toISOString().slice(0, 10).replaceAll("-", "")}-${crypto.randomBytes(5).toString("hex")}`;
  const context = {schemaVersion: 1, projectId, runId, controlledRecipientDomain: "example.test", state: "prepared", preparedAt: now.toISOString()};
  context.mapsApiKey = process.env.GOOGLE_MAPS_WEB_API_KEY;
  if (!/^AIza[0-9A-Za-z_-]{35}$/.test(context.mapsApiKey || "")) throw Error("The staging-restricted GOOGLE_MAPS_WEB_API_KEY is required");
  for (const role of roles) context[role] = {uid: `${runId}-${role}`, email: `${runId}-${role}@example.test`, password: crypto.randomBytes(27).toString("base64url") + "aA1!"};
  context.event = {id: `${runId}-pilot`, title: "Controlled web qualification pilot", publicPath: `/event/${runId}-pilot`};
  context.privateEventId = `${runId}-private`; context.secondEventId = `${runId}-second`; context.canaryEventId = `${runId}-analytics`;
  context.largeRoster = {eventId: `${runId}-large`, expectedRows: 1201, expectedCsvHeaders: csvHeaders,
    expectedCsvSpecialNames: ["'=1+1", 'Comma, quote " and\nnewline']};
  context.organizationId = `${runId}-community`; context.conversationId = [context.owner.uid, context.attendee.uid].sort().join("_");
  context.communications = {reminderEventId: `${runId}-reminder`, discoveryEventId: `${runId}-discovery`, pendingPushId: `${runId}-pending`};
  context.ownedFixtureIds = [...roles.map((role) => context[role].uid), context.event.id, context.privateEventId, context.secondEventId,
    context.canaryEventId, context.largeRoster.eventId, context.organizationId, context.conversationId,
    ...Object.values(context.communications)];
  context.recovery = {bundle: read(pointerFile)};
  const source = fs.readFileSync(path.resolve(__dirname, "../lib/firebase_options.dart"), "utf8");
  const staging = /stagingWeb\s*=\s*FirebaseOptions\(([\s\S]*?)\);/.exec(source)?.[1];
  const field = (key) => new RegExp(`${key}:\\s*'([^']+)'`).exec(staging || "")?.[1];
  context.firebase = {projectId, projectNumber: "925344893088", apiKey: field("apiKey"), appId: field("appId"), storageBucket: field("storageBucket"),
    appCheckSiteKey: process.env.ATTENDUS_RECAPTCHA_ENTERPRISE_SITE_KEY};
  if (field("projectId") !== projectId || !context.firebase.apiKey || !context.firebase.appId ||
      !/^[A-Za-z0-9_-]{20,100}$/.test(context.firebase.appCheckSiteKey || "")) throw Error("Staging Firebase source configuration and ATTENDUS_RECAPTCHA_ENTERPRISE_SITE_KEY are required");
  fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, JSON.stringify(context, null, 2) + "\n", {flag: "wx", mode: 0o600});
  return {runId, projectId, state: "prepared", contextPath: target, accounts: roles.length, events: 7, largeRosterRows: 1201};
}
async function apply(file, candidateFile, receiptFile) {
  validateLiveEnvironment();
  const target = privatePath(file), fixture = read(target), candidate = validateCandidate(read(candidateFile), "staging"), receipt = read(receiptFile);
  if (fixture.projectId !== projectId || fixture.state !== "prepared" || process.env.FIRESTORE_EMULATOR_HOST || !/^webqa-[0-9]{8}-[a-f0-9]{10}$/.test(fixture.runId)) throw Error("A fresh prepared staging fixture is required; never overwrite an active run");
  if (receipt.candidateSha256 !== digest(candidate) || receipt.environment !== "staging" || receipt.sourceSha !== candidate.sourceSha) throw Error("Fixture target is not the frozen staging receipt");
  const current = verifyState(candidate, await captureState(projectId), read(path.resolve(__dirname, "../firestore.indexes.json")));
  if (current.stateSha256 !== receipt.stateSha256) throw Error("Staging changed since verified deployment");
  const {initializeApp, applicationDefault, deleteApp} = fromFunctions("firebase-admin/app");
  const {getFirestore} = fromFunctions("firebase-admin/firestore"), {getAuth} = fromFunctions("firebase-admin/auth");
  const app = initializeApp({projectId, storageBucket: fixture.firebase.storageBucket, credential: applicationDefault()}, `fixture-${fixture.runId}`);
  const db = getFirestore(app), auth = getAuth(app), now = new Date();
  try {
    // Enabling public staging pages is safe only for this explicitly empty site.
    // A partial failed setup requires inspection; this command never resets it.
    for (const name of ["Events", "Customers", "RegisterAttendance", "Tickets", "Attendance", "GuestAttendees", "Organizations"])
      if ((await db.collection(name).limit(1).get()).size) throw Error(`Staging collection ${name} is not empty; inspect owned fixture state before proceeding`);
    const eventIds = [fixture.event.id, fixture.privateEventId, fixture.secondEventId, fixture.canaryEventId, fixture.largeRoster.eventId,
      fixture.communications.reminderEventId, fixture.communications.discoveryEventId];
    const accountIds = roles.filter((role) => role !== "deletion").map((role) => fixture[role].uid);
    const start = new Date(now.getTime() - 15 * 60000), end = new Date(start.getTime() + 120 * 60000);
    fixture.runStartsAt = now.toISOString(); fixture.eventClosesAt = end.toISOString();
    fixture.candidateRunId = candidate.candidateRunId; fixture.sourceSha = candidate.sourceSha;
    fixture.state = "seeding";
    fs.writeFileSync(target, JSON.stringify(fixture, null, 2) + "\n", {mode: 0o600});
    const batch = db.batch();
    batch.create(db.doc(`QualificationScopes/${fixture.runId}`), {schemaVersion: 1, projectId, status: "active", mode: "capture", createdAt: now,
      expiresAt: new Date(now.getTime() + 72 * 3600000), actorUids: accountIds, recipientUids: accountIds, eventIds,
      organizationIds: [fixture.organizationId], conversationIds: [fixture.conversationId],
      recipientEmailHashes: [...roles.filter((role) => role !== "deletion").map((role) => emailHash(fixture[role].email)), emailHash(`${fixture.runId}-guest@example.test`)]});
    for (const [kind, ids] of [["account", roles.map((role) => fixture[role].uid)], ["event", eventIds], ["organization", [fixture.organizationId]], ["conversation", [fixture.conversationId]]])
      for (const id of ids) batch.create(db.doc(`QualificationBindings/${bindingId(kind, id)}`), {schemaVersion: 1, projectId, runId: fixture.runId, state: "bound"});
    batch.create(db.doc(`QualificationSetup/${fixture.runId}`), {schemaVersion: 1, projectId, sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId, state: "seeding", createdAt: now, ownedFixtureIds: fixture.ownedFixtureIds});
    await batch.commit();
    for (const role of roles) {
      const account = fixture[role];
      await auth.createUser({...account, displayName: `Controlled ${role}`, emailVerified: true});
      await db.doc(`Customers/${account.uid}`).create({uid: account.uid, name: `Controlled ${role}`, email: account.email,
        username: `qa${fixture.runId.slice(-10)}_${role}`, bio: "Controlled web qualification fixture.", isDiscoverable: true,
        eventsCreated: role === "owner" ? eventIds.length : 0, groupsCreated: role === "owner" ? 1 : 0, createdAt: now});
      await db.doc(`users/${account.uid}`).create({uid: account.uid, displayName: `Controlled ${role}`, email: account.email, createdAt: now});
    }
    await auth.setCustomUserClaims(fixture.administrator.uid, {admin: true});
    await db.doc(`admin_roles/${fixture.administrator.uid}`).create({active: true, roles: ["support"]});
    await db.doc(`Customers/${fixture.owner.uid}/followers/${fixture.attendee.uid}`).create({userId: fixture.attendee.uid, createdAt: now});
    await db.doc(`account_entitlements/${fixture.owner.uid}`).create({unlimitedEventCreation: true, source: "owned_staging_qualification", runId: fixture.runId});
    await db.doc(`Organizations/${fixture.organizationId}`).create({id: fixture.organizationId, name: "Controlled qualification community",
      description: "Synthetic community for isolated web acceptance.", category: "Other", defaultEventVisibility: "public",
      publicPageEnabled: true, createdBy: fixture.owner.uid, createdAt: now});
    for (const role of ["owner", "attendee", "staff"]) await db.doc(`Organizations/${fixture.organizationId}/Members/${fixture[role].uid}`).create({
      userId: fixture[role].uid, role: role === "owner" ? "owner" : "member", status: "approved", joinedAt: now});
    await db.doc(`AppConfig/publicWeb`).set({publicPagesEnabled: true, inlineRegistrationEnabled: true, accountlessRegistrationEnabled: true,
      paidTicketCheckoutEnabled: false, appCheckSiteKey: fixture.firebase.appCheckSiteKey});
    await db.doc(`AppConfig/eventCreation`).set({experienceVersion: 2});
    await db.doc(`AppConfig/attendance`).set({corePasses: {enabled: true, eventIds, userIds: accountIds, identityEnabled: true},
      smartArrival: {enabled: true, eventIds: [fixture.event.id], userIds: accountIds}, appleDelivery: {enabled: false}, googleDelivery: {enabled: false}});
    for (const id of eventIds) {
      const communicationEvent = [fixture.communications.reminderEventId, fixture.communications.discoveryEventId].includes(id);
      const eventStart = communicationEvent ? new Date(now.getTime() + 4 * 3600000) : start;
      await db.doc(`Events/${id}`).create({id, customerUid: fixture.owner.uid, title: id === fixture.event.id ? fixture.event.title : `Controlled ${id.split("-").at(-1)} event`,
        description: "Synthetic event used only for isolated web release qualification.", imageUrl: "", groupName: "Qualification community", organizationId: fixture.organizationId, private: id === fixture.privateEventId,
        isHidden: false, status: "active", selectedDateTime: eventStart, eventDurationMinutes: 120, eventTimeZone: "America/New_York", location: "Controlled test venue",
        locationType: "in_person", eventRevision: 1, checkInStaff: [fixture.staff.uid], ticketsEnabled: false, ticketPrice: 0,
        confirmedRegistrationCount: id === fixture.largeRoster.eventId ? 1201 : 0, issuedTickets: 0, reservedTickets: 0,
        registrationPolicy: {mode: "rsvp", capacity: id === fixture.largeRoster.eventId ? 1500 : 100, waitlistEnabled: true},
        eventReminderPolicy: "24h_1h", checkInPolicy: {version: 2, profile: "staff_entry", openingMode: "manual", eligibility: "registered_only"}, createdAt: now});
    }
    await db.doc(`Events/${fixture.event.id}/EventQuestions/access`).create({id: "access", prompt: "Accessibility needs", timing: "registration", type: "short_text", required: true});
    await db.doc(`Events/${fixture.event.id}/EventQuestions/door`).create({id: "door", questionTitle: "Door access code", type: "short_text", required: true});
    for (let offset = 0; offset < fixture.largeRoster.expectedRows; offset += 400) {
      const rows = db.batch();
      for (let i = offset; i < Math.min(offset + 400, fixture.largeRoster.expectedRows); i++) {
        const id = `${fixture.runId}-row-${String(i).padStart(4, "0")}`;
        rows.create(db.doc(`RegisterAttendance/${id}`), {eventId: fixture.largeRoster.eventId, guestId: `${fixture.runId}-guest-${i}`, identityType: "guest",
          realName: i === 0 ? "=1+1" : i === 1 ? 'Comma, quote " and\nnewline' : `Controlled attendee ${String(i).padStart(4, "0")}`, status: "confirmed", createdAt: now, answers: []});
      }
      await rows.commit();
    }
    // This is a real legacy queue input, never a fabricated delivery result.
    // Deliberately omit device tokens; the deployed capture path must process it.
    await db.doc(`pendingPushNotifications/${fixture.communications.pendingPushId}`).create({senderId: fixture.owner.uid,
      receiverId: fixture.attendee.uid, eventId: fixture.event.id, conversationId: fixture.conversationId,
      title: "Controlled pending canary", body: "Synthetic qualification only", type: "message"});
    fixture.state = "seeded"; fixture.seededAt = new Date().toISOString();
    await db.doc(`QualificationSetup/${fixture.runId}`).update({state: "seeded", completedAt: new Date()});
    fs.writeFileSync(target, JSON.stringify(fixture, null, 2) + "\n", {mode: 0o600});
    return {runId: fixture.runId, projectId, state: "seeded", sourceSha: candidate.sourceSha, eventClosesAt: fixture.eventClosesAt,
      fixtureManifestSha256: digest({...fixture, ...Object.fromEntries(roles.map((role) => [role, {uid: fixture[role].uid}]))})};
  } finally { await db.terminate(); await deleteApp(app); }
}
async function main() {
  const [command, context, first, second] = process.argv.slice(2);
  if (!context || !first || !["prepare", "apply"].includes(command) || command === "apply" && !second) throw Error("Usage: seed_web_qualification.js prepare <private-context> <recovery-pointer> OR apply <private-context> <staging-candidate> <deployment-receipt>");
  console.log(JSON.stringify(command === "prepare" ? prepare(context, first) : await apply(context, first, second)));
}
if (require.main === module) main().catch((error) => {console.error(error.code || error.message); process.exitCode = 1;});
module.exports = {prepare, apply, privatePath, validateLiveEnvironment};
