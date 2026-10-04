'use strict';

// Metadata only: never retain headers, query strings, bodies, cookies, console
// payloads or arbitrary exception messages from an authenticated browser.
function safeLocation(value) {
  try {
    const url = new URL(value);
    if (!['http:', 'https:', 'ws:', 'wss:'].includes(url.protocol)) return null;
    const pathname = url.pathname
      .replace(/\/(manage|reset|verify|token|oob|__fixtures)\/[^/]+/gi, '/$1/[redacted]')
      .replace(/eyJ[A-Za-z0-9_.-]+/g, '[token]');
    return {origin: url.origin, path: pathname.slice(0, 240)};
  } catch { return null; }
}

function assetLocation(value, method) {
  if (method !== 'GET') return null;
  const location = safeLocation(value);
  if (!location) return null;
  const url = new URL(value);
  if ((url.hostname === 'www.gstatic.com' && /^\/(firebasejs|flutter-canvaskit)\//.test(url.pathname)) ||
      (url.hostname === 'fonts.gstatic.com' && /^\/s\//.test(url.pathname)) ||
      (['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) &&
        (/\/(?:flutter(?:_bootstrap)?\.js|main\.dart(?:\.bootstrap)?\.js|dart_sdk\.js)$/.test(url.pathname) ||
         /\/canvaskit\/[^?]+\.(?:js|wasm)$/.test(url.pathname)))) return location;
  return null;
}

function exceptionMetadata(error) {
  const message = String(error?.message || '');
  let category = 'unclassified';
  if (/dynamically imported module|importing a module script|module script failed/i.test(message)) category = 'module-import';
  else if (/fetch|network|load failed/i.test(message)) category = 'network';
  else if (/content security|trustedtype|trustedscript/i.test(message)) category = 'script-policy';
  else if (/webgl|canvaskit/i.test(message)) category = 'renderer';
  const name = ['Error', 'TypeError', 'ReferenceError', 'SyntaxError', 'RangeError', 'SecurityError', 'NetworkError'].includes(error?.name) ? error.name : 'Error';
  const sources = [...message.matchAll(/https?:\/\/[^\s'"<>]+/g)].slice(0, 3)
    .map(match => {
      const location = safeLocation(match[0]);
      if (!location) return null;
      return assetLocation(match[0], 'GET') || {origin: location.origin, path: '[redacted]'};
    }).filter(Boolean);
  return {name, category, sources};
}

function createBoundedWriter(append, {maxRecords = 400, maxBytes = 128 * 1024} = {}) {
  let records = 0, bytes = 0, capped = false;
  const marker = JSON.stringify({event: 'diagnostics-capped'}) + '\n';
  return (entry) => {
    if (capped) return;
    const line = JSON.stringify(entry) + '\n';
    const length = Buffer.byteLength(line);
    if (records >= maxRecords - 1 || bytes + length + Buffer.byteLength(marker) > maxBytes) {
      capped = true;
      if (records < maxRecords && bytes + Buffer.byteLength(marker) <= maxBytes) append(marker);
      return;
    }
    records++; bytes += length; append(line);
  };
}

function observeStartup(context, emit, {now = () => performance.now(), allowed = () => false} = {}) {
  const started = now(), pending = new Map(), pages = new Map();
  let next = 0, active = true;
  const elapsed = () => Math.max(0, Math.round(now() - started));
  const write = value => {if (active) emit({elapsedMs: elapsed(), ...value});};
  const request = value => {
    const location = assetLocation(value.url(), value.method());
    if (!location || pending.size >= 100 || next >= 200) return;
    const item = {id: ++next, ...location, allowed: allowed(value.url(), value.method()), started: now()};
    pending.set(value, item);
    const {started: _, ...metadata} = item;
    write({event: 'asset-start', ...metadata});
  };
  const response = value => {
    const item = pending.get(value.request());
    if (item) write({event: 'asset-response', id: item.id, status: value.status(), durationMs: Math.max(0, Math.round(now() - item.started))});
  };
  const finish = (value, failed) => {
    const item = pending.get(value);
    if (!item) return;
    pending.delete(value);
    const errorCode = failed ? (String(value.failure()?.errorText || '').match(/net::[A-Z0-9_]+/)?.[0] || 'transport-error') : undefined;
    write({event: failed ? 'asset-failed' : 'asset-finished', id: item.id,
      durationMs: Math.max(0, Math.round(now() - item.started)), ...(failed ? {errorCode} : {})});
  };
  const finished = value => finish(value, false), failed = value => finish(value, true);
  const observePage = page => {
    if (pages.has(page)) return;
    const onError = error => write({event: 'page-error', ...exceptionMetadata(error)});
    const onConsole = message => {
      const text = message.text();
      const module = text.match(/^Initializing Firebase (firebase_(?:core|auth|firestore|functions|messaging|storage|app_check))$/)?.[1];
      if (module) write({event: 'firebase-module-initializing', module});
      if (text.includes('Firebase core initialized')) write({event: 'firebase-core-initialized'});
      if (text.includes('Firebase initialization timed out')) write({event: 'firebase-core-timeout'});
    };
    page.on('pageerror', onError); page.on('console', onConsole);
    pages.set(page, {onError, onConsole});
  };
  context.on('request', request); context.on('response', response);
  context.on('requestfinished', finished); context.on('requestfailed', failed);
  context.on('page', observePage);
  for (const page of context.pages()) observePage(page);
  return () => {
    if (!active) return;
    write({event: 'startup-observation-ended', assetCount: next, pendingCount: pending.size,
      pending: [...pending.values()].slice(0, 25).map(({started: start, ...item}) => ({...item, durationMs: Math.max(0, Math.round(now() - start))}))});
    active = false;
    context.off('request', request); context.off('response', response);
    context.off('requestfinished', finished); context.off('requestfailed', failed);
    context.off('page', observePage);
    for (const [page, {onError, onConsole}] of pages) {page.off('pageerror', onError); page.off('console', onConsole);}
    pending.clear(); pages.clear();
  };
}

module.exports = {safeLocation, assetLocation, exceptionMetadata, createBoundedWriter, observeStartup};
