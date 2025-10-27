# Geofence Facial Recognition Detection Fix

## Issue Summary
The Location & Facial Recognition sign-in method was displaying "No Events Nearby" even when users were within the geofence radius of active events.

## Root Cause
The `GeofenceEventDetector` service had an overly restrictive time window filter that prevented events from being detected:

### Original Behavior
- **Time Buffer**: 2 hours (before or after event time)
- **Logic**: Used absolute difference `eventTime.difference(now).abs()`
- **Problem**: Events that started more than 2 hours from the current time were filtered out, even if the user was within the geofence

### Example Scenario
If an event was scheduled for 3 hours from now:
- User is within the geofence radius ✓
- Event has geofence enabled ✓
- But event is 3 hours away (> 2 hour buffer) ✗
- **Result**: Event not detected ❌

## Solution Implemented

### Changes Made to `lib/Services/geofence_event_detector.dart`

1. **Increased Time Buffer**: Changed from 2 hours to 24 hours
   - Allows detection of events happening within the next day
   - More practical for real-world event attendance

2. **Improved Time Logic**: Split time checking into two conditions
   ```dart
   // Event must be either:
   // 1. Starting within the time buffer (24 hours by default)
   final isUpcoming = eventTime.isAfter(now) && 
       eventTime.difference(now) <= timeBufferDuration;
   
   // 2. Currently happening (between start time and end time)
   final isHappening = now.isAfter(eventTime) && now.isBefore(eventEndTime);
   ```

3. **Event Duration Support**: Added 12-hour default event duration
   - Assumes events can last up to 12 hours
   - Allows sign-in during the entire event period
   - Event end time: `eventTime.add(const Duration(hours: 12))`

### Updated Detection Logic Flow

```
1. Get user's current location ✓
2. Query all events with:
   - getLocation = true (geofence enabled)
   - status = 'active'
3. For each event, check:
   a. Is the event upcoming within 24 hours? OR
   b. Is the event currently happening?
   c. Does event have valid coordinates (lat/long ≠ 0)?
   d. Is user within geofence radius?
4. If all checks pass → Add to nearby events list ✓
5. Sort by distance (closest first)
6. Return nearby events
```

## Testing Checklist

### Scenario 1: Event Starting Soon
- [ ] Event scheduled for 30 minutes from now
- [ ] User within geofence radius
- [ ] **Expected**: Event detected ✓

### Scenario 2: Event Starting Later Today
- [ ] Event scheduled for 6 hours from now
- [ ] User within geofence radius
- [ ] **Expected**: Event detected ✓

### Scenario 3: Event Currently Happening
- [ ] Event started 2 hours ago
- [ ] User within geofence radius
- [ ] **Expected**: Event detected ✓

### Scenario 4: Event Ended
- [ ] Event ended 13+ hours ago
- [ ] User within geofence radius
- [ ] **Expected**: Event NOT detected (outside duration window)

### Scenario 5: User Outside Geofence
- [ ] Event currently happening
- [ ] User outside geofence radius
- [ ] **Expected**: Event NOT detected

### Scenario 6: Multiple Events
- [ ] Multiple events with geofence at same time
- [ ] User within radius of both
- [ ] **Expected**: Show event selection dialog with both events

## Benefits of the Fix

1. ✅ **More Flexible Detection**: 24-hour window vs 2-hour window
2. ✅ **Better Event Coverage**: Detects events throughout their duration
3. ✅ **Clearer Logic**: Separate checks for upcoming vs happening events
4. ✅ **Better Logging**: Added debug messages for time window filtering
5. ✅ **Realistic Assumptions**: 12-hour event duration covers most scenarios

## Technical Details

### Time Buffer Parameter
The time buffer can be customized when calling the method:
```dart
final nearbyEvents = await geofenceDetector.findNearbyGeofencedEvents(
  userPosition: position,
  timeBuffer: Duration(hours: 48), // Custom 48-hour window
);
```

Default: `Duration(hours: 24)`

### Distance Calculation
- Event radius stored in **feet** in database
- Converted to meters: `radiusInMeters = event.radius * 0.3048`
- User is within geofence if: `distance <= radiusInMeters`

### Location Requirements
Events must have:
- `getLocation = true` (geofence enabled in Firestore)
- `latitude ≠ 0` and `longitude ≠ 0` (valid coordinates)
- `status = 'active'` (event is active)

## Files Modified
- `lib/Services/geofence_event_detector.dart` (lines 37-73)

## Related Features
- Location & Facial Recognition sign-in flow
- `ModernSignInFlowScreen` (uses `GeofenceEventDetector`)
- `FaceRecognitionScannerScreen` (receives detected event)
- `FaceEnrollmentScreen` (facial recognition enrollment)

## Additional Notes

### Why 24 Hours?
- Most events are planned within a day of sign-in
- Allows early arrivals to events
- Balances between flexibility and relevance

### Why 12-Hour Duration?
- Covers most real-world events (conferences, parties, festivals)
- Can be made configurable in future if needed
- Long-running events (multi-day) may need alternative approach

### Event Status Field
Events with `status != 'active'` are automatically excluded by the Firestore query, regardless of geofence settings.

## Future Enhancements

1. **Configurable Event Duration**: Store actual event duration in database
2. **Advanced Time Windows**: Different buffers for different event types
3. **Geofence Zones**: Multiple check-in zones for large events
4. **Historical Sign-ins**: Allow late sign-ins for recently ended events

## Deployment Notes
- No database schema changes required
- No breaking changes to existing APIs
- Backward compatible with existing sign-in flows
- Existing facial recognition enrollments remain valid
