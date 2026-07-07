# Navigation State Restoration Implementation Guide

## Overview

This implementation adds full navigation state restoration to the Attendus app. When users switch to another app and return later, they will be taken back to the exact screen they were viewing, rather than resetting to the home screen.

## What Was Implemented

### 1. Core Infrastructure

#### Files Created:
- **`lib/Utils/route_names.dart`** - Route name constants for all major screens
- **`lib/models/route_config.dart`** - Models for serializing/deserializing navigation state
- **`lib/Services/navigation_state_service.dart`** - Service for persisting and restoring navigation state
- **`lib/Utils/route_builder.dart`** - Helper for rebuilding screens from saved configuration

#### Files Modified:
- **`lib/main.dart`** - Added app lifecycle monitoring and enhanced navigation observer
- **`lib/widgets/auth_gate.dart`** - Added navigation state restoration on app startup
- **`lib/screens/Home/dashboard_screen.dart`** - Added tab state persistence
- **`lib/Services/auth_service.dart`** - Clear navigation state on logout

### 2. How It Works

1. **State Tracking**: The `_NavigationLogger` in `main.dart` tracks every navigation event (push, pop, replace)
2. **State Persistence**: Navigation state is saved to `SharedPreferences` with:
   - Route name (e.g., "single_event", "group_profile")
   - Route parameters (e.g., eventId, organizationId)
   - Current bottom navigation tab index
   - Timestamp (for expiry validation)
3. **App Lifecycle**: `MyApp` monitors app lifecycle states (paused, resumed) via `WidgetsBindingObserver`
4. **State Restoration**: On app startup, `AuthGate` checks for valid saved state and rebuilds the screen
5. **Expiry**: Saved state expires after 30 minutes to prevent stale data

### 3. Supported Screens

The following screen types can be restored:

**Event Screens:**
- Single Event Screen (with event details)
- Edit Event Screen (with event details)
- Ticket Management Screen (with event details)
- Event Analytics Screen

**Group Screens:**
- Group Profile Screen
- Group Analytics Dashboard
- Manage Groups Screen
- Group Admin Settings
- Manage Members
- Manage Feed Posts
- Pending Events

**Messaging Screens:**
- Chat Screen (with conversation)
- New Message Screen

**Profile Screens:**
- User Profile Screen (with user details)
- My Tickets Screen

**Quiz Screens:**
- Quiz Builder Screen
- Quiz Host Screen
- Quiz Participant Screen

**Premium Screens:**
- Premium Features Screen
- Premium Upgrade Screen

**Other Screens:**
- Search Screen
- Analytics Dashboard Screen

**Bottom Navigation Tabs:**
- Home Hub (tab 0)
- Groups (tab 1)
- Messages (tab 2)
- My Profile (tab 3)
- Notifications (tab 4)
- Account (tab 5)

### 4. Edge Cases Handled

✅ **State older than 30 minutes** - Ignored, user goes to home
✅ **Saved event/group deleted** - Falls back to appropriate tab
✅ **App killed vs backgrounded** - Both restore properly
✅ **First app launch** - No saved state, goes to home
✅ **User logged out then back in** - Old state cleared
✅ **Deep links/notifications** - Override saved state
✅ **Modal/dialog routes** - Not persisted
✅ **Auth/splash screens** - Not persisted

## Testing Guide

### Test Case 1: Basic Tab Switching
1. Open the app
2. Navigate to Groups tab
3. Switch to another app (e.g., Settings)
4. Wait 5 seconds
5. Return to Attendus
6. ✅ **Expected**: App shows Groups tab (not Home tab)

### Test Case 2: Event Details Screen
1. Open the app
2. Navigate to an event (tap on any event)
3. Switch to another app
4. Wait 10 seconds
5. Return to Attendus
6. ✅ **Expected**: App shows the same event details screen

### Test Case 3: Deep Navigation Stack
1. Open the app
2. Navigate: Groups → Group Profile → Event Details
3. Switch to another app
4. Wait 10 seconds
5. Return to Attendus
6. ✅ **Expected**: App shows the event details screen (last screen)

### Test Case 4: State Expiry
1. Open the app
2. Navigate to any screen (e.g., Messages tab)
3. Force close the app
4. Wait 35 minutes (or modify expiry time in code for testing)
5. Open the app
6. ✅ **Expected**: App shows Home tab (state expired)

### Test Case 5: Logout Clears State
1. Open the app
2. Navigate to Profile tab
3. Switch to another app briefly
4. Return to app (should show Profile tab)
5. Go to Account → Logout
6. Login again
7. ✅ **Expected**: App shows Home tab (state was cleared)

### Test Case 6: App Killed
1. Open the app
2. Navigate to Notifications tab
3. Force close the app completely (swipe up in app switcher)
4. Reopen the app
5. ✅ **Expected**: App shows Notifications tab

### Test Case 7: Chat Screen
1. Open the app
2. Navigate to Messages → Open a chat
3. Switch to another app
4. Wait 5 seconds
5. Return to Attendus
6. ✅ **Expected**: App shows the same chat screen

### Test Case 8: Deleted Content
1. Open the app as User A
2. Navigate to an event created by User B
3. Switch to another app
4. User B deletes the event (use another device or ask someone)
5. Return to Attendus
6. ✅ **Expected**: App falls back to Groups tab (event not found)

## Debug Logging

The implementation includes comprehensive logging. To view logs:

### iOS:
```bash
# In Xcode, open Console app and filter by "Attendus" or "Navigation"
```

### Android:
```bash
# Use logcat
adb logcat | grep -i navigation
```

### Key Log Messages:
- `📱 DashboardScreen: Saved tab change to index X` - Tab switch saved
- `🔄 AuthGate: Attempting to restore navigation state` - Restoration attempt
- `✅ AuthGate: Successfully restored route: X` - Restoration success
- `🏠 AuthGate: Navigating to Dashboard (no restored state)` - No state to restore
- `App paused - navigation state should be saved` - App going to background

## Configuration

### Adjust State Expiry Time

Edit `lib/models/route_config.dart`:

```dart
// Change from 30 minutes to 1 hour
bool isValid({Duration maxAge = const Duration(hours: 1)}) {
  final age = DateTime.now().difference(timestamp);
  return age <= maxAge;
}
```

### Add New Screen Type

1. Add route name to `lib/Utils/route_names.dart`:
```dart
static const String myNewScreen = 'my_new_screen';
```

2. Add builder to `lib/Utils/route_builder.dart`:
```dart
case RouteNames.myNewScreen:
  return await _buildMyNewScreen(config);
```

3. Implement builder method:
```dart
static Future<Widget> _buildMyNewScreen(RouteConfig config) async {
  final param = config.parameters['paramName'] as String?;
  if (param != null) {
    return MyNewScreen(param: param);
  }
  return _getFallbackScreen(config);
}
```

### Disable for Specific Screens

Edit `lib/Utils/route_names.dart`:

```dart
static bool shouldPersistRoute(String routeName) {
  const excludedRoutes = [
    splash,
    secondSplash,
    login,
    authGate,
    myNewScreen, // Add your screen here
  ];
  return !excludedRoutes.contains(routeName);
}
```

## Performance Considerations

- State is saved asynchronously to avoid blocking the UI
- SharedPreferences is cached to reduce I/O operations
- Firestore fetches for screen restoration are minimal (1 document per screen)
- Failed restorations fall back gracefully to appropriate tabs
- No impact on app startup time (restoration happens in background)

## Troubleshooting

### Issue: State not restoring
**Check:**
1. Look for log message: `No valid navigation state to restore`
2. Verify state hasn't expired (< 30 minutes old)
3. Check if screen type is in supported list
4. Ensure route has a name set

### Issue: Wrong screen restored
**Check:**
1. Look for log: `Error fetching X: [error message]`
2. Verify the saved document still exists in Firestore
3. Check if parameters were saved correctly
4. Test with debug logging enabled

### Issue: App crashes on restoration
**Check:**
1. Review crash logs for the specific screen builder
2. Verify required parameters are available
3. Check if screen constructor matches builder
4. Add try-catch in specific builder if needed

## Future Enhancements

Potential improvements for future versions:

1. **Full Navigation Stack**: Currently saves only the last screen. Could save entire stack for nested navigation.
2. **Scroll Position**: Save and restore scroll position within screens
3. **Form State**: Restore partially filled forms (create event, etc.)
4. **Tab State**: Restore which tab was selected in multi-tab screens
5. **Filter State**: Restore applied filters in list screens

## Notes

- Navigation state is user-specific (cleared on logout)
- State is stored locally on device (not synced across devices)
- Deep links and push notifications override saved state
- Modal dialogs and bottom sheets are not persisted
- Authentication screens are never persisted
- State validity is checked on both save and restore

