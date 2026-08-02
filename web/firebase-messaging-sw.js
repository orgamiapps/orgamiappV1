// Give the service worker access to Firebase Messaging.
// Note that you can only use Firebase Messaging here, other Firebase libraries are not available in the service worker.

importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "__ATTENDUS_FIREBASE_API_KEY__",
  authDomain: "__ATTENDUS_FIREBASE_AUTH_DOMAIN__",
  projectId: "__ATTENDUS_FIREBASE_PROJECT_ID__",
  storageBucket: "__ATTENDUS_FIREBASE_STORAGE_BUCKET__",
  messagingSenderId: "__ATTENDUS_FIREBASE_MESSAGING_SENDER_ID__",
  appId: "__ATTENDUS_FIREBASE_APP_ID__"
});

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage(function(payload) {
  const title = (payload.notification && payload.notification.title) || 'Attendus';
  const body = (payload.notification && payload.notification.body) || '';
  const data = payload.data || {};
  self.registration.showNotification(title, {
    body,
    data,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png'
  });
});
