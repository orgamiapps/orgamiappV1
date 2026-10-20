"use strict";

// Real staging UI + real Firebase only. This supplemental report is not one of
// the canonical release gates and cannot replace hourly or physical-device QA.
const fs = require("node:fs"), path = require("node:path");
const {createRequire} = require("node:module");
const {spawnSync} = require("node:child_process");
const c = require("./event_removal_contract");
const READ_CALLS = new Set(["getEventCapabilitiesV1", "getDiscoveryHomeV2", "getDiscoveryHomeV3",
  "searchDiscoveryEventsV2", "searchDiscoveryEventsV3", "getPublicProfilesV1", "searchPublicProfilesV1",
  "listMyAdmissionsV1", "getSmartArrivalCandidates", "getPublicRegistrationStatusV2"]);
const MUTATIONS = new Set(["previewEventCancellationV1", "deleteEmptyEventV1", "cancelEventV1", "startPublicRegistrationV3"]);
const REPLAYABLE = new Set(["deleteEmptyEventV1", "cancelEventV1", "startPublicRegistrationV3"]);
function readOnlyDataRequest(value, method) {
  const url = new URL(value);
  if (url.hostname === "firestore.googleapis.com") {
    const database = "projects/attendus-staging/databases/(default)";
    const pathname = decodeURIComponent(url.pathname);
    if (pathname === "/google.firestore.v1.Firestore/Listen/channel") {
      return ["GET", "POST"].includes(method) && url.searchParams.get("database") === database;
    }
    if (!pathname.startsWith(`/v1/${database}/documents`)) return false;
    if (method === "GET") return !pathname.includes(":");
    return method === "POST" && /:(?:batchGet|runQuery|runAggregationQuery)$/.test(pathname);
  }
  if (url.hostname === "firebasestorage.googleapis.com" || url.origin === c.ORIGIN) {
    return ["GET", "HEAD"].includes(method);
  }
  return true;
}
function jwtUid(token) {
  try {const data = JSON.parse(Buffer.from(token.split(".")[1], "base64url")); return data.user_id || data.sub;}
  catch (_) {return null;}
}
function createMutationGuard({fixture, journal}) {
  let armed = null;
  const operations = new Map();
  const summaries = [];
  return {
    summaries,
    arm(name, key, role = "owner") {
      c.need(MUTATIONS.has(name) && c.EVENT_KEYS.includes(key) && c.ROLE_KEYS.includes(role), "ACTION_SCOPE_INVALID");
      c.need(role === (name === "startPublicRegistrationV3" ? "viewer" : "owner"), "ACTION_ROLE_INVALID");
      armed = {name, key, role};
    },
    disarm() {armed = null;},
    begin({name, data, authorization, appCheckToken}) {
      c.need(armed && name === armed.name && data?.eventId === fixture.events[armed.key].id, "UNARMED_OR_FOREIGN_MUTATION");
      const actorUid = fixture.roles[armed.role].uid;
      c.need(authorization?.startsWith("Bearer ") && jwtUid(authorization.slice(7)) === actorUid && appCheckToken, "BOUND_BROWSER_CREDENTIALS_REQUIRED");
      const keys = {
        previewEventCancellationV1: ["eventId", "recurrenceScope"],
        deleteEmptyEventV1: ["eventId", "requestId", "expectedEventRevision"],
        cancelEventV1: ["eventId", "requestId", "expectedEventRevision", "previewToken", "reason"],
        startPublicRegistrationV3: ["eventId", "idempotencyKey", "fullName", "email", "answers"],
      }[name];
      c.need(Object.keys(data).every(key => keys.includes(key)), "UNREVIEWED_MUTATION_FIELDS");
      if (name === "previewEventCancellationV1") c.need(data.recurrenceScope === "this_occurrence", "RECURRENCE_SCOPE_FORBIDDEN");
      if (["deleteEmptyEventV1", "cancelEventV1"].includes(name)) c.need(/^[A-Za-z0-9._:-]{8,128}$/.test(data.requestId || "") &&
        Number.isSafeInteger(data.expectedEventRevision) && data.expectedEventRevision >= 0, "REMOVAL_IDENTITY_REQUIRED");
      if (name === "cancelEventV1") c.need(typeof data.previewToken === "string" && data.previewToken &&
        data.reason === "Controlled removal qualification", "CANCELLATION_IDENTITY_REQUIRED");
      if (name === "startPublicRegistrationV3") c.need(armed.key === "race" &&
        data.idempotencyKey === `${fixture.runId}:race-registration` &&
        data.email === fixture.roles.viewer.email, "REGISTRATION_IDENTITY_REQUIRED");
      const requestSha256 = c.digest({name, data, actorUid});
      const key = `${name}:${data.eventId}`;
      const previous = operations.get(key);
      if (previous) {
        c.need(previous.requestSha256 === requestSha256 && REPLAYABLE.has(name), "REQUEST_REUSE_NOT_IDEMPOTENT");
        c.need(previous.attempts < 3, "MUTATION_ATTEMPT_LIMIT");
        previous.attempts++;
        journal("same-request-retry", {name, eventKey: armed.key, requestSha256, attempt: previous.attempts});
        return previous;
      }
      const operation = {name, eventKey: armed.key, requestSha256, attempts: 1, outcomes: [], reconciled: false};
      // Full operation data stays in the private journal for uncertain outcomes.
      journal("mutation-intent", {name, eventKey: armed.key, actorUid, requestSha256, data, automaticRestart: false});
      operations.set(key, operation); summaries.push(operation);
      return operation;
    },
    outcome(operation, result) {
      if (!result?.error && ["deleteEmptyEventV1", "cancelEventV1"].includes(operation.name)) {
        const data = result.result || result.data;
        c.need(data?.status === (operation.name === "deleteEmptyEventV1" ? "deleted" : "cancelled") &&
          c.digest(data.affectedEventIds) === c.digest([fixture.events[operation.eventKey].id]), "LIFECYCLE_RESPONSE_SCOPE_INVALID");
      }
      const status = result?.error?.status || result?.result?.status || result?.data?.status || "ACKNOWLEDGED";
      const safe = /^[A-Za-z_-]{1,60}$/.test(status) ? status : "UNRECOGNIZED";
      operation.outcomes.push(safe);
      journal("mutation-response", {name: operation.name, eventKey: operation.eventKey,
        requestSha256: operation.requestSha256, status: safe});
    },
    unknown(operation) {
      operation.outcomes.push("UNKNOWN");
      journal("mutation-unknown", {name: operation.name, eventKey: operation.eventKey,
        requestSha256: operation.requestSha256, automaticRestart: false});
    },
    reconcile(snapshot) {
      for (const operation of summaries) {
        const event = snapshot.events?.[operation.eventKey];
        if (operation.name === "deleteEmptyEventV1") {
          operation.reconciled = !!event && (!event.exists ||
            operation.outcomes.some(status => ["FAILED_PRECONDITION", "ABORTED"].includes(status)) && event.exists);
        } else if (operation.name === "cancelEventV1") operation.reconciled = event?.exists && event.status === "cancelled";
        else if (operation.name === "startPublicRegistrationV3") operation.reconciled = event?.registrations > 0;
        else operation.reconciled = !operation.outcomes.includes("UNKNOWN");
      }
      return summaries.every(operation => operation.reconciled);
    },
  };
}
function assertCurated(value, fixture) {
  const bytes = typeof value === "string" ? value : JSON.stringify(value);
  for (const actor of Object.values(fixture.roles)) {
    c.need(!bytes.includes(actor.password) && !bytes.includes(actor.email) && !bytes.includes(actor.uid), "PRIVATE_DATA_IN_REPORT");
  }
  c.need(!/(?:Bearer\s+[A-Za-z0-9._-]+|refreshToken|idToken|passwordHash|X-Firebase-AppCheck":)/i.test(bytes), "CREDENTIAL_IN_REPORT");
}
async function waitForSnapshot(observe, predicate, timeoutMs = 90000) {
  const end = Date.now() + timeoutMs;
  do {
    const snapshot = await observe();
    c.need(snapshot.canonical?.unchanged === true, "CANONICAL_PILOT_CHANGED");
    c.need(snapshot.scope?.active === true && snapshot.scope.boundCount === 10, "QUALIFICATION_SCOPE_CHANGED");
    if (predicate(snapshot)) return snapshot;
    await new Promise(resolve => setTimeout(resolve, 1000));
  } while (Date.now() < end);
  c.need(false, "SERVER_RECONCILIATION_TIMEOUT");
}
async function run({repo, candidate, receipt, fixture, directory}) {
  c.validateContext({repo, candidate, receipt, fixture});
  c.need(fixture.state === "seeded", "SEEDED_FIXTURE_REQUIRED");
  c.assertLiveEnvironment(); c.sourceCheck(repo, candidate);
  const contracts = require(path.join(repo, "tools/web_release_contract"));
  contracts.validateCandidate(candidate, "staging");
  const {captureState, verifyState} = require(path.join(repo, "tools/web_release_state"));
  const verifyDeployment = async () => {
    const state = verifyState(candidate, await captureState(c.PROJECT),
      JSON.parse(fs.readFileSync(path.join(repo, "firestore.indexes.json"))));
    c.need(state.stateSha256 === receipt.stateSha256, "STAGING_DEPLOYMENT_CHANGED");
  };
  await verifyDeployment();
  const output = c.privateDirectory(repo, directory);
  const attemptRoot = path.join(repo, "build", "event-removal-live-attempts");
  fs.mkdirSync(attemptRoot, {recursive: true, mode: 0o700});
  try {fs.mkdirSync(path.join(attemptRoot, fixture.runId), {mode: 0o700});}
  catch (_) {c.need(false, "FIXTURE_ALREADY_ATTEMPTED_RECONCILE_FIRST");}
  c.save(path.join(attemptRoot, fixture.runId, "intent-private.json"),
    {fixtureSha256: c.digest(fixture), candidateSha256: c.digest(candidate), output, automaticRestart: false});
  const journal = c.createJournal(path.join(output, "private-journal"));
  journal("started", {candidateSha256: c.digest(candidate), fixtureSha256: c.digest(fixture), restartAllowed: false});
  const browserRequire = createRequire(path.join(repo, "tests/browser/package.json"));
  const serverRequire = createRequire(path.join(repo, "functions/package.json"));
  const {chromium, expect} = browserRequire("@playwright/test");
  const {activateFlutterSemanticsPage, enterFlutterText} = require(path.join(repo, "tools/web_release_producers/flutter-semantics"));
  const {readFirebaseAuthStatePage} = require(path.join(repo, "tools/web_release_producers/firebase-auth-state"));
  const {pageCallable} = require(path.join(repo, "tools/web_release_producers/browser-replay"));
  const {allowStagingRequest} = require(path.join(repo, "tools/web_release_producers/browser"))._test;
  const {initializeApp, applicationDefault, deleteApp} = serverRequire("firebase-admin/app");
  const {getFirestore} = serverRequire("firebase-admin/firestore");
  const app = initializeApp({projectId: c.PROJECT, credential: applicationDefault()}, `removal-${fixture.runId}`);
  const db = getFirestore(app);
  const observe = require("./event_removal_observer").createObserver({db, fixture, candidate, receipt});
  const guard = createMutationGuard({fixture, journal});
  const report = {schemaVersion: 1, evidenceKind: "supplemental-live-event-removal", sourceSha: candidate.sourceSha,
    candidateRunId: candidate.candidateRunId, candidateSha256: c.digest(candidate), deploymentStateSha256: receipt.stateSha256,
    fixtureRunId: fixture.runId, fixtureSha256: c.digest(fixture), helperSha256: c.sha(fs.readFileSync(__filename)),
    origin: c.ORIGIN, startedAt: new Date().toISOString(), appCheckMode: "real-enterprise-provider",
    physicalIphoneQualified: false, canonicalReleaseGate: false, serviceWorkers: "blocked-for-request-receipt-observation",
    optionalFunnelTelemetry: "blocked", cases: [], captures: [], blockers: []};
  const curated = path.join(output, "curated"); fs.mkdirSync(curated);
  const browser = await chromium.launch({headless: true});
  let failed = null, dropCommittedDelete = true, dropEligibility = false, currentPage = null;
  const pages = [], contexts = [], pending = new Set(), safetyFailures = [];
  const appCheckTokens = new Map(), appCheckExchanges = new Map(), anonymousIdentities = [], navigations = new WeakMap(),
    authCreationLatches = new WeakMap(), verifiedContexts = new WeakSet(), verifiedMainScripts = new WeakMap();
  const eventKey = event => c.EVENT_KEYS.find(key => fixture.events[key].id === event.id);
  const capture = async (page, name) => {
    c.need(/^[a-z0-9-]+$/.test(name), "CAPTURE_NAME_INVALID");
    // Captures happen only after login. No traces, DOM dumps, or raw logs.
    const bytes = await page.screenshot({fullPage: false});
    fs.writeFileSync(path.join(curated, `${name}.png`), bytes, {flag: "wx"});
    report.captures.push({file: `${name}.png`, sha256: c.sha(bytes)});
  };
  const record = (name, actual = true) => {c.need(actual === true, "UI_ASSERTION_FAILED"); report.cases.push({name, passed: true});};
  const appUrl = event => `${c.ORIGIN}/app/event/${encodeURIComponent(event.id)}`;
  const nodes = (page, event) => page.getByText(event.title, {exact: true})
    .or(page.getByRole("button", {name: new RegExp(event.title)}))
    .or(page.getByRole("group", {name: new RegExp(event.title)}));
  const card = (page, event) => page.getByRole("button", {name: new RegExp(event.title)})
    .or(page.getByText(event.title, {exact: true})).first();
  async function routes(context, role) {
    const authCreationLatch = {remaining: 1, unknown: false};
    authCreationLatches.set(context, authCreationLatch);
    context.on("response", response => {
      const url = new URL(response.url());
      if (url.origin === c.ORIGIN && url.pathname.endsWith("/main.dart.js")) {
        const verification = (async () => {
          const page = response.request().frame().page();
          const expectedPath = `/releases/${candidate.releaseId}/main.dart.js`;
          c.need(url.pathname === expectedPath && response.status() === 200 &&
            c.sha(await response.body()) === candidate.webFiles[expectedPath.slice(1)], "BROWSER_RUNTIME_BYTES_DIFFER");
          verifiedMainScripts.set(page, true);
        })().catch(() => safetyFailures.push("BROWSER_RUNTIME_BYTES_DIFFER"));
        pending.add(verification); void verification.finally(() => pending.delete(verification));
      }
      if (["firebaseappcheck.googleapis.com", "content-firebaseappcheck.googleapis.com"].includes(url.hostname) &&
        url.pathname.endsWith(":exchangeRecaptchaEnterpriseToken") && response.status() === 200) {
        appCheckExchanges.set(role, true);
      }
    });
    const handle = async route => {
      const request = route.request(), url = new URL(request.url()), headers = await request.allHeaders();
      const policy = {baseUrl: c.ORIGIN, projectId: c.PROJECT, fixture};
      const stop = code => {safetyFailures.push(code); return route.abort("blockedbyclient");};
      if (!allowStagingRequest(request.url(), request.method(), policy, headers)) return stop("OUT_OF_SCOPE_NETWORK");
      if (!readOnlyDataRequest(request.url(), request.method())) return stop("UNREVIEWED_DIRECT_DATA_MUTATION");
      if (headers["x-firebase-appcheck"]) appCheckTokens.set(role, headers["x-firebase-appcheck"]);
      if (url.hostname === "identitytoolkit.googleapis.com" && /accounts:(signUp|update|delete|sendOobCode)$/.test(url.pathname)) {
        // Fresh guest startup can create an anonymous identity before email login.
        // It is recorded privately and never automatically deleted or recreated.
        let data;
        try {data = request.postDataJSON();} catch (_) {return stop("AUTH_REQUEST_INVALID");}
        if (!url.pathname.endsWith(":signUp") || data.email || data.password) return stop("UNREVIEWED_AUTH_MUTATION");
        if (authCreationLatch.unknown || authCreationLatch.remaining < 1) return stop("ANONYMOUS_CREATE_RETRY_REQUIRES_RECONCILIATION");
        authCreationLatch.remaining--;
        journal("anonymous-create-intent", {role, requestSha256: c.digest(data), automaticRetry: false});
        try {
          const response = await route.fetch({maxRetries: 0, timeout: 60000}), result = await response.json();
          if (response.ok() && result.localId) {
            anonymousIdentities.push({role, uid: result.localId, observedAt: new Date().toISOString()});
            journal("anonymous-created", anonymousIdentities.at(-1));
          }
          else journal("anonymous-create-rejected", {role, status: response.status()});
          return route.fulfill({response});
        } catch (_) {
          authCreationLatch.unknown = true;
          journal("anonymous-create-unknown", {role, automaticRetry: false}); return stop("AUTH_CREATE_OUTCOME_UNKNOWN");
        }
      }
      if (url.hostname === "us-central1-attendus-staging.cloudfunctions.net") {
        const name = url.pathname.slice(1);
        if (request.method() === "OPTIONS") return route.continue();
        let data; try {data = request.postDataJSON()?.data;} catch (_) {return stop("CALLABLE_REQUEST_INVALID");}
        if (READ_CALLS.has(name)) {
          if (name === "getEventCapabilitiesV1" && dropEligibility && data?.includeRemovalEligibility === true) {
            dropEligibility = false; journal("eligibility-network-fault", {eventId: data.eventId}); return route.abort("connectionfailed");
          }
          return route.continue();
        }
        // Optional analytics is intentionally blocked; no aggregate mutations are
        // needed to verify removal. All business mutations require an armed UI.
        if (name === "recordProductFunnelEvent") return route.abort("blockedbyclient");
        if (!MUTATIONS.has(name)) return stop("UNREVIEWED_CALLABLE_MUTATION");
        let operation;
        try {operation = guard.begin({name, data, authorization: headers.authorization, appCheckToken: headers["x-firebase-appcheck"]});}
        catch (_) {return stop("MUTATION_GUARD_REJECTED");}
        try {
          const response = await route.fetch({maxRetries: 0, timeout: 120000});
          const result = await response.json(); guard.outcome(operation, result);
          if (dropCommittedDelete && name === "deleteEmptyEventV1" && data.eventId === fixture.events.publicDelete.id &&
            (result.result || result.data)?.status === "deleted") {
            dropCommittedDelete = false;
            journal("committed-response-dropped", {requestSha256: operation.requestSha256});
            return route.abort("connectionfailed");
          }
          return route.fulfill({response});
        } catch (_) {guard.unknown(operation); return route.abort("connectionfailed");}
      }
      return route.continue();
    };
    await context.route("**/*", route => {
      const task = handle(route); pending.add(task);
      void task.finally(() => pending.delete(task)).catch(() => {});
      return task;
    });
    await context.routeWebSocket("**/*", socket => {safetyFailures.push("UNREVIEWED_WEBSOCKET"); socket.close();});
  }
  async function newPage(context) {
    const page = await context.newPage(); page.setDefaultTimeout(45000); pages.push(page);
    navigations.set(page, 0);
    page.on("framenavigated", frame => {if (frame === page.mainFrame()) navigations.set(page, navigations.get(page) + 1);});
    page.on("pageerror", () => safetyFailures.push("BROWSER_PAGE_ERROR"));
    return page;
  }
  async function open(page, url = `${c.ORIGIN}/app/discover`) {
    currentPage = page;
    c.need(new URL(url).origin === c.ORIGIN, "NAVIGATION_SCOPE_INVALID");
    verifiedMainScripts.delete(page);
    await page.goto(url, {waitUntil: "domcontentloaded"}); await activateFlutterSemanticsPage(page);
    c.need(await page.evaluate(() => globalThis.attendusReleaseId) === candidate.releaseId, "BROWSER_RELEASE_ID_DIFFERS");
    await expect.poll(() => verifiedMainScripts.get(page), {timeout: 60000}).toBe(true);
  }
  async function click(page, text) {
    currentPage = page;
    const target = page.getByText(text, {exact: true}).last(); await target.scrollIntoViewIfNeeded(); await target.click();
  }
  async function currentUser(page, role) {
    return readFirebaseAuthStatePage(page, {apiKey: fixture.firebase.apiKey, projectId: c.PROJECT,
      appName: "[DEFAULT]", expectedUid: fixture.roles[role].uid, timeoutMs: 15000});
  }
  async function login(role, viewport) {
    const context = await browser.newContext({viewport, serviceWorkers: "block"});
    contexts.push(context); await routes(context, role); const page = await newPage(context);
    await loginOnPage(page, role);
    return {context, page};
  }
  async function loginOnPage(page, role) {
    report.phase = `login-${role}`;
    await open(page); await click(page, "Log in");
    if (!await page.getByText("Welcome back", {exact: true}).isVisible()) await click(page, "Log in");
    await enterFlutterText(page, "Email address", fixture.roles[role].email);
    await enterFlutterText(page, "Password", fixture.roles[role].password);
    await click(page, "Log in"); await page.getByText("Welcome back", {exact: true}).waitFor({state: "hidden", timeout: 90000});
    await currentUser(page, role);
    verifiedContexts.add(page.context());
  }
  async function profile(page, tab) {
    report.phase = `profile-${tab.toLowerCase().replace(/[^a-z]+/g, "-")}`;
    await open(page); await click(page, "Profile");
    if (tab === "Created" || tab === "Organizer workspace") await click(page, "Organizer workspace");
    else if (tab === "Saved") await click(page, "Saved events");
    else if (tab === "Attended") {
      const target = page.getByText(/^Attended \(\d+\)$/).last();
      await target.scrollIntoViewIfNeeded(); await target.click();
    } else await click(page, tab);
  }
  async function documentIdentity(page) {
    return {...await page.evaluate(() => ({timeOrigin: performance.timeOrigin, url: location.href})), navigations: navigations.get(page)};
  }
  async function searchValue(page) {
    await page.getByRole("textbox", {name: "Search events, organizers, or venues", exact: true}).click();
    const value = await page.evaluate(() => {
      const field = document.activeElement;
      return field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement ? field.value : null;
    });
    c.need(typeof value === "string", "SEARCH_FIELD_NOT_READABLE");
    return value;
  }
  async function healthySaved(page) {
    await expect(page.getByText(/^Saved \(\d+\)$/).last()).toBeAttached();
    await expect(nodes(page, fixture.events.restricted).first()).toBeAttached();
    await expect(page.getByText("Cancelled events", {exact: true})).toHaveCount(0);
    await expect(page.getByText("Try again", {exact: true})).toHaveCount(0);
  }
  async function healthyDiscover(page, event) {
    await expect(page.getByText("Discover", {exact: true}).first()).toBeAttached();
    await expect(page.getByText("Try again", {exact: true})).toHaveCount(0);
    c.need(await searchValue(page) === event.title, "DISCOVER_QUERY_NOT_RETAINED");
  }
  async function discover(page, event) {
    report.phase = `discover-${eventKey(event)}`;
    await open(page);
    await enterFlutterText(page, "Search events, organizers, or venues", event.title);
    await expect(card(page, event)).toBeAttached({timeout: 90000});
  }
  async function removalControls(page, event, current = false) {
    report.phase = `open-removal-${eventKey(event)}`; currentPage = page;
    if (!current) await card(page, event).click();
    await page.getByRole("button", {name: "Manage event", exact: true}).click();
    await click(page, "Delete or cancel event");
  }
  async function previewCancel(page, key) {
    report.phase = `preview-${key}`;
    await expect(page.getByRole("button", {name: "Delete event", exact: true})).toHaveCount(0);
    await enterFlutterText(page, "Reason shared with attendees", "Controlled removal qualification");
    guard.arm("previewEventCancellationV1", key);
    await page.getByRole("button", {name: "Review affected attendees", exact: true}).click();
    await expect(page.getByRole("button", {name: "Cancel event", exact: true})).toBeEnabled({timeout: 60000});
  }
  async function cancelledHistory(owner, viewer) {
    await profile(owner, "Organizer workspace");
    const toggle = owner.getByRole("switch", {name: /Cancelled events/});
    await toggle.click();
    for (const key of ["publicCancel", "privateCancel"]) await expect(nodes(owner, fixture.events[key]).first()).toBeAttached();
    await capture(owner, "organizer-cancelled-history");
    await profile(viewer, "Attended");
    for (const key of ["publicCancel", "privateCancel"]) await expect(nodes(viewer, fixture.events[key]).first()).toBeAttached();
    await capture(viewer, "attendee-history-retained");
    await profile(viewer, "Registrations and tickets");
    for (const key of ["publicCancel", "privateCancel"]) await expect(viewer.getByText(fixture.events[key].title, {exact: true})).toBeAttached();
    await expect(viewer.getByText(/Cancelled event · /).first()).toBeAttached();
    await capture(viewer, "cancelled-registrations-and-tickets");
    record("cancelled organizer, registration, ticket and attendance history remains available");
  }
  try {
    const manifest = await fetch(`${c.ORIGIN}/release-manifest.json`, {redirect: "error", signal: AbortSignal.timeout(30000)});
    c.need(manifest.ok && c.sha(Buffer.from(await manifest.arrayBuffer())) === candidate.webFiles["release-manifest.json"], "HOSTED_CANDIDATE_BYTES_DIFFER");
    const before = await observe();
    c.need(before.canonical?.unchanged === true && before.scope?.active === true && before.scope.boundCount === 10 &&
      c.EVENT_KEYS.every(key => before.events[key]?.exists && before.events[key]?.status === "active" &&
        before.events[key]?.historyPreserved), "FIXTURE_PREFLIGHT_FAILED");
    c.save(path.join(output, "initial-private.json"), before);
    const owner = await login("owner", {width: 1440, height: 1000});
    const viewer = await login("viewer", {width: 390, height: 844});
    const saved = await newPage(viewer.context), detail = await newPage(viewer.context), discoverPage = await newPage(viewer.context);
    for (const key of ["publicDelete", "privateDelete", "publicCancel", "privateCancel"]) {
      report.phase = key;
      const event = fixture.events[key], cancelled = key.endsWith("Cancel");
      if (event.private) await profile(owner.page, "Created"); else await discover(owner.page, event);
      await expect(card(owner.page, event)).toBeAttached();
      await profile(saved, "Saved");
      await expect(nodes(saved, event).first()).toBeAttached();
      await healthySaved(saved);
      await open(detail, appUrl(event)); await expect(detail.getByText(event.title, {exact: true}).first()).toBeAttached();
      if (!event.private) await discover(discoverPage, event);
      const savedIdentity = await documentIdentity(saved), detailIdentity = await documentIdentity(detail);
      const discoverIdentity = event.private ? null : await documentIdentity(discoverPage);
      const originalUrl = owner.page.url();
      await removalControls(owner.page, event);
      if (cancelled) await previewCancel(owner.page, key);
      else await expect(owner.page.getByRole("button", {name: "Delete event", exact: true})).toBeEnabled();
      await capture(owner.page, `${key.toLowerCase()}-confirmation`);
      report.phase = `submit-${key}`;
      guard.arm(cancelled ? "cancelEventV1" : "deleteEmptyEventV1", key);
      await owner.page.getByRole("button", {name: cancelled ? "Cancel event" : "Delete event", exact: true}).click();
      await expect(owner.page.getByText(cancelled ? "Event cancelled" : "Event deleted", {exact: true}).last())
        .toBeVisible({timeout: 90000});
      report.phase = `observe-${key}`;
      await expect(nodes(owner.page, event)).toHaveCount(0);
      c.need(owner.page.url() === originalUrl, "ORIGIN_ROUTE_NOT_RESTORED");
      if (event.private) {
        await expect(owner.page.getByText("Cancelled events", {exact: true})).toBeAttached();
        await expect(nodes(owner.page, fixture.events.restricted).first()).toBeAttached();
      } else await healthyDiscover(owner.page, event);
      await expect(nodes(saved, event)).toHaveCount(0, {timeout: 60000});
      await healthySaved(saved);
      c.need(c.digest(await documentIdentity(saved)) === c.digest(savedIdentity), "SAVED_LIST_REMOUNTED");
      if (!event.private) await expect(nodes(discoverPage, event)).toHaveCount(0, {timeout: 60000});
      if (!event.private) {
        await healthyDiscover(discoverPage, event);
        c.need(c.digest(await documentIdentity(discoverPage)) === c.digest(discoverIdentity), "DISCOVER_LIST_REMOUNTED");
      }
      if (cancelled) {
        await expect(detail.getByText("Event canceled", {exact: true})).toBeAttached({timeout: 60000});
        await expect(detail.getByText(event.title, {exact: true}).first()).toBeAttached();
      } else {
        await expect(detail.getByText("Event unavailable", {exact: true})).toBeAttached({timeout: 60000});
        await expect(detail.getByText("This event requires access", {exact: true})).toHaveCount(0);
        c.need(c.digest(await documentIdentity(detail)) === c.digest(detailIdentity), "VIEWER_DETAIL_REMOUNTED");
        await detail.goBack(); await detail.goForward(); await activateFlutterSemanticsPage(detail);
        await expect(detail.getByText("Event unavailable", {exact: true})).toBeAttached();
      }
      if (cancelled) c.need(c.digest(await documentIdentity(detail)) === c.digest(detailIdentity), "VIEWER_DETAIL_REMOUNTED");
      await capture(owner.page, `${key.toLowerCase()}-origin-list`);
      await capture(saved, `${key.toLowerCase()}-viewer-saved`);
      await capture(detail, `${key.toLowerCase()}-viewer-detail`);
      const after = await waitForSnapshot(observe, snapshot => cancelled ?
        snapshot.events[key]?.status === "cancelled" && snapshot.events[key]?.historyPreserved === true &&
          snapshot.events[key]?.projectionExists === false :
        snapshot.events[key]?.exists === false && snapshot.events[key]?.projectionExists === false);
      journal("event-server-confirmed", {key, stateSha256: c.digest(after.events[key])});
      record(`${key}: creator origin restored; second session list/detail reconciled without refresh`);
      guard.disarm(); c.need(safetyFailures.length === 0, "SAFETY_OR_BROWSER_FAILURE");
    }
    const lost = guard.summaries.find(operation => operation.eventKey === "publicDelete");
    record("lost committed response reuses the same deletion request", lost?.attempts === 2 &&
      lost.outcomes.every(status => status === "deleted"));
    report.phase = "history";
    await cancelledHistory(owner.page, viewer.page);
    // A genuine private access restriction remains distinguishable from absence.
    report.phase = "restricted";
    const outsider = await login("outsider", {width: 390, height: 844});
    await open(outsider.page, appUrl(fixture.events.restricted));
    await expect(outsider.page.getByText("This event requires access", {exact: true})).toBeAttached();
    await expect(outsider.page.getByText("Event unavailable", {exact: true})).toHaveCount(0);
    await capture(outsider.page, "private-access-restriction");
    record("existing restricted private link keeps the access flow");
    // Drop only the eligibility read. No fabricated successful Firebase reply.
    report.phase = "eligibility-retry";
    await open(owner.page, appUrl(fixture.events.restricted));
    dropEligibility = true;
    await removalControls(owner.page, fixture.events.restricted, true);
    await expect(owner.page.getByRole("button", {name: "Try again", exact: true})).toBeEnabled();
    await expect(owner.page.getByText(/Could not connect/)).toBeAttached();
    await capture(owner.page, "connection-error-retry");
    await owner.page.getByRole("button", {name: "Try again", exact: true}).click();
    await expect(owner.page.getByRole("button", {name: "Delete event", exact: true})).toBeEnabled();
    await click(owner.page, "Keep event"); record("eligibility connection error stays open and retries");
    // Registration is an actual authenticated browser callable. Only the
    // viewer's owned race event may be mutated outside the creator UI.
    report.phase = "registration-race";
    await open(owner.page, appUrl(fixture.events.race));
    await removalControls(owner.page, fixture.events.race, true);
    await expect(owner.page.getByRole("button", {name: "Delete event", exact: true})).toBeEnabled();
    const viewerUser = await currentUser(viewer.page, "viewer");
    guard.arm("startPublicRegistrationV3", "race", "viewer");
    const raceRegistration = await pageCallable(viewer.page, {name: "startPublicRegistrationV3",
      data: {eventId: fixture.events.race.id, idempotencyKey: `${fixture.runId}:race-registration`,
        fullName: "Controlled removal viewer", email: fixture.roles.viewer.email, answers: {}},
      token: viewerUser.token, appCheckToken: appCheckTokens.get("viewer"), actorUid: fixture.roles.viewer.uid});
    c.need(raceRegistration.status === "OK" && raceRegistration.result.status === "confirmed", "RACE_REGISTRATION_NOT_CONFIRMED");
    await waitForSnapshot(observe, snapshot => snapshot.events.race.registrations > 0);
    guard.arm("deleteEmptyEventV1", "race");
    await owner.page.getByRole("button", {name: "Delete event", exact: true}).click();
    await expect(owner.page.getByText("The event changed. Review its current details before continuing.", {exact: true})).toBeAttached();
    await expect(owner.page.getByRole("button", {name: "Review affected attendees", exact: true})).toBeEnabled();
    await expect(owner.page.getByRole("button", {name: "Delete event", exact: true})).toHaveCount(0);
    await capture(owner.page, "new-registration-prevents-deletion");
    await click(owner.page, "Keep event");
    report.phase = "account-switch";
    await open(detail, appUrl(fixture.events.restricted));
    await expect(detail.getByText(fixture.events.restricted.title, {exact: true}).first()).toBeAttached();
    c.need(!authCreationLatches.get(viewer.context).unknown, "AUTH_CREATE_OUTCOME_UNKNOWN");
    authCreationLatches.get(viewer.context).remaining = 1;
    journal("explicit-signout-guest-budget", {role: "viewer", permittedNewAnonymousAccounts: 1, automaticRetry: false});
    await profile(viewer.page, "Settings"); await click(viewer.page, "Sign out");
    await viewer.page.getByText("Log in", {exact: true}).first().waitFor({timeout: 60000});
    await loginOnPage(viewer.page, "outsider");
    await expect(detail.getByText("This event requires access", {exact: true})).toBeAttached({timeout: 60000});
    await expect(nodes(detail, fixture.events.restricted)).toHaveCount(0);
    await capture(detail, "account-switch-hides-private-detail");
    record("account switch removes previous viewer's private detail in another open tab");
    report.phase = "final-reconciliation";
    const final = await observe();
    record("new registration prevents stale deletion and offers cancellation review",
      final.events.race.exists && final.events.race.registrations > 0 && final.events.race.status === "active");
    c.need(final.canonical?.unchanged === true && final.scope?.active === true && final.scope.boundCount === 10 &&
      final.events.restricted.exists &&
      guard.reconcile(final), "FINAL_RECONCILIATION_FAILED");
    c.need(c.ROLE_KEYS.every(role => appCheckExchanges.get(role) === true), "REAL_APPCHECK_EXCHANGE_NOT_OBSERVED");
    await verifyDeployment(); c.sourceCheck(repo, candidate);
    c.need(safetyFailures.length === 0, "SAFETY_OR_BROWSER_FAILURE");
    report.status = "passed";
    report.serverEvidence = {canonicalUnchanged: true,
      events: Object.fromEntries(c.EVENT_KEYS.map(key => [key, final.events[key]]))};
  } catch (error) {
    failed = c.safeCode(error); report.status = "blocked"; report.blockers.push(failed); report.blockedAt = report.phase;
    try {
      if (currentPage && verifiedContexts.has(currentPage.context()) &&
        !await currentPage.getByText("Welcome back", {exact: true}).isVisible() &&
        await currentPage.getByRole("textbox", {name: "Password", exact: true}).count() === 0) {
        await capture(currentPage, `failed-${String(report.phase || "unknown").toLowerCase().replace(/[^a-z0-9-]/g, "-")}`);
      }
    } catch (_) {/* Keep the secret-free phase even when rendering has failed. */}
    try {
      const reconciliation = await observe();
      journal("failure-reconciliation", {snapshot: reconciliation, allOperationsResolved: guard.reconcile(reconciliation)});
      report.reconciliationCompleted = true;
    } catch (_) {report.reconciliationCompleted = false;}
  } finally {
    await browser.close().catch(() => {});
    await Promise.allSettled([...pending]);
    guard.disarm(); report.finishedAt = new Date().toISOString();
    report.operations = guard.summaries;
    report.safetyFailures = [...new Set(safetyFailures)];
    if (report.safetyFailures.length && !failed) {
      failed = "SAFETY_OR_BROWSER_FAILURE"; report.status = "blocked";
      report.blockers.push(failed); report.blockedAt = report.phase;
    }
    report.automaticRestartAllowed = false;
    report.realAppCheckExchangeRoles = c.ROLE_KEYS.filter(role => appCheckExchanges.get(role));
    c.save(path.join(output, "fixture-created-identities-private.json"), {runId: fixture.runId,
      candidateRunId: candidate.candidateRunId, projectId: c.PROJECT, identities: anonymousIdentities, automaticallyDeleted: false});
    await db.terminate().catch(() => {}); await deleteApp(app).catch(() => {});
    assertCurated(report, fixture);
    c.save(path.join(curated, "report.json"), report);
    journal("finished", {status: report.status, reportSha256: c.digest(report), automaticRestartAllowed: false});
  }
  if (failed) c.need(false, failed);
  return {status: report.status, reportPath: path.join(curated, "report.json"), reportSha256: c.digest(report)};
}
async function main() {
  const args = c.options(process.argv.slice(2));
  if (args["internal-worker"] !== "true") {
    // captureState's existing Firebase CLI can write raw stderr. Keep every
    // child stream private and emit only our fixed-schema terminal result.
    const child = spawnSync(process.execPath, [__filename, ...process.argv.slice(2), "--internal-worker", "true"], {
      encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], timeout: 30 * 60000, maxBuffer: 2 * 1024 * 1024,
      windowsHide: true,
    });
    let result;
    try {result = JSON.parse((child.stdout || "").trim().split(/\r?\n/).at(-1));} catch (_) {}
    if (child.status !== 0 || result?.status !== "passed" || !/^[a-f0-9]{64}$/.test(result.reportSha256 || "")) {
      c.need(false, "LIVE_WORKER_BLOCKED_REVIEW_PRIVATE_REPORT");
    }
    process.stdout.write(JSON.stringify({status: "passed", reportPath: result.reportPath, reportSha256: result.reportSha256}) + "\n");
    return;
  }
  const repo = path.resolve(args.repo || path.join(__dirname, ".."));
  c.need(args.candidate && args.receipt && args.fixture && args.output, "INPUT_FILES_REQUIRED");
  const read = file => JSON.parse(fs.readFileSync(path.resolve(file), "utf8").replace(/^\uFEFF/, ""));
  const result = await run({repo, candidate: read(args.candidate), receipt: read(args.receipt),
    fixture: read(args.fixture), directory: args.output});
  process.stdout.write(JSON.stringify(result) + "\n");
}
if (require.main === module) main().catch(error => {process.stderr.write(JSON.stringify({status: "blocked", code: c.safeCode(error), rawDiagnosticsOmitted: true}) + "\n"); process.exitCode = 1;});
module.exports = {createMutationGuard, assertCurated, waitForSnapshot, readOnlyDataRequest, run, READ_CALLS, MUTATIONS};
