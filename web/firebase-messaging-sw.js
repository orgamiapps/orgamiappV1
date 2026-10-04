// Register before Firebase's click listener so every handled notification uses
// a known same-origin app route. Firebase carries its payload under FCM_MSG.
// Authentication and resource access are restored/checked by the app route;
// this worker cannot inspect Firebase Auth before the OS displays a push.
function attendusPushDestination(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) return null;
  let path;
  let id;
  switch (data.type) {
    case 'discovery_new_events':
      if (data.eventId === '' || data.eventId == null) {
        return new URL('/app/discover', self.location.origin).href;
      }
      path = '/app/event/';
      id = data.eventId;
      break;
    case 'event_reminder':
    case 'event_changes':
    case 'geofence_checkin':
    case 'new_event':
    case 'ticket_update':
    case 'organizer_feedback':
    case 'event_feedback':
      path = '/app/event/';
      id = data.eventId;
      break;
    case 'org_update':
      path = '/app/community/';
      id = data.organizationId;
      break;
    case 'new_message':
    case 'message':
    case 'group_message':
    case 'message_mention':
      path = '/';
      id = data.conversationId;
      break;
    default:
      return null;
  }
  if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,300}$/.test(id)) return null;
  const destination = new URL(path, self.location.origin);
  if (path === '/') destination.searchParams.set('conversationId', id);
  else destination.pathname += encodeURIComponent(id);
  return destination.href;
}

async function openAttendusPush(destination) {
  const windows = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
  for (const client of windows) {
    try {
      if (new URL(client.url).origin !== self.location.origin) continue;
      const opened = await client.navigate(destination);
      if (opened) {
        await opened.focus();
        return;
      }
    } catch (_) {
      // A window can close between enumeration and navigation. Try another.
    }
  }
  const opened = await self.clients.openWindow(destination);
  if (opened) await opened.focus();
}

self.addEventListener('notificationclick', (event) => {
  event.stopImmediatePropagation();
  event.notification.close();
  if (event.action) return;
  const wrapper = event.notification.data;
  const data = wrapper && wrapper.FCM_MSG ? wrapper.FCM_MSG.data : wrapper;
  const destination = attendusPushDestination(data);
  // Never follow arbitrary link/url fields or Firebase's fallback click URL.
  if (destination) event.waitUntil(openAttendusPush(destination));
});

const attendusWorkerConfig = {
  apiKey: "__ATTENDUS_FIREBASE_API_KEY__",
  authDomain: "__ATTENDUS_FIREBASE_AUTH_DOMAIN__",
  projectId: "__ATTENDUS_FIREBASE_PROJECT_ID__",
  storageBucket: "__ATTENDUS_FIREBASE_STORAGE_BUCKET__",
  messagingSenderId: "__ATTENDUS_FIREBASE_MESSAGING_SENDER_ID__",
  appId: "__ATTENDUS_FIREBASE_APP_ID__"
};

// Raw development has no provider identity. Do not import or initialize provider
// code until release configuration replaces the public Firebase placeholders.
if (!attendusWorkerConfig.projectId.startsWith('__')) {
  importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
  importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');
  firebase.initializeApp(attendusWorkerConfig);

  const messaging = firebase.messaging();

  messaging.onBackgroundMessage(function() {
  // FCM already displays notification payloads. Data-only messages are silent:
  // fabricating a blank generic notification neither conveys content nor has
  // a trustworthy account context. Server-owned inbox records remain the source.
  });
}
