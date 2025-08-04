# Dwell Time Tracking Feature

## Overview
The dwell time tracking feature allows event organizers to automatically measure how long attendees spend at their events using location-based tracking.

## Features

### Core Functionality
- **Geofence Entry Detection**: Automatically detects when users enter the event venue (200ft radius)
- **Exit Monitoring**: Tracks when users leave the venue with a 15-minute grace period
- **Duration Calculation**: Calculates total time spent at the event
- **Auto-Stop**: Automatically stops tracking when the event ends (event duration + 1 hour buffer)
- **Manual Check-Out**: Users can manually stop tracking with a "Check Out" button

### Privacy & Battery Optimization
- **Privacy Opt-in Dialog**: Users must explicitly consent to location tracking
- **5-Minute Location Updates**: Optimized for battery life
- **10-Hour Maximum**: Caps dwell time at 10 hours maximum
- **Data Visibility**: Only event organizers can see dwell time data

### UI Components
- **Dwell Tracking Section**: Shows in SingleEventScreen for signed-in users
- **Status Display**: Shows active tracking, completed tracking, or enable option
- **Attendance Sheet Integration**: Displays dwell time next to attendee names
- **Excel Export**: Includes dwell time data in attendance exports

## Technical Implementation

### Models Updated
- **AttendanceModel**: Added dwell time fields (entryTimestamp, exitTimestamp, dwellTime, dwellStatus, dwellNotes)
- **EventModel**: Added eventDuration field for event length in hours

### New Components
- **DwellTimeTracker**: Core tracking logic with location monitoring and geofence detection
- **Privacy Dialog**: User consent interface for location tracking
- **Dwell UI**: Status display and controls in SingleEventScreen

### Key Methods
- `startDwellTracking()`: Initiates location monitoring and tracking
- `stopDwellTracking()`: Manually stops tracking
- `_handleLocationUpdate()`: Processes location updates and geofence status
- `_updateAttendanceExit()`: Calculates and saves dwell time to Firestore

## Usage Flow

1. **User Signs In**: When user signs in to an event with location enabled
2. **Privacy Dialog**: User sees privacy opt-in dialog explaining tracking
3. **Tracking Starts**: If user consents, location monitoring begins
4. **Geofence Monitoring**: System tracks entry/exit from 200ft radius
5. **Grace Period**: 15-minute grace period for brief absences
6. **Auto-Stop**: Tracking stops automatically at event end + 1 hour
7. **Manual Stop**: Users can manually check out anytime
8. **Data Display**: Dwell time shown in attendance sheet and exports

## Configuration

### Event Setup
- Events can enable location tracking via `getLocation` field
- Event duration set via `eventDuration` field (default: 2 hours)
- Geofence radius configurable (default: 200 feet)

### Tracking Parameters
- **Exit Threshold**: 200 feet from event location
- **Grace Period**: 15 minutes for brief absences
- **Location Updates**: Every 5 minutes for battery optimization
- **Max Dwell Time**: 10 hours maximum
- **Auto-Stop Buffer**: Event end + 1 hour

## Data Structure

### AttendanceModel Dwell Fields
```dart
DateTime? entryTimestamp;     // When user entered geofence
DateTime? exitTimestamp;      // When user exited (confirmed)
Duration? dwellTime;          // Calculated total dwell time
String? dwellStatus;          // 'active', 'completed', 'auto-stopped', 'manual-stopped'
String? dwellNotes;           // Notes like 'Auto-stopped', 'Manual check-out'
```

### EventModel Duration Field
```dart
int eventDuration;            // Event duration in hours (default: 2)
DateTime get eventEndTime;    // Calculated event end time
DateTime get dwellTrackingEndTime; // Event end + 1 hour buffer
```

## Privacy Considerations

- **Explicit Consent**: Users must opt-in to location tracking
- **Limited Data**: Only tracks entry/exit times and total duration
- **Organizer Access**: Only event organizers can view dwell data
- **Auto-Cleanup**: Tracking stops automatically at event end
- **Manual Control**: Users can stop tracking anytime

## Battery Optimization

- **5-Minute Updates**: Location updates every 5 minutes
- **Distance Filter**: Only updates when user moves 10+ meters
- **High Accuracy**: Uses high accuracy mode for precise geofence detection
- **Graceful Degradation**: Handles location permission denials gracefully

## Future Enhancements

- **Real-time Updates**: Live dwell time display during events
- **Analytics Dashboard**: Dwell time analytics for organizers
- **Custom Geofences**: Configurable geofence sizes per event
- **Batch Processing**: Optimized for large events
- **Offline Support**: Local tracking when network unavailable 