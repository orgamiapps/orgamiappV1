# Bottom Navigation Implementation Examples

This document shows specific examples of how the bottom navigation has been added to various screens in the app.

## 1. ChatScreen (Messages Tab)

**File**: `lib/screens/Messaging/chat_screen.dart`

```dart
// Added import
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

// Updated build method
@override
Widget build(BuildContext context) {
  return AppScaffoldWrapper(
    selectedBottomNavIndex: 2, // Messages tab
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      // ... rest of AppBar configuration
    ),
    body: Column(
      children: [
        Expanded(child: _buildMessageList()),
        _buildMessageInput(),
      ],
    ),
  );
}
```

## 2. UserProfileScreen (Profile Tab)

**File**: `lib/screens/MyProfile/user_profile_screen.dart`

```dart
// Added import
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

// Updated loading state
if (_isLoading) {
  return AppScaffoldWrapper(
    selectedBottomNavIndex: 3, // Profile tab
    backgroundColor: AppThemeColor.backGroundColor,
    body: SafeArea(
      child: Container(
        // ... loading UI
      ),
    ),
  );
}

// Updated main state
return AppScaffoldWrapper(
  selectedBottomNavIndex: 3, // Profile tab
  backgroundColor: const Color(0xFFFAFBFC),
  body: SafeArea(
    child: RefreshIndicator(
      // ... profile content
    ),
  ),
);
```

## 3. EventAnalyticsScreen (Groups Tab)

**File**: `lib/screens/Events/event_analytics_screen.dart`

```dart
// Added import
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

// Updated unauthorized state
if (!_isAuthorized) {
  return AppScaffoldWrapper(
    backgroundColor: AppThemeColor.backGroundColor,
    body: SafeArea(
      // ... unauthorized UI
    ),
  );
}

// Updated main state
return AppScaffoldWrapper(
  backgroundColor: AppThemeColor.backGroundColor,
  body: SafeArea(
    child: Column(
      children: [
        // ... analytics content
      ],
    ),
  ),
);
```

## 4. Updated DashboardScreen

**File**: `lib/screens/Home/dashboard_screen.dart`

The main dashboard now uses the reusable `AppBottomNavigation` widget:

```dart
// Added import
import 'package:attendus/widgets/app_bottom_navigation.dart';

class DashboardScreen extends StatefulWidget {
  final int initialIndex; // Added support for initial tab
  
  const DashboardScreen({super.key, this.initialIndex = 0});
}

// Updated to use new widget
bottomNavigationBar: AppBottomNavigation(
  selectedIndex: _selectedIndex,
  onDestinationSelected: (index) => setState(() {
    _selectedIndex = index;
  }),
  hasScrolledContent: _hasScrolledContent,
),
```

## Navigation Flow Examples

### From Chat to Groups Tab
When user taps "Groups" in bottom navigation from ChatScreen:
1. Navigates to DashboardScreen with `initialIndex: 1`
2. Groups tab becomes active
3. User sees GroupsScreen content

### From Event Details to Messages Tab
When user taps "Messages" in bottom navigation from SingleEventScreen:
1. Navigates to DashboardScreen with `initialIndex: 2`
2. Messages tab becomes active
3. User sees MessagingScreen content

## Screen Categories and Recommended Indices

### Home Tab (Index 0)
- HomeHubScreen ✓
- HomeScreen ✓
- SearchScreen → `selectedBottomNavIndex: 0`
- CalendarScreen → `selectedBottomNavIndex: 0`
- QRScannerFlowScreen → `selectedBottomNavIndex: 0`

### Groups Tab (Index 1)
- GroupsScreen ✓
- GroupProfileScreenV2 → `selectedBottomNavIndex: 1`
- SingleEventScreen → `selectedBottomNavIndex: 1`
- CreateEventScreen → `selectedBottomNavIndex: 1`
- EventAnalyticsScreen ✓
- TicketManagementScreen → `selectedBottomNavIndex: 1`

### Messages Tab (Index 2)
- MessagingScreen ✓
- ChatScreen ✓
- NewMessageScreen → `selectedBottomNavIndex: 2`

### Profile Tab (Index 3)
- MyProfileScreen ✓
- UserProfileScreen ✓
- FollowersFollowingScreen → `selectedBottomNavIndex: 3`
- MyTicketsScreen → `selectedBottomNavIndex: 3`

### Notifications Tab (Index 4)
- NotificationsScreen ✓

### Account Tab (Index 5)
- AccountScreen ✓
- AnalyticsDashboardScreen → `selectedBottomNavIndex: 5`
- BlockedUsersScreen → `selectedBottomNavIndex: 5`
- AttendeeNotificationScreen → `selectedBottomNavIndex: 5`

## Special Cases

### Screens Without Bottom Navigation
Some screens should not show bottom navigation:

```dart
AppScaffoldWrapper(
  showBottomNavigation: false, // Hide bottom navigation
  body: // ... screen content
)
```

Examples:
- SplashScreen
- LoginScreen
- CreateAccountScreen
- OnboardingScreens

### Screens With No Highlighted Tab
Some screens don't fit clearly into any category:

```dart
AppScaffoldWrapper(
  selectedBottomNavIndex: null, // No tab highlighted
  body: // ... screen content
)
```

## Migration Status

✅ **Completed Examples:**
- DashboardScreen (refactored to use new widget)
- ChatScreen (Messages tab)
- UserProfileScreen (Profile tab)
- EventAnalyticsScreen (Groups tab)

🔄 **Ready for Migration:**
All other screens can follow the same pattern by:
1. Adding the import
2. Replacing `Scaffold` with `AppScaffoldWrapper`
3. Adding appropriate `selectedBottomNavIndex`

The implementation is designed to be backward-compatible and easy to adopt gradually across the entire app.
