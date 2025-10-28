# Location & Facial Recognition Sign-In Fix

## Issue Description
The Location & Facial Recognition sign-in method was not detecting nearby events. The console logs showed:
```
I/flutter: 🔍 DEBUG: Found 0 events with geofence enabled
I/flutter: ℹ️ INFO: Found 0 nearby geofenced events
I/flutter: 🔍 DEBUG: User location: 26.3336028, -81.7750021
```

The app was successfully getting the user's location but finding no events with geofence enabled.

## Root Cause
The geofence event detection query in `geofence_event_detector.dart` had the following issues:

1. **Overly Restrictive Status Filter**: The query was filtering for `status == 'active'`, which may not match all events in the database (some events might have different status values like 'Active', 'ACTIVE', or other values).

2. **Insufficient Logging**: There was minimal logging to diagnose why events weren't being found.

3. **Fixed Event Duration**: The code assumed all events lasted 12 hours instead of using the actual `eventDuration` field from the EventModel.

## Changes Made

### 1. Removed Status Filter
**File**: `/workspace/lib/Services/geofence_event_detector.dart`

**Before**:
```dart
final eventsSnapshot = await FirebaseFirestore.instance
    .collection(EventModel.firebaseKey)
    .where('getLocation', isEqualTo: true)
    .where('status', isEqualTo: 'active')  // ❌ Too restrictive
    .get();
```

**After**:
```dart
// Query events with geofence enabled (removed status filter for better compatibility)
final eventsSnapshot = await FirebaseFirestore.instance
    .collection(EventModel.firebaseKey)
    .where('getLocation', isEqualTo: true)  // ✓ Only filter by geofence enabled
    .get();
```

### 2. Added Comprehensive Logging
Added detailed logging to help diagnose issues:

- **Log all found events** with their geofence settings:
```dart
for (final doc in eventsSnapshot.docs) {
  try {
    final data = doc.data();
    Logger.debug(
      'Event found: ${data['title']} | getLocation: ${data['getLocation']} | lat: ${data['latitude']} | lng: ${data['longitude']} | radius: ${data['radius']} | status: ${data['status']}',
    );
  } catch (e) {
    Logger.debug('Error logging event data: $e');
  }
}
```

- **Log distance calculations** for each event:
```dart
Logger.debug(
  'Event ${event.title}: distance=${distance.toStringAsFixed(1)}m, radius=${event.radius}ft (${(event.radius * 0.3048).toStringAsFixed(1)}m)',
);
```

- **Log geofence check results** with clear indicators:
```dart
if (distance <= radiusInMeters) {
  Logger.success(
    '✓ User is within geofence of event: ${event.title} (${distance.toStringAsFixed(1)}m away, within ${radiusInMeters.toStringAsFixed(1)}m radius)',
  );
} else {
  Logger.debug(
    '✗ User is outside geofence of event: ${event.title} (${distance.toStringAsFixed(1)}m away, needs to be within ${radiusInMeters.toStringAsFixed(1)}m)',
  );
}
```

### 3. Improved Event Duration Handling
**Before**:
```dart
final eventEndTime = eventTime.add(const Duration(hours: 12)); // ❌ Fixed 12 hours
```

**After**:
```dart
final eventEndTime = eventTime.add(Duration(hours: event.eventDuration)); // ✓ Use actual duration
```

### 4. Extended Event Time Window
Added a 1-hour buffer after event end time to allow late sign-ins:

**Before**:
```dart
final isHappening = now.isAfter(eventTime) && now.isBefore(eventEndTime);
```

**After**:
```dart
final isHappening = now.isAfter(eventTime) && 
    now.isBefore(eventEndTime.add(const Duration(hours: 1)));
```

### 5. Enhanced Warning Messages
Improved warning messages for better debugging:

```dart
if (event.latitude == 0 && event.longitude == 0) {
  Logger.warning('Event ${event.title} has no geofence coordinates (lat/lng = 0,0)');
  continue;
}
```

## Testing Instructions

### 1. Verify Events Have Geofence Enabled
In Firebase Console, check that your events have:
- `getLocation: true`
- Valid `latitude` and `longitude` values (not 0,0)
- A reasonable `radius` value in feet (e.g., 500-5000 feet)

### 2. Test the Sign-In Flow
1. Open the app and navigate to the event sign-in screen
2. Select "Location & Facial Recognition"
3. Monitor the console logs to see:
   - Events found with geofence enabled
   - Distance calculations for each event
   - Which events you're within/outside the geofence

### 3. Expected Console Output
You should now see detailed logs like:
```
I/flutter: 🔍 DEBUG: Found 3 events with geofence enabled
I/flutter: 🔍 DEBUG: Event found: Summer Festival | getLocation: true | lat: 26.3340 | lng: -81.7750 | radius: 1000 | status: active
I/flutter: 🔍 DEBUG: User location: 26.3336028, -81.7750021
I/flutter: 🔍 DEBUG: Event Summer Festival: distance=44.5m, radius=1000ft (304.8m)
I/flutter: ✓ User is within geofence of event: Summer Festival (44.5m away, within 304.8m radius)
I/flutter: ℹ️ INFO: Found 1 nearby geofenced events
```

## Common Issues & Solutions

### Issue 1: Still Finding 0 Events
**Cause**: Events don't have `getLocation` set to `true` in the database.

**Solution**: 
1. Go to Firebase Console → Firestore Database
2. Navigate to the Events collection
3. For each event you want to use with location sign-in, ensure:
   - `getLocation: true`
   - `latitude` and `longitude` are set to the event location coordinates
   - `radius` is set (default: 500-1000 feet is reasonable)

### Issue 2: Events Found But User Not Within Geofence
**Cause**: The user is too far from the event location or the radius is too small.

**Solution**:
1. Check the console logs for distance vs. radius
2. Increase the `radius` field in the event document (in feet)
3. Ensure the event's latitude/longitude coordinates are correct

### Issue 3: Events Outside Time Window
**Cause**: The event's `selectedDateTime` is not within the acceptable range.

**Solution**:
- Events are detected if they:
  - Start within the next 24 hours (upcoming), OR
  - Are currently happening (between start time and end time + 1 hour)
- Adjust the event's `selectedDateTime` to be within this window

## Architecture Notes

### Query Strategy
The fix removes the `status` filter to be more inclusive. This means the query will return all events with `getLocation: true` regardless of their status. The subsequent time-window filtering ensures only relevant events are shown to users.

### Performance Considerations
- The query now returns more events (without status filter)
- However, the filtering happens in-memory which is acceptable for typical event counts
- If your app has thousands of events with geofencing, consider adding composite indexes in Firebase

### Security Considerations
- Events must have `getLocation: true` to be detected
- User must be within the specified radius
- Event must be in the correct time window
- Facial recognition is still required after location verification

## Related Files
- `/workspace/lib/Services/geofence_event_detector.dart` - Main fix location
- `/workspace/lib/screens/QRScanner/modern_sign_in_flow_screen.dart` - Sign-in UI
- `/workspace/lib/models/event_model.dart` - Event data structure

## Next Steps
1. Test the fix with real events in your database
2. Monitor console logs to verify events are being detected
3. Adjust geofence radius as needed for your use cases
4. Consider creating a Firebase composite index if you have many events
