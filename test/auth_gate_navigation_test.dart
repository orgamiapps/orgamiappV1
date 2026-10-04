import 'package:attendus/Services/account_access_service.dart';
import 'package:attendus/Services/navigation_state_service.dart';
import 'package:attendus/Services/pending_auth_intent_service.dart';
import 'package:attendus/Utils/route_names.dart';
import 'package:attendus/widgets/auth_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NavigationStateService().initialize();
  });

  test(
    'explicit Discover overrides saved Profile and a stale conversation continuation',
    () async {
      final navigation = NavigationStateService();
      await navigation.saveNavigationState(
        routeName: RouteNames.myProfile,
        tabIndex: RouteNames.profileTab,
      );
      await PendingAuthIntentService.rememberConversation('old-chat');

      final entry = await AuthGateNavigation.resolve(forceDiscover: true);

      expect(entry.initialTab, RouteNames.homeTab);
      expect(entry.restoreNavigation, false);
      expect(entry.pendingIntent, isNull);
      expect(await navigation.restoreNavigationState(), isNull);
      expect(await navigation.restoreTabIndex(), isNull);
      expect(await PendingAuthIntentService.consume(), isNull);
    },
  );

  test(
    'explicit Discover clears a saved chat and pending event before guest or account entry',
    () async {
      final navigation = NavigationStateService();
      await navigation.saveNavigationState(
        routeName: RouteNames.chatScreen,
        tabIndex: RouteNames.messagesTab,
        parameters: {'conversationId': 'old-chat'},
      );
      await PendingAuthIntentService.rememberSharedEvent('old-event');
      final entry = await AuthGateNavigation.resolve(forceDiscover: true);
      expect(entry.initialTab, RouteNames.homeTab);
      expect(entry.restoreNavigation, false);
      expect(await navigation.shouldRestore(), false);
      expect(await PendingAuthIntentService.consume(), isNull);
    },
  );

  test(
    'ordinary app startup still restores a saved destination with no pending intent',
    () async {
      final navigation = NavigationStateService();
      await navigation.saveNavigationState(
        routeName: RouteNames.myProfile,
        tabIndex: RouteNames.profileTab,
      );
      final entry = await AuthGateNavigation.resolve();
      expect(entry.restoreNavigation, true);
      expect(entry.pendingIntent, isNull);
      expect(
        (await navigation.restoreNavigationState())?.routeName,
        RouteNames.myProfile,
      );
      expect(await navigation.restoreTabIndex(), RouteNames.profileTab);
    },
  );

  test(
    'ordinary authentication preserves the requested feature instead of saved navigation',
    () async {
      final navigation = NavigationStateService();
      await navigation.saveNavigationState(
        routeName: RouteNames.myProfile,
        tabIndex: RouteNames.profileTab,
      );
      await PendingAuthIntentService.rememberFeature(AccountFeature.messages);
      final entry = await AuthGateNavigation.resolve();
      expect(entry.restoreNavigation, false);
      expect(entry.initialTab, RouteNames.messagesTab);
      expect(entry.pendingIntent?.action, PendingAuthAction.dashboardTab);
      expect(await navigation.shouldRestore(), false);
    },
  );
}
