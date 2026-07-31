'use strict';
const {ROLES} = require('./constants');
function canAssignRoles(actorRoles, requestedRoles) {
  return Array.isArray(actorRoles) && actorRoles.includes('super_admin') && Array.isArray(requestedRoles) && requestedRoles.length > 0 && requestedRoles.every((role) => ROLES.includes(role));
}
module.exports = {canAssignRoles};
