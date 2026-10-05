'use strict';

// Configuration support only. Callers still verify the sealed candidate, fixture,
// deployment and capture scope, and qualify real-provider acceptance separately.
// Debug secrets are closure-local, never evidence fields or exception details.
const STAGE = Object.freeze({projectId: 'attendus-staging', projectNumber: '925344893088',
  appId: '1:925344893088:web:3be71e809ba516e1d021c5', origin: 'https://attendus-staging.web.app'});
const SECRET_ENV = 'STAGING_APPCHECK_DEBUG_TOKEN';
const UUID4 = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const HASH = /^[a-f0-9]{64}$/;
const fail = (code) => {throw new Error(`App Check test mode: ${code}`);};
const plain = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const matches = (pattern, value) => typeof value === 'string' && value.trim() === value && pattern.test(value);

function identity(candidate, fixture, env) {
  if (!plain(candidate) || candidate.environment !== 'staging' || candidate.projectId !== STAGE.projectId ||
      !matches(/^[a-f0-9]{40}$/, candidate.sourceSha) || !matches(/^\d{1,30}$/, candidate.candidateRunId) ||
      !matches(HASH, candidate.webSha256) || !plain(fixture) || fixture.projectId !== STAGE.projectId ||
      fixture.sourceSha !== candidate.sourceSha || fixture.candidateRunId !== candidate.candidateRunId ||
      !matches(/^[a-z0-9-]{8,80}$/, fixture.runId) || !plain(fixture.firebase) ||
      fixture.firebase.projectId !== STAGE.projectId || fixture.firebase.projectNumber !== STAGE.projectNumber ||
      fixture.firebase.appId !== STAGE.appId ||
      !matches(/^[A-Za-z0-9_-]{8,200}$/, fixture.firebase.apiKey)) fail('invalid_staging_identity');
  if ([candidate, fixture, fixture.firebase].some((value) => value.emulator || value.useEmulator || value.emulatorHost) ||
      ['FIREBASE_AUTH_EMULATOR_HOST', 'FIRESTORE_EMULATOR_HOST', 'FIREBASE_DATABASE_EMULATOR_HOST',
        'FIREBASE_STORAGE_EMULATOR_HOST', 'FIREBASE_EMULATOR_HUB'].some((key) => env[key] !== undefined)) fail('emulator_unsupported');
}

// Playwright serializes this function. It must remain self-contained. It runs on
// page navigations AND child frames, hence both the origin and top-level fence.
// It does not initialize Firebase, call providers, touch storage, or cover workers.
function installDebugInDocument(options) {
  'use strict';
  const {origin, token} = options;
  if (globalThis.top !== globalThis.self || globalThis.location?.origin !== origin) return;
  if (typeof globalThis.document !== 'object' ||
      Object.prototype.hasOwnProperty.call(globalThis, 'FIREBASE_APPCHECK_DEBUG_TOKEN')) {
    throw new Error('App Check test mode: document_not_fresh');
  }
  // Both official CDN SDKs (11.10.0/12.15.0) console.log the supplied string at
  // initializeAppCheck. Redact before setting the global; do not log arguments.
  const escaped = token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pattern = new RegExp(escaped, 'gi');
  if (!globalThis.console || typeof globalThis.console.log !== 'function') {
    throw new Error('App Check test mode: console_unavailable');
  }
  for (const method of ['log', 'info', 'warn', 'error', 'debug']) {
    const previous = globalThis.console[method];
    if (typeof previous !== 'function') continue;
    const wrapped = function(...args) {
      return Reflect.apply(previous, this, args.map((value) => typeof value === 'string' ?
        value.replace(pattern, '[REDACTED_APPCHECK_DEBUG_TOKEN]') : value));
    };
    try {globalThis.console[method] = wrapped;} catch {throw new Error('App Check test mode: console_not_writable');}
    if (globalThis.console[method] !== wrapped) throw new Error('App Check test mode: console_not_writable');
  }
  globalThis.FIREBASE_APPCHECK_DEBUG_TOKEN = token;
}

function secretTools(token) {
  if (!token) return {redact: (value) => String(value), assertPublishable: () => true};
  // Known plaintext/URL/JSON/transport encodings, not a claim to detect arbitrary
  // encryption. UUID characters are ASCII; mixed-case percent/unicode forms are
  // handled character by character rather than by one canonical encoded string.
  const encoded = [...token].map((character) => {
    const codes = [...new Set([character.toLowerCase(), character.toUpperCase()])]
      .map((value) => value.charCodeAt(0).toString(16).padStart(2, '0'));
    return `(?:${character}|%(?:25)*(?:${codes.join('|')})|\\\\u00(?:${codes.join('|')}))`;
  }).join('');
  const forms = [token, token.toUpperCase()].flatMap((value) => [Buffer.from(value).toString('base64'),
    Buffer.from(value).toString('base64url'), Buffer.from(value).toString('hex')]);
  const pattern = new RegExp(`${encoded}|${[...new Set(forms)].join('|')}`, 'gi');
  function text(value) {
    if (typeof value === 'string') return value;
    if (Buffer.isBuffer(value) || value instanceof Uint8Array) return Buffer.from(value).toString('utf8');
    fail('publication_bytes_required');
  }
  return {
    redact(value) {return text(value).replace(pattern, '[REDACTED_APPCHECK_DEBUG_TOKEN]');},
    assertPublishable(value) {pattern.lastIndex = 0; if (pattern.test(text(value))) fail('secret_in_publication'); return true;},
  };
}

function createAppCheckTestMode({mode = 'real', candidate, fixture, producer = 'browser', driver = 'playwright',
  registeredResource, env = process.env} = {}) {
  if (!['real', 'staging-debug-functional'].includes(mode)) fail('unsupported_mode');
  if (!plain(env)) fail('invalid_environment');
  identity(candidate, fixture, env); // Do not resolve the secret before these fences.
  if (mode === 'staging-debug-functional' && (driver !== 'playwright' || !['browser', 'browser-cache-upgrade'].includes(producer))) fail('debug_driver_unsupported');
  let raw;
  try {raw = env[SECRET_ENV];} catch {fail('secret_environment_unavailable');}
  if (mode === 'real' && raw !== undefined) fail('unexpected_secret_in_real_mode');
  if (mode === 'real' && registeredResource !== undefined) fail('unexpected_debug_resource');
  if (mode === 'staging-debug-functional' && !matches(UUID4, raw)) fail('invalid_debug_secret');
  const token = mode === 'staging-debug-functional' ? raw : null;
  const resourcePrefix = `projects/${STAGE.projectNumber}/apps/${STAGE.appId}/debugTokens/`;
  if (token && (typeof registeredResource !== 'string' || !registeredResource.startsWith(resourcePrefix) ||
      !matches(/^[A-Za-z0-9_-]{1,128}$/, registeredResource.slice(resourcePrefix.length)) ||
      registeredResource.toLowerCase().includes(token.toLowerCase()))) fail('invalid_registered_resource');
  const safe = secretTools(token);
  if (token) safe.assertPublishable(registeredResource);
  const metadata = Object.freeze({schemaVersion: 1, mode, projectId: STAGE.projectId, appId: STAGE.appId,
    sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId, fixtureRunId: fixture.runId,
    registeredResource: token ? registeredResource : null, configurationOnly: true,
    realProviderAttestation: 'unverified', qualifiesCandidate: false});
  if (token) safe.assertPublishable(JSON.stringify(metadata));
  const bound = Object.freeze({sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId,
    webSha256: candidate.webSha256, apiKey: fixture.firebase.apiKey});
  const installed = new WeakSet();

  function allowedOrigin(origin, proof) {
    if (origin === STAGE.origin) return true;
    let url;
    try {url = new URL(origin);} catch {return false;}
    if (url.href !== `${origin}/` || url.protocol !== 'http:' || url.hostname !== 'localhost' ||
        !url.port || Number(url.port) < 1024 || url.username || url.password || url.search || url.hash ||
        !plain(proof) || proof.schemaVersion !== 1 || proof.verified !== true || proof.origin !== origin ||
        proof.sourceSha !== bound.sourceSha || proof.candidateRunId !== bound.candidateRunId ||
        proof.currentWebSha256 !== bound.webSha256 || !matches(HASH, proof.predecessorWebSha256) ||
        !matches(HASH, proof.proofSha256) || !Number.isFinite(Date.parse(proof.verifiedAt))) return false;
    return ['current', 'predecessor'].every((key) => plain(proof[key]) && proof[key].projectId === STAGE.projectId &&
      proof[key].projectNumber === STAGE.projectNumber && proof[key].appId === STAGE.appId &&
      proof[key].runtimeVerified === true && proof[key].messagingWorkerVerified === true);
  }

  async function install(context, {origin = STAGE.origin, cacheProof, capturePolicy} = {}) {
    if (!token) return metadata; // Inert: preserves the existing real Enterprise path.
    if (!allowedOrigin(origin, cacheProof)) fail('unverified_document_origin');
    if (!plain(capturePolicy) || ['rawConsole', 'trace', 'har', 'storageState'].some((key) => capturePolicy[key] !== false)) fail('unsafe_capture_policy');
    if (!context || typeof context.addInitScript !== 'function' || typeof context.pages !== 'function' || installed.has(context)) fail('invalid_or_reused_context');
    // Declaration and pages() fence cannot inspect external CDP/logging sinks.
    // Caller must install this before pages/capture hooks and never persist state.
    try {
      if (context.pages().length !== 0) fail('context_not_fresh');
      installed.add(context);
      await context.addInitScript(installDebugInDocument, {origin, token});
    } catch {fail('document_initializer_failed');}
    return metadata;
  }

  function allowsDebugRequest(value, method, rawBody) {
    if (!token || !['POST', 'OPTIONS'].includes(method) || typeof value !== 'string') return false;
    let url;
    try {url = new URL(value);} catch {return false;}
    if (!['https://content-firebaseappcheck.googleapis.com', 'https://firebaseappcheck.googleapis.com'].includes(url.origin) ||
        url.username || url.password || url.hash || [...url.searchParams.keys()].length !== 1 ||
        url.searchParams.getAll('key').length !== 1 || url.searchParams.get('key') !== bound.apiKey) return false;
    const match = /^\/v1\/projects\/([^/]+)\/apps\/([^/]+):exchangeDebugToken$/.exec(url.pathname);
    if (!match || ![STAGE.projectId, STAGE.projectNumber].includes(match[1])) return false;
    try {if (decodeURIComponent(match[2]) !== STAGE.appId) return false;} catch {return false;}
    if (method === 'OPTIONS') return rawBody === undefined || rawBody === null || rawBody === '';
    // Both retained official SDK versions JSON.stringify exactly this sole field.
    // Reject duplicate keys, aliases, whitespace inside the credential and extras.
    if (typeof rawBody !== 'string' || rawBody.length > 256 ||
        !/^\s*\{\s*"debug_token"\s*:\s*"[a-fA-F0-9-]+"\s*\}\s*$/.test(rawBody)) return false;
    try {return JSON.parse(rawBody).debug_token === token;} catch {return false;}
  }
  return Object.freeze({metadata, install, allowsDebugRequest, redact: safe.redact, assertPublishable: safe.assertPublishable});
}

module.exports = {createAppCheckTestMode};
