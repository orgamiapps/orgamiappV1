"use strict";

// The packaged Flutter initializer selects Persistence.LOCAL. FlutterFire maps
// that to browserLocalPersistence, not indexedDBLocalPersistence. Read exactly
// the requested app's LOCAL record; never fall back to another app/account.
// This function is self-contained for page.evaluate and WebDriver serialization.
// Tokens remain in memory for authenticated requests, never in evidence/errors.
function readFirebaseAuthStateInBrowser(options) {
  const reject = (code) => ({state: "rejected", code});
  if (!options || options.projectId !== "attendus-staging" ||
      typeof options.apiKey !== "string" || !/^[A-Za-z0-9_-]{8,200}$/.test(options.apiKey) ||
      options.appName !== "[DEFAULT]" || typeof options.expectedUid !== "string" ||
      !options.expectedUid || options.expectedUid.length > 128 || options.expectedUid.trim() !== options.expectedUid ||
      /[\u0000-\u001f\u007f/]/.test(options.expectedUid)) return reject("invalid_expected_identity");
  let raw;
  try {
    raw = localStorage.getItem(`firebase:authUser:${options.apiKey}:${options.appName}`);
  } catch {
    return reject("local_storage_unavailable");
  }
  if (raw === null) return {state: "missing"};
  if (typeof raw !== "string" || raw.length > 65536) return reject("malformed_local_record");
  let user;
  try {user = JSON.parse(raw);} catch {return reject("malformed_local_record");}
  if (!user || Array.isArray(user) || typeof user !== "object") return reject("malformed_local_record");
  if (user.apiKey !== options.apiKey || user.appName !== options.appName) return reject("app_identity_mismatch");
  if (user.uid !== options.expectedUid || user.isAnonymous !== false) return reject("actor_identity_mismatch");
  const token = user.stsTokenManager?.accessToken;
  if (typeof token !== "string" || token.length > 16384) return reject("malformed_identity_token");
  const pieces = token.split(".");
  if (pieces.length !== 3 || pieces.some((piece) => !/^[A-Za-z0-9_-]+$/.test(piece))) return reject("malformed_identity_token");
  let header, claims;
  try {
    const decode = (piece) => {
      const base64 = piece.replace(/-/g, "+").replace(/_/g, "/");
      const bytes = Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
      return JSON.parse(new TextDecoder("utf-8", {fatal: true}).decode(bytes));
    };
    header = decode(pieces[0]); claims = decode(pieces[1]);
  } catch {return reject("malformed_identity_token");}
  if (!header || header.alg !== "RS256" || !claims || Array.isArray(claims) || typeof claims !== "object") return reject("malformed_identity_token");
  if (claims.aud !== options.projectId || claims.iss !== `https://securetoken.google.com/${options.projectId}`) return reject("token_project_mismatch");
  if (claims.sub !== options.expectedUid || (claims.user_id !== undefined && claims.user_id !== options.expectedUid) ||
      claims.firebase?.sign_in_provider === "anonymous") return reject("token_actor_mismatch");
  const now = Math.floor(Date.now() / 1000);
  if (!Number.isSafeInteger(claims.exp) || !Number.isSafeInteger(claims.iat) || claims.iat <= 0 ||
      claims.exp <= claims.iat || claims.exp <= now || claims.iat > now + 30 ||
      (claims.auth_time !== undefined && (!Number.isSafeInteger(claims.auth_time) || claims.auth_time <= 0 || claims.auth_time > claims.iat + 30))) return reject("token_time_invalid");
  // This is identity/provenance validation, not cryptographic JWT verification.
  // Firebase callable authorization verifies the token at its own boundary.
  return {state: "ready", uid: user.uid, isAnonymous: false, token};
}

function safeReadError(code) {
  const allowed = new Set(["invalid_expected_identity", "local_storage_unavailable", "malformed_local_record",
    "app_identity_mismatch", "actor_identity_mismatch", "malformed_identity_token", "token_project_mismatch",
    "token_actor_mismatch", "token_time_invalid", "local_state_timeout", "browser_read_failed"]);
  const safe = allowed.has(code) ? code : "browser_read_failed";
  const error = new Error(`Packaged browser authentication state rejected (${safe}).`);
  error.code = safe;
  return error;
}

async function readFirebaseAuthStatePage(page, options) {
  const timeoutMs = options?.timeoutMs ?? 10000;
  if (!options || !Number.isFinite(timeoutMs) || timeoutMs <= 0 || timeoutMs > 30000) throw safeReadError("invalid_expected_identity");
  const deadline = performance.now() + timeoutMs;
  const input = {apiKey: options.apiKey, projectId: options.projectId, appName: options.appName, expectedUid: options.expectedUid};
  let timer;
  try {
    return await Promise.race([
      (async () => {
        while (performance.now() < deadline) {
          let state;
          try {state = await page.evaluate(readFirebaseAuthStateInBrowser, input);} catch {throw safeReadError("browser_read_failed");}
          if (performance.now() >= deadline) throw safeReadError("local_state_timeout");
          if (state?.state === "ready" && state.uid === input.expectedUid && state.isAnonymous === false && typeof state.token === "string") {
            return {uid: state.uid, isAnonymous: false, token: state.token};
          }
          if (state?.state === "rejected") throw safeReadError(state.code);
          if (state?.state !== "missing") throw safeReadError("browser_read_failed");
          await new Promise((resolve) => setTimeout(resolve, Math.min(100, Math.max(0, deadline - performance.now()))));
        }
        throw safeReadError("local_state_timeout");
      })(),
      new Promise((_, reject) => {timer = setTimeout(() => reject(safeReadError("local_state_timeout")), timeoutMs);}),
    ]);
  } finally {clearTimeout(timer);}
}

module.exports = {readFirebaseAuthStateInBrowser, readFirebaseAuthStatePage};
