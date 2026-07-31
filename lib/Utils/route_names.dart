/// Route name constants for navigation state restoration
class RouteNames {
  static const int homeTab = 0;
  static const int groupsTab = 1;
  static const int messagesTab = 2;
  static const int profileTab = 3;
  static const int accountTab = 4;
  static const int legacyNotificationsTab = 5;

  // Dashboard and main tabs
  static const String dashboard = 'dashboard';
  static const String homeHub = 'home_hub';
  static const String groups = 'groups';
  static const String messaging = 'messaging';
  static const String myProfile = 'my_profile';
  static const String notifications = 'notifications';
  static const String account = 'account';

  // Event screens
  static const String singleEvent = 'single_event';
  static const String createEvent = 'create_event';
  static const String editEvent = 'edit_event';
  static const String ticketManagement = 'ticket_management';
  static const String eventAnalytics = 'event_analytics';
  static const String attendeeManagement = 'attendee_management';

  // Group/Organization screens
  static const String groupProfile = 'group_profile';
  static const String groupAnalytics = 'group_analytics';
  static const String manageGroups = 'manage_groups';
  static const String groupAdminSettings = 'group_admin_settings';
  static const String manageMembers = 'manage_members';
  static const String manageFeedPosts = 'manage_feed_posts';
  static const String pendingEvents = 'pending_events';

  // Messaging screens
  static const String chatScreen = 'chat_screen';
  static const String newMessage = 'new_message';

  // Profile screens
  static const String userProfile = 'user_profile';
  static const String myTickets = 'my_tickets';

  // Quiz screens
  static const String quizBuilder = 'quiz_builder';
  static const String quizHost = 'quiz_host';
  static const String quizParticipant = 'quiz_participant';

  // Face recognition screens
  static const String faceEnrollment = 'face_enrollment';
  static const String faceScanner = 'face_scanner';

  // Premium screens
  static const String premiumFeatures = 'premium_features';
  static const String premiumUpgrade = 'premium_upgrade';

  // Other screens
  static const String search = 'search';
  static const String qrScanner = 'qr_scanner';
  static const String calendar = 'calendar';
  static const String analyticsDashboard = 'analytics_dashboard';

  // Auth/Splash screens (these should not be restored)
  static const String splash = 'splash';
  static const String secondSplash = 'second_splash';
  static const String login = 'login';
  static const String authGate = 'auth_gate';

  /// Check if a route should be persisted for restoration
  static bool shouldPersistRoute(String routeName) {
    // Don't persist auth, splash, or login screens
    const excludedRoutes = [splash, secondSplash, login, authGate];
    return !excludedRoutes.contains(routeName);
  }

  /// Get the appropriate dashboard tab index for a route
  static int? getDashboardTabForRoute(String routeName) {
    switch (routeName) {
      case homeHub:
      case search:
      case calendar:
      case qrScanner:
        return 0; // Home tab
      case groups:
      case groupProfile:
      case groupAnalytics:
      case manageGroups:
      case singleEvent:
      case createEvent:
      case editEvent:
        return 1; // Groups tab
      case messaging:
      case chatScreen:
      case newMessage:
        return 2; // Messages tab
      case myProfile:
      case userProfile:
      case myTickets:
        return 3; // Profile tab
      case notifications:
      case account:
      case analyticsDashboard:
      case premiumFeatures:
      case premiumUpgrade:
        return 4; // Account tab
      default:
        return null;
    }
  }

  /// Normalize historical dashboard tab indexes to the current 5-tab shell.
  ///
  /// Older code used index 5 for notifications/account-adjacent screens. The
  /// modern shell keeps notifications in the top bar, so that legacy index now
  /// lands on Account.
  static int normalizeDashboardTabIndex(int index) {
    if (index < homeTab) return homeTab;
    if (index >= legacyNotificationsTab) return accountTab;
    if (index > accountTab) return accountTab;
    return index;
  }
}
