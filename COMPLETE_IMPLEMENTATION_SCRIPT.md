# Complete Bottom Navigation Implementation Script

This document provides the exact steps to add bottom navigation to all remaining screens in the Orgami app.

## ✅ Already Completed Screens

The following screens already have bottom navigation implemented:

- **Dashboard Screens**: DashboardScreen ✓
- **Home Screens**: SearchScreen ✓, CalendarScreen ✓, AnalyticsDashboardScreen ✓, AttendeeNotificationScreen ✓, BlockedUsersScreen ✓
- **Messaging Screens**: ChatScreen ✓, NewMessageScreen ✓
- **Profile Screens**: UserProfileScreen ✓, FollowersFollowingScreen ✓
- **Events Screens**: EventAnalyticsScreen ✓

## 🔄 Remaining Screens to Update

### Home Screens
```dart
// lib/screens/Home/account_details_screen.dart
// lib/screens/Home/delete_account_screen.dart
// lib/screens/Home/home_screen.dart
// lib/screens/Home/notification_settings_screen.dart
// lib/screens/Home/test_connectivity_screen.dart
```

### Event Screens  
```dart
// lib/screens/Events/single_event_screen.dart (PRIORITY - most used)
// lib/screens/Events/create_event_screen.dart
// lib/screens/Events/edit_event_screen.dart
// lib/screens/Events/all_attendees_screen.dart
// lib/screens/Events/ticket_management_screen.dart
// lib/screens/Events/ticket_scanner_screen.dart
// lib/screens/Events/event_feedback_screen.dart
// lib/screens/Events/event_feedback_management_screen.dart
// lib/screens/Events/feature_event_screen.dart
// lib/screens/Events/select_group_screen.dart
// lib/screens/Events/location_picker_screen.dart
// lib/screens/Events/event_location_view_screen.dart
// lib/screens/Events/geofence_setup_screen.dart
// lib/screens/Events/chose_sign_in_methods_screen.dart
// lib/screens/Events/chose_location_in_map_screen.dart
// lib/screens/Events/add_questions_prompt_screen.dart
// lib/screens/Events/add_questions_to_event_screen.dart
// lib/screens/Events/ticket_revenue_screen.dart
// lib/screens/Events/Attendance/attendance_sheet_screen.dart
```

### Group Screens
```dart
// lib/screens/Groups/groups_list_screen.dart
// lib/screens/Groups/create_group_screen.dart
// lib/screens/Groups/edit_group_details_screen.dart
// lib/screens/Groups/manage_members_screen.dart
// lib/screens/Groups/join_requests_screen.dart
// lib/screens/Groups/role_permissions_screen.dart
// lib/screens/Groups/group_admin_settings_screen.dart
// lib/screens/Groups/manage_feed_posts_screen.dart
// lib/screens/Groups/create_announcement_screen.dart
// lib/screens/Groups/create_photo_post_screen.dart
// lib/screens/Groups/create_poll_screen.dart
```

### Profile Screens
```dart
// lib/screens/MyProfile/my_tickets_screen.dart
```

### QR Scanner Screens
```dart
// lib/screens/QRScanner/qr_scanner_flow_screen.dart
// lib/screens/QRScanner/modern_qr_scanner_screen.dart
// lib/screens/QRScanner/qr_code_generator_screen.dart
// lib/screens/QRScanner/ans_questions_to_sign_in_event_screen.dart
// lib/screens/QRScanner/qr_scanner_screen.dart
// Note: qr_scanner_without_login_screen.dart should NOT have bottom nav (pre-login)
```

### Feedback Screens
```dart
// lib/screens/Feedback/feedback_screen.dart
```

## 📝 Implementation Template

For each screen, follow this exact pattern:

### Step 1: Add Import
```dart
import 'package:attendus/widgets/app_scaffold_wrapper.dart';
```

### Step 2: Replace Scaffold
**Before:**
```dart
return Scaffold(
  // existing parameters
);
```

**After:**
```dart
return AppScaffoldWrapper(
  selectedBottomNavIndex: [INDEX], // See table below
  // existing parameters (appBar, body, etc.)
);
```

### Step 3: Choose Correct Index

| Screen Type | Index | Tab |
|-------------|-------|-----|
| Home, Search, Calendar, QR Scanner | 0 | Home |
| Events, Groups, Organizations | 1 | Groups |  
| Messages, Chat | 2 | Messages |
| Profile, User, Tickets | 3 | Profile |
| Notifications | 4 | Notifications |
| Account, Settings, Analytics | 5 | Account |
| Login, Splash, Onboarding | null or showBottomNavigation: false | None |

## 🎯 Priority Implementation Order

### Phase 1: High-Impact Screens (Update First)
1. **SingleEventScreen** - Most frequently used
2. **CreateEventScreen** - Core functionality
3. **TicketManagementScreen** - Important for organizers
4. **MyTicketsScreen** - Important for attendees

### Phase 2: Group Management Screens
1. **CreateGroupScreen**
2. **ManageMembersScreen** 
3. **GroupsListScreen**

### Phase 3: Remaining Screens
- All other event screens
- QR scanner screens
- Settings screens

## 📋 Specific Implementation Examples

### SingleEventScreen (Groups Tab - Index 1)
```dart
// Add import
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

// Find the build method and replace Scaffold
@override
Widget build(BuildContext context) {
  return AppScaffoldWrapper(
    selectedBottomNavIndex: 1, // Groups tab
    // ... rest of existing Scaffold parameters
  );
}
```

### CreateEventScreen (Groups Tab - Index 1)  
```dart
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

return AppScaffoldWrapper(
  selectedBottomNavIndex: 1, // Groups tab
  appBar: AppBar(title: Text('Create Event')),
  body: // existing body
);
```

### MyTicketsScreen (Profile Tab - Index 3)
```dart
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

return AppScaffoldWrapper(
  selectedBottomNavIndex: 3, // Profile tab
  backgroundColor: const Color(0xFFFAFBFC),
  body: // existing body  
);
```

### QRScannerFlowScreen (Home Tab - Index 0)
```dart
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

return AppScaffoldWrapper(
  selectedBottomNavIndex: 0, // Home tab
  body: // existing body
);
```

## 🚫 Screens That Should NOT Have Bottom Navigation

These screens should either use `showBottomNavigation: false` or remain as regular Scaffold:

- **lib/screens/Splash/splash_screen.dart**
- **lib/screens/Splash/second_splash_screen.dart**  
- **lib/screens/Authentication/login_screen.dart**
- **lib/screens/Authentication/create_account/create_account_screen.dart**
- **lib/screens/Authentication/forgot_password_screen.dart**
- **lib/screens/QRScanner/qr_scanner_without_login_screen.dart**

## ✅ Verification Checklist

For each updated screen, verify:

- [ ] Import added: `import 'package:attendus/widgets/app_scaffold_wrapper.dart';`
- [ ] Scaffold replaced with AppScaffoldWrapper
- [ ] Correct selectedBottomNavIndex chosen
- [ ] All existing Scaffold parameters preserved
- [ ] Screen compiles without errors
- [ ] Bottom navigation appears and functions correctly
- [ ] Correct tab is highlighted when navigating to screen

## 🔧 Troubleshooting Common Issues

**Issue**: Bottom navigation doesn't appear
**Solution**: Ensure `showBottomNavigation` is not set to false

**Issue**: Wrong tab highlighted  
**Solution**: Check selectedBottomNavIndex value (0-5)

**Issue**: Compilation errors
**Solution**: Ensure import is added and all existing parameters are preserved

**Issue**: Navigation doesn't work
**Solution**: Verify AppScaffoldWrapper is used instead of Scaffold

## 📈 Implementation Progress Tracking

Create a checklist to track progress:

```
Home Screens:
☐ account_details_screen.dart
☐ delete_account_screen.dart  
☐ home_screen.dart
☐ notification_settings_screen.dart
☐ test_connectivity_screen.dart

Event Screens:
☐ single_event_screen.dart (PRIORITY)
☐ create_event_screen.dart (PRIORITY)
☐ edit_event_screen.dart
☐ all_attendees_screen.dart
☐ ticket_management_screen.dart (PRIORITY)
... (continue for all screens)
```

This systematic approach ensures consistent implementation across the entire app while maintaining code quality and user experience.