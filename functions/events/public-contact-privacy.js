"use strict";

function publishedContact(contact) {
  return contact?.visible === true ? {
    name: typeof contact.name === "string" ? contact.name.slice(0, 160) : "",
    email: typeof contact.email === "string" ? contact.email.slice(0, 254) : "",
    visible: true,
  } : {name: "", email: "", visible: false};
}

// Pure candidate generation only. Historical writes require a separately
// reviewed manifest, snapshot and version preconditions.
function scrubHiddenPublishedContact(data) {
  if (!data?.experience?.publicContact || data.experience.publicContact.visible === true) return data;
  return {...data, experience: {...data.experience, publicContact: publishedContact(data.experience.publicContact)}};
}

function contactExposure(eventId, data = {}) {
  const contact = data.experience?.publicContact;
  const hiddenFields = contact?.visible === true ? [] : ["name", "email"].filter((field) => typeof contact?.[field] === "string" && contact[field].trim().length > 0);
  return {path: `Events/${eventId}`, publiclyReadable: data.private === false,
    hiddenContactFields: hiddenFields, hiddenContactFieldCount: hiddenFields.length,
    coHostIdentifierCount: Array.isArray(data.coHosts) ? data.coHosts.length : 0,
    checkInStaffIdentifierCount: Array.isArray(data.checkInStaff) ? data.checkInStaff.length : 0};
}
module.exports = {publishedContact, scrubHiddenPublishedContact, contactExposure};
