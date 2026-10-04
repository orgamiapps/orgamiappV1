"use strict";

const appSdk = require("firebase-admin/app");
const authSdk = require("firebase-admin/auth");
const firestoreSdk = require("firebase-admin/firestore");
const messagingSdk = require("firebase-admin/messaging");
const storageSdk = require("firebase-admin/storage");

if (appSdk.getApps().length === 0) appSdk.initializeApp();

function firestore() {
  return firestoreSdk.getFirestore();
}
Object.assign(firestore, firestoreSdk);

function auth() {
  return authSdk.getAuth();
}
Object.assign(auth, authSdk);

function messaging() {
  return messagingSdk.getMessaging();
}
Object.assign(messaging, messagingSdk);

function storage() {
  return storageSdk.getStorage();
}
Object.assign(storage, storageSdk);

// Temporary adapter for legacy modules. New modules should import the relevant
// Firebase Admin service directly.
module.exports = {
  ...appSdk,
  auth,
  credential: {applicationDefault: appSdk.applicationDefault, cert: appSdk.cert},
  firestore,
  messaging,
  storage,
};
