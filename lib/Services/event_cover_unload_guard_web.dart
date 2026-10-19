import 'dart:js_interop';
import 'package:web/web.dart' as web;

class EventCoverUnloadGuard {
  EventCoverUnloadGuard() {
    _listener = ((web.Event event) {
      event.preventDefault();
      (event as web.BeforeUnloadEvent).returnValue = '';
    }).toJS;
  }
  late final JSFunction _listener;
  bool _attached = false;
  void setUnsaved(bool value) {
    if (_attached == value) return;
    _attached = value;
    if (value) {
      web.window.addEventListener('beforeunload', _listener);
    } else {
      web.window.removeEventListener('beforeunload', _listener);
    }
  }

  void dispose() => setUnsaved(false);
}
