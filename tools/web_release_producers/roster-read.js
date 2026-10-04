"use strict";

const {isDeepStrictEqual} = require("node:util");
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
const timedOut = () => Object.assign(Error("Roster read did not complete within its bounded deadline."), {code: "roster-read-timeout"});
const unavailable = (error) => String(error?.status || error?.code || "").replace(/^functions\//, "").replaceAll("-", "_").toUpperCase() === "UNAVAILABLE";

// This helper can invoke only the roster read. Mutation failures, unknown
// transport outcomes and expired snapshots never enter a retry scope.
async function readRosterPage(call, request, {timeoutMs = 120000, maxAttempts = 30, retryDelayMs = 1000,
  now = Date.now, sleep = pause} = {}) {
  if (typeof call !== "function" || !request || typeof request.eventId !== "string" || !request.eventId ||
      !Number.isFinite(timeoutMs) || timeoutMs < 1 || timeoutMs > 600000 ||
      !Number.isInteger(maxAttempts) || maxAttempts < 1 || maxAttempts > 100 ||
      !Number.isFinite(retryDelayMs) || retryDelayMs < 0 || retryDelayMs > 15000) throw Error("A bounded roster read is required.");
  const original = structuredClone(request), deadline = now() + timeoutMs;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const remaining = deadline - now();
    if (remaining <= 0) throw timedOut();
    let timer;
    try {
      const result = await Promise.race([
        Promise.resolve().then(() => call("listEventRosterV2", structuredClone(original))),
        new Promise((_, reject) => {timer = setTimeout(() => reject(timedOut()), remaining);}),
      ]);
      if (now() >= deadline) throw timedOut();
      return result;
    } catch (error) {
      if (!unavailable(error) || attempt === maxAttempts) throw error;
    } finally {clearTimeout(timer);}
    const remainingAfterRead = deadline - now();
    if (remainingAfterRead <= 0) throw timedOut();
    await sleep(Math.min(retryDelayMs, remainingAfterRead));
  }
}

async function collectRosterPages(call, request, {timeoutMs = 360000, maxPages = 100, ...readOptions} = {}) {
  if (request?.cursor || !Number.isInteger(maxPages) || maxPages < 1 || maxPages > 100 ||
      !Number.isFinite(timeoutMs) || timeoutMs < 1 || timeoutMs > 600000) throw Error("A bounded first-page roster scan is required.");
  const original = structuredClone(request), now = readOptions.now || Date.now, deadline = now() + timeoutMs;
  const rowIds = new Set(), cursors = new Set();
  let cursor, pages = 0, snapshot;
  do {
    if (pages >= maxPages || now() >= deadline) throw Error("Roster pagination did not terminate within its bound.");
    const page = await readRosterPage(call, {...original, ...(cursor ? {cursor} : {})}, {...readOptions, timeoutMs: deadline - now()});
    if (!Array.isArray(page?.rows) || !page.snapshotAt || !Number.isInteger(page.total) || page.total < 0 ||
        !Number.isInteger(page.matchingCount) || page.matchingCount < 0 ||
        page.nextCursor !== null && (typeof page.nextCursor !== "string" || !page.nextCursor)) throw Error("Roster page is malformed.");
    const identity = {snapshotAt: page.snapshotAt, total: page.total, matchingCount: page.matchingCount};
    if (snapshot && !isDeepStrictEqual(snapshot, identity)) throw Error("Roster pagination changed its snapshot.");
    snapshot ||= structuredClone(identity);
    for (const row of page.rows) {
      const id = row.registrationId || row.id;
      if (!id || rowIds.has(id)) throw Error("Roster contains a duplicate or missing row identity.");
      rowIds.add(id);
    }
    cursor = page.nextCursor;
    if (cursor && cursors.has(cursor)) throw Error("Roster pagination repeated a cursor.");
    if (cursor) cursors.add(cursor);
    pages++;
  } while (cursor);
  if (rowIds.size !== snapshot.matchingCount) throw Error("Roster pagination omitted matching snapshot rows.");
  return {pages, seen: rowIds.size, snapshot};
}

module.exports = {readRosterPage, collectRosterPages};
