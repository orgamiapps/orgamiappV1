// Retire Flutter's legacy app-cache worker without clearing authentication or
// application storage. Keep this endpoint available while older installations
// may still be controlled by flutter_service_worker.js.
self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const cacheNames = await caches.keys();
    await Promise.all(
      cacheNames
        .filter((cacheName) => cacheName.startsWith('flutter-'))
        .map((cacheName) => caches.delete(cacheName)),
    );

    await self.registration.unregister();

    const windows = await self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });
    await Promise.all(windows.map((client) => client.navigate(client.url)));
  })());
});
