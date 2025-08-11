// Give the service worker access to Firebase Messaging.
// Note that you can only use Firebase Messaging here, other Firebase libraries are not available in the service worker.

importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyAgxBhWgtmRA_cc-JcuMP8fXl7NjZIthOI",
  authDomain: "orgami-66nxok.firebaseapp.com",
  projectId: "orgami-66nxok",
  storageBucket: "orgami-66nxok.appspot.com",
  messagingSenderId: "951311475019",
  appId: "1:951311475019:web:d65cfc2cbe6e987c89c8ce"
});

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage(function(payload) {
  const title = (payload.notification && payload.notification.title) || 'Orgami';
  const body = (payload.notification && payload.notification.body) || '';
  const data = payload.data || {};
  self.registration.showNotification(title, {
    body,
    data,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png'
  });
});