import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class GoogleMapsBootstrap {
  static bool _isAvailable = false;
  static String? _errorMessage;

  static bool get isAvailable => _isAvailable;
  static String? get errorMessage => _errorMessage;

  static Future<void> initialize(String apiKey) async {
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      _errorMessage =
          'Google Maps is not configured for this web build. Add the '
          'GOOGLE_MAPS_WEB_API_KEY build definition.';
      return;
    }

    final existing = web.document.querySelector(
      'script[data-attendus-google-maps]',
    );
    if (existing != null) {
      _isAvailable = true;
      return;
    }

    final completer = Completer<void>();
    final script = web.document.createElement('script') as web.HTMLScriptElement
      ..async = true
      ..defer = true
      ..setAttribute('data-attendus-google-maps', 'true')
      ..src = Uri.https('maps.googleapis.com', '/maps/api/js', {
        'key': normalizedKey,
        'loading': 'async',
        'v': 'weekly',
      }).toString();

    final loadListener = ((web.Event _) {
      _isAvailable = true;
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    final errorListener = ((web.Event _) {
      _errorMessage =
          'Google Maps could not be loaded. Check the web key restrictions, '
          'billing, and network connection.';
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    script.addEventListener('load', loadListener);
    script.addEventListener('error', errorListener);
    web.document.head?.append(script);

    try {
      await completer.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      _errorMessage =
          'Google Maps timed out while loading. Check the network and try again.';
    } finally {
      script.removeEventListener('load', loadListener);
      script.removeEventListener('error', errorListener);
    }
  }
}
