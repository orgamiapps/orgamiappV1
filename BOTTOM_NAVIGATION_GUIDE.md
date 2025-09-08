# Bottom Navigation Implementation Guide

This guide explains how to add the bottom navigation bar to any screen in the Orgami app.

## Overview

The app now supports a consistent bottom navigation bar across all screens, making it easier for users to navigate throughout the app regardless of which screen they're currently viewing.

## Quick Start

### Step 1: Import the Required Widget

Add this import to your screen file:

```dart
import 'package:attendus/widgets/app_scaffold_wrapper.dart';
```

### Step 2: Replace Scaffold with AppScaffoldWrapper

**Before:**
```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: Text('My Screen')),
    body: MyScreenContent(),
  );
}
```

**After:**
```dart
@override
Widget build(BuildContext context) {
  return AppScaffoldWrapper(
    selectedBottomNavIndex: 2, // Messages tab highlighted
    appBar: AppBar(title: Text('My Screen')),
    body: MyScreenContent(),
  );
}
```

### Step 3: Choose the Right Tab Index

Use the appropriate tab index based on your screen's context:

- `0` - Home (for home, search, calendar, QR scanner screens)
- `1` - Groups (for events, organizations, group-related screens)
- `2` - Messages (for chat, messaging screens)
- `3` - Profile (for profile, user-related screens)
- `4` - Notifications (for notification screens)
- `5` - Account (for settings, account screens)
- `null` - No tab highlighted (for screens with no clear association)

## Helper Utility

For convenience, you can use the `NavigationHelper` utility:

```dart
import 'package:attendus/Utils/navigation_helper.dart';

// In your build method:
selectedBottomNavIndex: NavigationHelper.getBottomNavIndexForScreen('chat'),
```

## AppScaffoldWrapper Parameters

The `AppScaffoldWrapper` supports all the same parameters as a regular `Scaffold`, plus:

- `selectedBottomNavIndex` (int?): Which tab to highlight (0-5, or null for none)
- `showBottomNavigation` (bool): Whether to show the bottom navigation (default: true)

### Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:attendus/widgets/app_scaffold_wrapper.dart';
import 'package:attendus/Utils/navigation_helper.dart';

class MyChatScreen extends StatefulWidget {
  @override
  Widget build(BuildContext context) {
    return AppScaffoldWrapper(
      selectedBottomNavIndex: NavigationHelper.messagesTabIndex,
      appBar: AppBar(
        title: Text('Chat'),
        backgroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(child: MessagesList()),
          MessageInput(),
        ],
      ),
    );
  }
}
```

## Screen Examples

### Chat Screen
```dart
selectedBottomNavIndex: NavigationHelper.messagesTabIndex, // or 2
```

### Event Details Screen
```dart
selectedBottomNavIndex: NavigationHelper.groupsTabIndex, // or 1
```

### User Profile Screen
```dart
selectedBottomNavIndex: NavigationHelper.profileTabIndex, // or 3
```

### Settings Screen
```dart
selectedBottomNavIndex: NavigationHelper.accountTabIndex, // or 5
```

### Login/Splash Screens (no bottom navigation)
```dart
showBottomNavigation: false,
```

## Navigation Behavior

When users tap on bottom navigation tabs:

1. **From main dashboard screens**: Switches between tabs within the dashboard
2. **From other screens**: Navigates back to the dashboard with the selected tab active

This ensures consistent navigation behavior throughout the app.

## Migration Checklist

To add bottom navigation to an existing screen:

- [ ] Import `AppScaffoldWrapper`
- [ ] Replace `Scaffold` with `AppScaffoldWrapper`
- [ ] Add appropriate `selectedBottomNavIndex`
- [ ] Test navigation behavior
- [ ] Verify the correct tab is highlighted

## Advanced Usage

### Conditional Bottom Navigation

```dart
AppScaffoldWrapper(
  showBottomNavigation: userIsLoggedIn && !isFullScreenMode,
  selectedBottomNavIndex: someCondition ? 2 : null,
  // ... other parameters
)
```

### Custom Background Color

```dart
AppScaffoldWrapper(
  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
  selectedBottomNavIndex: 1,
  // ... other parameters
)
```

## Benefits

1. **Consistent Navigation**: Users can navigate to any main section from any screen
2. **Better UX**: No need to go back to home to access other sections
3. **Easy Implementation**: Simple wrapper around existing Scaffold
4. **Flexible**: Works with all existing Scaffold parameters
5. **Automatic State Management**: Bottom navigation state is preserved correctly

## Troubleshooting

**Q: The bottom navigation doesn't show**
A: Make sure `showBottomNavigation` is not set to `false`

**Q: Wrong tab is highlighted**
A: Check that you're using the correct index (0-5) for your screen type

**Q: Navigation doesn't work**
A: Ensure you're using `AppScaffoldWrapper` instead of regular `Scaffold`

**Q: Bottom navigation conflicts with keyboard**
A: Use `resizeToAvoidBottomInset: true` parameter if needed