'use strict';

const {fail} = require('./errors');
const buckets = new Map();

function rateLimit(key, max = 120, windowMs = 60000) {
  const now = Date.now();
  const current = buckets.get(key);
  if (!current || current.resetAt <= now) { buckets.set(key, {count: 1, resetAt: now + windowMs}); return; }
  current.count += 1;
  if (current.count > max) fail(429, 'RATE_LIMITED', 'Too many administrator requests. Retry later.');
}

module.exports = {rateLimit};
