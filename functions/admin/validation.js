'use strict';

const {fail} = require('./errors');

function object(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(400, 'INVALID_ARGUMENT', 'A JSON object is required.');
  return value;
}
function string(value, name, {required = true, min = 1, max = 500} = {}) {
  if ((value === undefined || value === null || value === '') && !required) return undefined;
  if (typeof value !== 'string' || value.trim().length < min || value.trim().length > max) fail(400, 'INVALID_ARGUMENT', `${name} must be ${min}-${max} characters.`);
  return value.trim();
}
function boolean(value, name) {
  if (typeof value !== 'boolean') fail(400, 'INVALID_ARGUMENT', `${name} must be a boolean.`);
  return value;
}
function enumeration(value, name, values) {
  if (!values.includes(value)) fail(400, 'INVALID_ARGUMENT', `${name} is invalid.`, {allowed: values});
  return value;
}
function limit(value) {
  const parsed = value === undefined ? 25 : Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 100) fail(400, 'INVALID_ARGUMENT', 'limit must be between 1 and 100.');
  return parsed;
}
function mutation(body, destructive = false) {
  object(body);
  const reason = string(body.reason, 'reason', {min: 10, max: 500});
  if (destructive && boolean(body.confirmed, 'confirmed') !== true) fail(400, 'CONFIRMATION_REQUIRED', 'Explicit confirmation is required.');
  return reason;
}
module.exports = {object, string, boolean, enumeration, limit, mutation};
