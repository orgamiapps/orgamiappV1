# Guest Mode - Quick Reference Guide

## Quick Start for Developers

### Check if User is in Guest Mode
```dart
import 'package:attendus/Services/guest_mode_service.dart';

final isGuestMode = GuestModeService().isGuestMode;
```

### Check if Feature is Available
```dart
import 'package:attendus/Services/guest_mode_service.dart';

if (GuestModeService().isFeatureAvailable(GuestFeature.createEvent)) {
  // Allow action
  _createEvent();
} else {
  // Show restriction dialog
  _showGuestRestrictionDialog();
}
```

### Show Restriction Dialog (Copy-Paste Ready)
```dart
void _showGuestRestrictionDialog(GuestFeature feature) {
  final message = GuestModeService().getFeatureRestrictionMessage(feature);

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.lock_outline,
              color: Color(0xFF667EEA),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Account Required',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 15, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Maybe Later'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            RouterClass.nextScreenNormal(
              context,
              const CreateAccountScreen(),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF667EEA),
            foregroundColor: Colors.white,
          ),
          child: const Text('Create Account'),
        ),
      ],
    ),
  );
}
```

### Conditional UI Rendering
```dart
// Hide feature for guests
if (!GuestModeService().isGuestMode) {
  _buildPrivateFeature();
}

// Show different UI for guests
final buttonText = GuestModeService().isGuestMode
    ? 'Sign Up to Create Events'
    : 'Create Event';
```

### Enable/Disable Guest Mode
```dart
// Enable guest mode (e.g., on "Continue as Guest" tap)
await GuestModeService().enableGuestMode();

// Disable guest mode (automatically done on login/signup)
await GuestModeService().disableGuestMode();
```

## Available Features Enum

```dart
enum GuestFeature {
  // ✅ AVAILABLE in guest mode
  viewEvents,
  searchEvents,
  viewGlobalMap,
  viewCalendar,
  eventSignIn,
  
  // ❌ RESTRICTED in guest mode
  createEvent,
  createGroup,
  editProfile,
  viewMyGroups,
  viewMyEvents,
  analytics,
}
```

## Common Patterns

### Pattern 1: Hide Feature Completely
```dart
if (!GuestModeService().isGuestMode) {
  // Show feature only to logged-in users
  _buildAdvancedFeature();
}
```

### Pattern 2: Show with Restriction
```dart
ElevatedButton(
  onPressed: () {
    if (GuestModeService().isGuestMode) {
      _showGuestRestrictionDialog(GuestFeature.createEvent);
    } else {
      _createEvent();
    }
  },
  child: const Text('Create Event'),
)
```

### Pattern 3: Conditional Navigation
```dart
void _navigateToFeature() {
  if (GuestModeService().isGuestMode) {
    ShowToast().showNormalToast(
      msg: 'Please create an account to access this feature',
    );
    RouterClass.nextScreenNormal(
      context,
      const CreateAccountScreen(),
    );
  } else {
    RouterClass.nextScreenNormal(
      context,
      const FeatureScreen(),
    );
  }
}
```

### Pattern 4: Different UI States
```dart
Widget build(BuildContext context) {
  final isGuestMode = GuestModeService().isGuestMode;
  
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: isGuestMode
            ? [Color(0xFF10B981), Color(0xFF059669)] // Green for guests
            : [Color(0xFF667EEA), Color(0xFF764BA2)], // Purple for users
      ),
    ),
    child: Text(
      isGuestMode
          ? 'Browsing as Guest'
          : 'Welcome, ${user.name}!',
    ),
  );
}
```

## Files Modified

### Core Files
- `lib/Services/guest_mode_service.dart` - Guest mode service (NEW)
- `lib/Services/auth_service.dart` - Auto-disable guest mode on login
- `lib/screens/Splash/second_splash_screen.dart` - "Continue as Guest" button
- `lib/screens/Home/home_hub_screen.dart` - Guest banner & restrictions
- `lib/screens/QRScanner/modern_sign_in_flow_screen.dart` - Guest sign-in flow

### What Changed
1. ✅ Replaced "Quick Sign-In" with "Continue as Guest"
2. ✅ Added guest mode state management
3. ✅ Added guest banner with account creation CTA
4. ✅ Hide private tab for guests
5. ✅ Restrict event creation for guests
6. ✅ Hide facial recognition for guests
7. ✅ Require name input for guest sign-ins
8. ✅ Show restriction dialogs on locked features
9. ✅ Auto-disable guest mode on login/signup

## Color Scheme

| Element | Color | Hex | Usage |
|---------|-------|-----|-------|
| Guest Primary | Emerald | #10B981 | Guest banner, guest welcome |
| Guest Secondary | Dark Emerald | #059669 | Gradient end |
| User Primary | Purple | #667EEA | Normal user UI |
| User Secondary | Dark Purple | #764BA2 | Gradient end |
| Restriction | Purple | #667EEA | Lock icons, dialogs |
| Success | Green | #10B981 | Benefits, checkmarks |

## Testing Commands

```dart
// Print guest status
print('Guest Mode: ${GuestModeService().isGuestMode}');
print('Session ID: ${GuestModeService().guestSessionId}');

// Force enable guest mode (for testing)
await GuestModeService().enableGuestMode();

// Force disable guest mode (for testing)
await GuestModeService().disableGuestMode();

// Test feature availability
for (var feature in GuestFeature.values) {
  print('$feature: ${GuestModeService().isFeatureAvailable(feature)}');
}
```

## Common Issues & Solutions

### Issue: Guest mode doesn't enable
**Solution**: Check secure storage permissions, restart app

### Issue: Banner shows after login
**Solution**: Verify `disableGuestMode()` is called in `_saveUserSession()`

### Issue: Name field not showing
**Solution**: Check `CustomerController.logeInCustomer == null` logic

### Issue: Restriction dialog not showing
**Solution**: Import `guest_mode_service.dart`, check condition logic

## Documentation

- Full Documentation: `GUEST_MODE_IMPLEMENTATION_SUMMARY.md`
- Architecture: See "Technical Implementation" section
- UX Guidelines: See "UI/UX Design Patterns" section
- Testing: See "Testing Checklist" section

## Support

For questions or issues:
1. Check full documentation: `GUEST_MODE_IMPLEMENTATION_SUMMARY.md`
2. Review code examples in this guide
3. Test with debug commands above
4. Check logs for errors

---

**Last Updated**: October 27, 2025  
**Version**: 1.0.0  
**Status**: Production Ready

