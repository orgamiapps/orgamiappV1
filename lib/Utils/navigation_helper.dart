/// Navigation helper utilities for consistent bottom navigation across the app
class NavigationHelper {
  // Bottom navigation tab indices
  static const int homeTabIndex = 0;
  static const int groupsTabIndex = 1;
  static const int messagesTabIndex = 2;
  static const int profileTabIndex = 3;
  static const int notificationsTabIndex = 4;
  static const int accountTabIndex = 5;

  /// Get the appropriate bottom navigation index based on screen context
  /// 
  /// Use this when you want the bottom navigation to highlight the most
  /// relevant tab for the current screen context.
  /// 
  /// For screens that don't have a clear association, use null to show
  /// no tab as selected.
  static int? getBottomNavIndexForScreen(String screenType) {
    switch (screenType.toLowerCase()) {
      // Home-related screens
      case 'home':
      case 'dashboard':
      case 'search':
      case 'calendar':
      case 'qr_scanner':
        return homeTabIndex;
      
      // Group/Organization-related screens
      case 'groups':
      case 'group_profile':
      case 'organization':
      case 'create_event':
      case 'event':
      case 'single_event':
      case 'event_analytics':
      case 'ticket_management':
      case 'attendee_management':
        return groupsTabIndex;
      
      // Messaging-related screens
      case 'messages':
      case 'messaging':
      case 'chat':
      case 'new_message':
        return messagesTabIndex;
      
      // Profile-related screens
      case 'profile':
      case 'my_profile':
      case 'user_profile':
      case 'followers':
      case 'following':
      case 'my_tickets':
        return profileTabIndex;
      
      // Notification-related screens
      case 'notifications':
      case 'notification_settings':
        return notificationsTabIndex;
      
      // Account/Settings-related screens
      case 'account':
      case 'settings':
      case 'analytics_dashboard':
      case 'blocked_users':
      case 'about':
        return accountTabIndex;
      
      // Screens with no clear association
      default:
        return null;
    }
  }

  /// Tab labels for reference
  static const List<String> tabLabels = [
    'Home',      // 0
    'Groups',    // 1  
    'Messages',  // 2
    'Profile',   // 3
    'Alerts',    // 4
    'Account',   // 5
  ];
}