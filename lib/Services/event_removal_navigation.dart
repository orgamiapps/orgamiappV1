import 'package:attendus/Services/event_removal_service.dart';
import 'package:flutter/material.dart';

/// Tracks event pages, including pages underneath the event editor. Removing
/// only this contiguous event flow preserves the originating list.
class EventRemovalNavigation {
  static final Map<Route<dynamic>, String> _eventRoutes = {};

  static void register(Route<dynamic>? route, String eventId) {
    if (route != null) _eventRoutes[route] = eventId;
  }

  static void unregister(Route<dynamic>? route) {
    if (route != null) _eventRoutes.remove(route);
  }

  static void complete(BuildContext context, EventRemovalResult result) {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final removed = result.affectedEventIds.toSet();
    bool needsDiscover = false;
    navigator.popUntil((route) {
      final belongsToFlow =
          route is PopupRoute || removed.contains(_eventRoutes[route]);
      if (!belongsToFlow) return true;
      if (route.isFirst) {
        needsDiscover = true;
        return true;
      }
      return false;
    });
    if (needsDiscover) {
      navigator.pushNamedAndRemoveUntil('/app/discover', (_) => false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (messenger?.mounted == true) {
        messenger!
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(result.message)));
      }
    });
  }

  static void backToList(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushNamedAndRemoveUntil('/app/discover', (_) => false);
    }
  }
}
