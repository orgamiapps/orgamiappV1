'use strict';
function allowedBrowserRequest(value, method = 'GET') {
  let url;
  try { url = new URL(value); } catch { return false; }
  if (['data:', 'blob:', 'about:'].includes(url.protocol)) return true;
  if (['http:', 'ws:'].includes(url.protocol) && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)) return true;
  // Read-only public SDK/engine/font delivery. No Google APIs, auth, storage,
  // analytics, maps, payment, messaging or production Attendus endpoints.
  return method === 'GET' && url.protocol === 'https:' &&
    ((url.hostname === 'www.gstatic.com' && /^\/(firebasejs|flutter-canvaskit)\//.test(url.pathname)) ||
     (url.hostname === 'fonts.gstatic.com' && /^\/s\/[a-z0-9]+\/.+\.(woff2?|ttf)$/.test(url.pathname)));
}
module.exports = {allowedBrowserRequest};
