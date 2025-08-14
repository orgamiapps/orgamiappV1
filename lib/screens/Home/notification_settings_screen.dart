import 'package:flutter/material.dart';
import 'package:orgami/firebase/firebase_messaging_helper.dart';
import 'package:orgami/models/notification_model.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:orgami/Services/notification_service.dart'; // Added import for NotificationService
import 'dart:convert'; // Added import for json

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final FirebaseMessagingHelper _messagingHelper = FirebaseMessagingHelper();
  UserNotificationSettings? _settings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _messagingHelper.getUserNotificationSettings();
      setState(() {
        _settings = settings;
      });
    } catch (e) {
      if (!mounted) return;
      ShowToast().showSnackBar('Error loading settings: $e', context);
    }
  }

  Future<void> _updateSettings(UserNotificationSettings newSettings) async {
    try {
      await _messagingHelper.updateNotificationSettings(newSettings);
      setState(() {
        _settings = newSettings;
      });
      if (!mounted) return;
      ShowToast().showSnackBar('Settings updated successfully', context);
    } catch (e) {
      if (!mounted) return;
      ShowToast().showSnackBar('Error updating settings: $e', context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notification Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _settings == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPermissionsCard(),
                  const SizedBox(height: 12),
                  _buildChannelsCard(),
                  const SizedBox(height: 12),
                  _buildBehaviorCard(),
                  const SizedBox(height: 12),
                  _buildActionsCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildPermissionsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_open, color: Color(0xFF667EEA)),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Permissions',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Control system-level permissions for notifications, including alerts, sound and badges.',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await _messagingHelper.requestPermissions();
                    if (!mounted) return;
                    ShowToast().showSnackBar(
                      'Status: ${result.authorizationStatus.name}',
                      context,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF667EEA),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.notifications_active),
                  label: const Text('Request Permission'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    // Open OS settings is not directly supported cross-platform; advise user
                    if (!mounted) return;
                    ShowToast().showSnackBar(
                      'To change system notification settings, open your device settings.',
                      context,
                    );
                  },
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('System Settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.tune, color: Color(0xFF667EEA)),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Notification Types',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _buildSettingSwitch(
              title: 'Event Reminders',
              subtitle:
                  'Get reminded before events start if you have a ticket or are the creator',
              value: _settings!.eventReminders,
              onChanged: (value) {
                _updateSettings(_settings!.copyWith(eventReminders: value));
              },
            ),
            const Divider(),
            _buildReminderTimeSetting(),
            const Divider(),
            _buildSettingSwitch(
              title: 'Event Changes',
              subtitle:
                  'Time, venue or agenda updates; cancellations and reschedules',
              value: _settings!.eventChanges,
              onChanged: (value) {
                _updateSettings(_settings!.copyWith(eventChanges: value));
              },
            ),
            const Divider(),
            _buildSettingSwitch(
              title: 'Geofenced Check-in',
              subtitle: 'Prompt check-in when you\'re near the venue close to start',
              value: _settings!.geofenceCheckIn,
              onChanged: (value) {
                _updateSettings(_settings!.copyWith(geofenceCheckIn: value));
              },
            ),
            const Divider(),
            _buildSettingSwitch(
              title: 'New Events',
              subtitle:
                  'Notifications about new events within ${_settings!.newEventsDistance} miles of your area',
              value: _settings!.newEvents,
              onChanged: (value) {
                _updateSettings(_settings!.copyWith(newEvents: value));
              },
            ),
            const Divider(),
            _buildNewEventsDistanceSetting(),
            const Divider(),
                        _buildSettingSwitch(
               title: 'Ticket Updates',
               subtitle: 'Get notified when you get a ticket or event details change',
               value: _settings!.ticketUpdates,
               onChanged: (value) {
                 _updateSettings(_settings!.copyWith(ticketUpdates: value));
               },
             ),
             const Divider(),
             _buildSettingSwitch(
               title: 'Event Feedback',
               subtitle: 'Get reminded to rate and comment on events you attended',
               value: _settings!.eventFeedback,
               onChanged: (value) {
                 _updateSettings(_settings!.copyWith(eventFeedback: value));
               },
             ),
             const Divider(),
             _buildSettingSwitch(
               title: 'Message Mentions',
               subtitle: 'Only @mentions and replies in chats',
               value: _settings!.messageMentions,
               onChanged: (value) {
                 _updateSettings(_settings!.copyWith(messageMentions: value));
               },
             ),
            const Divider(),
            _buildSettingSwitch(
              title: 'Organization Updates',
              subtitle:
                  'Join requests (admins), approvals/role changes (members)',
              value: _settings!.organizationUpdates,
              onChanged: (value) {
                _updateSettings(_settings!.copyWith(organizationUpdates: value));
              },
            ),
            const Divider(),
            _buildSettingSwitch(
              title: 'Organizer Feedback',
              subtitle: 'New ratings or comments on your events',
              value: _settings!.organizerFeedback,
              onChanged: (value) {
                _updateSettings(_settings!.copyWith(organizerFeedback: value));
              },
            ),
            const Divider(),
            _buildSettingSwitch(
              title: 'General Notifications',
              subtitle: 'Other app notifications and updates',
              value: _settings!.generalNotifications,
              onChanged: (value) {
                _updateSettings(
                  _settings!.copyWith(generalNotifications: value),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBehaviorCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      const Icon(Icons.volume_up_outlined, color: Color(0xFF667EEA)),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Behavior',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _buildSettingSwitch(
              title: 'Sound',
              subtitle: 'Play sound for notifications',
              value: _settings!.soundEnabled,
              onChanged: (value) {
                _updateSettings(_settings!.copyWith(soundEnabled: value));
              },
            ),
            const Divider(),
            _buildSettingSwitch(
              title: 'Vibration',
              subtitle: 'Vibrate for notifications',
              value: _settings!.vibrationEnabled,
              onChanged: (value) {
                _updateSettings(_settings!.copyWith(vibrationEnabled: value));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.build_outlined, color: Color(0xFF667EEA)),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Actions',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    // Quick test local notification
                    await NotificationService.showNotification(
                      title: 'Test Notification',
                      body: 'This is how notifications will look.',
                      payload: json.encode({'type': 'general'}),
                    );
                    if (!mounted) return;
                    ShowToast().showSnackBar('Test notification sent', context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF667EEA),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.notifications),
                  label: const Text('Send Test'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey[600], fontSize: 14),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF667EEA),
    );
  }

  Widget _buildReminderTimeSetting() {
    return ListTile(
      title: const Text(
        'Reminder Time',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Text(
        '$_settings!.reminderTime minutes before event',
        style: TextStyle(color: Colors.grey[600], fontSize: 14),
      ),
      trailing: DropdownButton<int>(
        value: _settings!.reminderTime,
        items: [15, 30, 60, 120, 1440].map((minutes) {
          String text;
          if (minutes < 60) {
            text = '$minutes minutes';
          } else if (minutes == 60) {
            text = '1 hour';
          } else if (minutes == 120) {
            text = '2 hours';
          } else if (minutes == 1440) {
            text = '1 day';
          } else {
            text = '${minutes ~/ 60} hours';
          }
          return DropdownMenuItem(value: minutes, child: Text(text));
        }).toList(),
        onChanged: (value) {
          if (value != null) {
            _updateSettings(_settings!.copyWith(reminderTime: value));
          }
        },
      ),
    );
  }

  Widget _buildNewEventsDistanceSetting() {
    return ListTile(
      title: const Text(
        'New Events Distance',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Text(
        '$_settings!.newEventsDistance miles radius',
        style: TextStyle(color: Colors.grey[600], fontSize: 14),
      ),
      trailing: DropdownButton<int>(
        value: _settings!.newEventsDistance,
        items: [5, 10, 15, 25, 50, 100].map((miles) {
          return DropdownMenuItem(value: miles, child: Text('$miles miles'));
        }).toList(),
        onChanged: (value) {
          if (value != null) {
            _updateSettings(_settings!.copyWith(newEventsDistance: value));
          }
        },
      ),
    );
  }
}
