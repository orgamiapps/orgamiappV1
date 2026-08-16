"use strict";

const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");

function uniqueId(prefix) {
  return `${prefix}-${Date.now()}-${randomUUID().slice(0, 8)}`;
}

async function fetchWithTimeout(url, options = {}, timeoutMs = 15000) {
  return fetch(url, {
    ...options,
    signal: AbortSignal.timeout(timeoutMs),
  });
}

async function waitFor(check, description, options = {}) {
  const timeoutMs = options.timeoutMs || 60000;
  const intervalMs = options.intervalMs || 250;
  const deadline = Date.now() + timeoutMs;
  let lastError;

  while (Date.now() < deadline) {
    try {
      const result = await check();
      if (result) return result;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }

  let observed = "unavailable";
  if (options.describe) {
    try {
      observed = JSON.stringify(await options.describe());
    } catch (error) {
      observed = `diagnostic failed: ${error.message}`;
    }
  }
  const errorSuffix = lastError ? `; last error: ${lastError.message}` : "";
  assert.fail(
      `Timed out after ${timeoutMs}ms waiting for ${description}; ` +
      `last observed: ${observed}${errorSuffix}`,
  );
}

module.exports = {fetchWithTimeout, uniqueId, waitFor};
