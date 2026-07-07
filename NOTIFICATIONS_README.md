# Push Notifications Implementation

This document describes the push notification system implemented in the Orgami app using Firebase Cloud Messaging (FCM).

## Features Implemented

### 1. Notification Types
- **Event Reminders**: Notifications sent before events start (customizable timing)
- **New Events**: Notifications about new events in the user's area
- **Ticket Updates**: Updates about user's tickets and registrations
- **General Notifications**: Other app notifications and updates

### 2. Notification Settings
Users can customize their notification preferences:
- Enable/disable different notification types
- Set reminder time (15 minutes, 30 minutes, 1 hour, 2 hours, 1 day)
- Toggle sound and vibration
- Manage notification permissions

### 3. Notification Screen
- View all notifications with read/unread status
- Mark notifications as read
- Delete notifications
- Access notification settings

## Technical Implementation

### Dependencies Added
```yaml
firebase_messaging: ^15.1.3
flutter_local_notifications: ^17.2.2
timezone: ^0.9.4
```

### Files Created/Modified

#### New Files:
- `lib/Models/NotificationModel.dart` - Notification data models
- `lib/Firebase/FirebaseMessagingHelper.dart` - Firebase Messaging integration
- `lib/Screens/Home/NotificationsScreen.dart` - Notifications UI
- `lib/Services/NotificationService.dart` - Local notification service

#### Modified Files:
- `lib/Screens/Home/DashboardScreen.dart` - Added notifications tab
- `lib/main.dart` - Initialize messaging services
- `android/app/src/main/AndroidManifest.xml` - Added notification permissions
- `ios/Runner/Info.plist` - Added background modes
- `functions/index.js` - Added Cloud Functions for scheduled notifications

### Firebase Cloud Functions

#### 1. Scheduled Notifications (`sendScheduledNotifications`)
- Runs every minute
- Checks for notifications due to be sent
- Sends push notifications to users
- Marks notifications as sent
- Saves to user's notification history

#### 2. Event Reminders (`sendEventReminders`)
- Triggered when new events are created
- Schedules reminders based on user preferences
- Respects user notification settings

## Setup Instructions

### 1. Firebase Console Setup
1. Enable Firebase Cloud Messaging in your Firebase project
2. Add your app's SHA-1 fingerprint to Firebase Console
3. Download updated `google-services.json` and `GoogleService-Info.plist`

### 2. Deploy Cloud Functions
```bash
cd functions
npm install
firebase deploy --only functions
```

### 3. Configure Notification Channels
The app automatically creates notification channels for Android:
- Channel ID: `orgami_channel`
- Name: "Orgami Notifications"
- Description: "Notifications for Orgami events and updates"

### 4. Test Notifications
1. Run the app
2. Navigate to the Notifications tab
3. Configure notification settings
4. Create an event to test event reminders

## Usage

### For Users:
1. **Access Notifications**: Tap the notifications icon in the bottom navigation
2. **Configure Settings**: Scroll down to "Notification Settings"
3. **Manage Notifications**: Tap on notifications to mark as read or delete

### For Developers:
1. **Send Test Notification**:
```dart
await FirebaseMessagingHelper().sendEventReminder(
  eventId: 'event_id',
  eventTitle: 'Event Title',
  eventTime: DateTime.now().add(Duration(hours: 1)),
);
```

2. **Subscribe to Topics**:
```dart
await FirebaseMessagingHelper().subscribeToTopic('new_events');
```

3. **Check Notification Settings**:
```dart
final settings = FirebaseMessagingHelper().settings;
if (settings?.eventReminders == true) {
  // Send event reminder
}
```

## Notification Flow

1. **Event Creation**: When an event is created, the Cloud Function schedules reminders
2. **Scheduled Check**: Every minute, the Cloud Function checks for due notifications
3. **Push Delivery**: Notifications are sent via FCM to user devices
4. **Local Display**: App displays notifications using local notification service
5. **User Interaction**: Users can tap notifications to navigate to relevant screens

## Security Considerations

- FCM tokens are stored securely in Firestore
- User notification preferences are protected by Firestore security rules
- Notifications respect user privacy settings
- Failed notifications are logged for debugging

## Troubleshooting

### Common Issues:
1. **Notifications not showing**: Check notification permissions in device settings
2. **FCM token not updating**: Ensure Firebase is properly initialized
3. **Cloud Functions not working**: Check Firebase project configuration
4. **iOS notifications**: Verify APNs certificate in Firebase Console

### Debug Commands:
```bash
# Check FCM token
flutter logs | grep "FCM token"

# Test Cloud Functions
firebase functions:log

# Verify notification settings
flutter logs | grep "Notification settings"
```

## Future Enhancements

1. **Rich Notifications**: Add images and action buttons
2. **Notification Groups**: Group related notifications
3. **Advanced Scheduling**: More granular reminder options
4. **Analytics**: Track notification engagement
5. **A/B Testing**: Test different notification content

## Support

For issues with the notification system:
1. Check Firebase Console logs
2. Verify device notification permissions
3. Test with different notification types
4. Review Cloud Function logs 