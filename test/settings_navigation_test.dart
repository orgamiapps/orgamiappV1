import 'package:attendus/Utils/route_names.dart';
import 'package:attendus/Services/pending_auth_intent_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy account and notification tabs normalize to Profile', () {
    expect(
      RouteNames.normalizeDashboardTabIndex(RouteNames.legacyAccountTab),
      RouteNames.profileTab,
    );
    expect(
      RouteNames.normalizeDashboardTabIndex(RouteNames.legacyNotificationsTab),
      RouteNames.profileTab,
    );
  });

  test('settings and legacy account routes resolve to Profile', () {
    expect(
      RouteNames.getDashboardTabForRoute(RouteNames.settings),
      RouteNames.profileTab,
    );
    expect(
      RouteNames.getDashboardTabForRoute(RouteNames.legacyAccount),
      RouteNames.profileTab,
    );
  });

  test('legacy pending Account intent resolves to Profile', () {
    final intent = PendingAuthIntent.fromJson({
      'action': PendingAuthAction.dashboardTab.name,
      'dashboardTab': RouteNames.legacyAccountTab,
      'sourceFeature': 'account',
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
    });

    expect(intent, isNotNull);
    expect(intent!.dashboardTab, RouteNames.profileTab);
  });

  test('shared event auth intent retains its destination', () {
    final intent = PendingAuthIntent.fromJson({
      'action': PendingAuthAction.sharedEvent.name,
      'eventId': 'event-123',
      'sourceFeature': 'accessRequest',
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
    });

    expect(intent, isNotNull);
    expect(intent!.eventId, 'event-123');
  });
}
