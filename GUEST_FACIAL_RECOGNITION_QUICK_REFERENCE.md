# Guest Facial Recognition - Quick Reference

## For Developers

### Check if Facial Recognition is for a Guest

```dart
// In FaceEnrollmentScreen
final isGuest = widget.guestUserId != null;

// In FaceRecognitionScannerScreen  
final isGuest = widget.guestUserId != null;
```

### Navigate to Face Enrollment (Guest)

```dart
// Generate unique guest ID
final guestId = 'guest_${DateTime.now().millisecondsSinceEpoch}';

// Navigate with guest parameters
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => FaceEnrollmentScreen(
      eventModel: event,
      guestUserId: guestId,
      guestUserName: guestName,
    ),
  ),
);
```

### Navigate to Face Scanner (Guest)

```dart
Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (context) => FaceRecognitionScannerScreen(
      eventModel: event,
      guestUserId: guestId,
      guestUserName: guestName,
    ),
  ),
);
```

### Guest Name Input Dialog

```dart
// Shows name input dialog for guests
final guestName = await _showGuestNameInputDialog();

if (guestName == null || guestName.trim().isEmpty) {
  ShowToast().showNormalToast(msg: 'Name is required for guest sign-in');
  return;
}
```

## User Flow

### Guest Experience

```
1. Tap "Location & Facial Recognition" button
2. Location verified (within geofence)
3. Name input dialog appears
4. Enter name: "John Smith"
5. Tap "Continue"
6. Confirmation dialog shows
7. Tap "Start Verification"
8. Face enrollment begins (5 samples)
9. Progress: 1/5, 2/5, 3/5, 4/5, 5/5
10. "Enrollment successful!"
11. Navigate to scanner screen
12. Face detected and matched
13. Attendance created
14. Success message shown
15. Navigate to event details
```

### Logged-In User Experience

```
1. Tap "Location & Facial Recognition" button
2. Location verified (within geofence)
3. (No name input - uses account name)
4. Check if enrolled for this event
5. If not enrolled:
   - Show enrollment dialog
   - Navigate to enrollment screen
   - Enroll face (5 samples)
6. Navigate to scanner screen
7. Face detected and matched
8. Attendance created
9. Success message shown
10. Navigate to event details
```

## Key Differences: Guest vs User

| Feature | Guest | Logged-In User |
|---------|-------|----------------|
| Name Input | Required each time | Automatic from account |
| User ID | `guest_[timestamp]` | Account UID |
| Face Data | Event-specific | Account-linked |
| Subtitle | "(name required)" | "Automatic detection & biometric" |
| Privacy | Temporary, event-only | Persistent across events |
| Reusability | One event only | All events after enrollment |

## Attendance Records

### Guest Attendance
```javascript
{
  "id": "event_123-guest_1730053847293",
  "eventId": "event_123",
  "userName": "John Smith",           // Manually entered
  "customerUid": "guest_1730053847293", // Generated guest ID
  "attendanceDateTime": "2025-10-27T10:35:00Z",
  "signInMethod": "facial_recognition",
  "dwellNotes": "Facial recognition sign-in"
}
```

### User Attendance
```javascript
{
  "id": "event_123-user_abc123",
  "eventId": "event_123",
  "userName": "Jane Doe",             // From user account
  "customerUid": "user_abc123",       // User's account UID
  "attendanceDateTime": "2025-10-27T10:35:00Z",
  "signInMethod": "facial_recognition",
  "dwellNotes": "Facial recognition sign-in"
}
```

## Testing

### Test Guest Flow
```dart
// 1. Enable guest mode
await GuestModeService().enableGuestMode();

// 2. Navigate to sign-in screen
RouterClass.nextScreenNormal(context, const ModernSignInFlowScreen());

// 3. Verify "Location & Facial Recognition" is visible

// 4. Tap the method and complete flow

// 5. Verify attendance created with guest ID
```

### Test Name Input Validation
```dart
// Test empty name
final name1 = ''; // Should fail validation

// Test whitespace only  
final name2 = '   '; // Should fail validation

// Test valid name
final name3 = 'John Smith'; // Should pass
```

## Common Issues & Solutions

### Issue: Guest can't see facial recognition option
**Solution**: Check that guest mode restriction was removed in `_buildSignInMethods()`

### Issue: Name dialog doesn't appear
**Solution**: Verify `_showGuestNameInputDialog()` is called after location verification

### Issue: Enrollment fails for guest
**Solution**: Check that guest parameters are passed to `FaceEnrollmentScreen`

### Issue: Attendance not created
**Solution**: Verify guest ID and name are passed through to scanner screen

## Files Modified

1. `lib/screens/QRScanner/modern_sign_in_flow_screen.dart`
   - Removed `if (!isGuestMode)` restriction
   - Added guest name input dialog
   - Added guest facial recognition confirmation dialog

2. `lib/screens/FaceRecognition/face_enrollment_screen.dart`
   - Added `guestUserId` and `guestUserName` parameters
   - Updated enrollment logic to support guests

3. `lib/screens/FaceRecognition/face_recognition_scanner_screen.dart`
   - Added `guestUserId` and `guestUserName` parameters
   - Already supported custom userId/userName for attendance

## Documentation

- **Full Documentation**: `GUEST_FACIAL_RECOGNITION_IMPLEMENTATION.md`
- **Guest Mode Guide**: `GUEST_MODE_IMPLEMENTATION_SUMMARY.md`  
- **Quick Reference**: `GUEST_MODE_QUICK_REFERENCE.md`

## Support

For questions or issues:
1. Check full documentation
2. Review code examples above
3. Test with debug logs enabled
4. Verify all parameters are passed correctly

---

**Last Updated**: October 27, 2025  
**Version**: 1.0.0  
**Status**: Production Ready
