import 'package:flutter/material.dart';
import 'package:orgami/Firebase/FirebaseMessagingHelper.dart';
import 'package:orgami/Models/NotificationModel.dart';
import 'package:orgami/Utils/Toast.dart';

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
      ShowToast().showSnackBar('Error loading settings: $e', context);
    }
  }

  Future<void> _updateSettings(UserNotificationSettings newSettings) async {
    try {
      await _messagingHelper.updateNotificationSettings(newSettings);
      setState(() {
        _settings = newSettings;
      });
      ShowToast().showSnackBar('Settings updated successfully', context);
    } catch (e) {
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
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildSettingSwitch(
                            title: 'Event Reminders',
                            subtitle:
                                'Get reminded before events start if you have a ticket or are the creator',
                            value: _settings!.eventReminders,
                            onChanged: (value) {
                              _updateSettings(
                                _settings!.copyWith(eventReminders: value),
                              );
                            },
                          ),
                          const Divider(),
                          _buildReminderTimeSetting(),
                          const Divider(),
                          _buildSettingSwitch(
                            title: 'New Events',
                            subtitle:
                                'Notifications about new events within ${_settings!.newEventsDistance} miles of your area',
                            value: _settings!.newEvents,
                            onChanged: (value) {
                              _updateSettings(
                                _settings!.copyWith(newEvents: value),
                              );
                            },
                          ),
                          const Divider(),
                          _buildNewEventsDistanceSetting(),
                          const Divider(),
                          _buildSettingSwitch(
                            title: 'Ticket Updates',
                            subtitle:
                                'Get notified when you get a ticket or event details change',
                            value: _settings!.ticketUpdates,
                            onChanged: (value) {
                              _updateSettings(
                                _settings!.copyWith(ticketUpdates: value),
                              );
                            },
                          ),
                          const Divider(),
                          _buildSettingSwitch(
                            title: 'General Notifications',
                            subtitle: 'Other app notifications and updates',
                            value: _settings!.generalNotifications,
                            onChanged: (value) {
                              _updateSettings(
                                _settings!.copyWith(
                                  generalNotifications: value,
                                ),
                              );
                            },
                          ),
                          const Divider(),
                          _buildSettingSwitch(
                            title: 'Sound',
                            subtitle: 'Play sound for notifications',
                            value: _settings!.soundEnabled,
                            onChanged: (value) {
                              _updateSettings(
                                _settings!.copyWith(soundEnabled: value),
                              );
                            },
                          ),
                          const Divider(),
                          _buildSettingSwitch(
                            title: 'Vibration',
                            subtitle: 'Vibrate for notifications',
                            value: _settings!.vibrationEnabled,
                            onChanged: (value) {
                              _updateSettings(
                                _settings!.copyWith(vibrationEnabled: value),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
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
        '${_settings!.reminderTime} minutes before event',
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
        '${_settings!.newEventsDistance} miles radius',
        style: TextStyle(color: Colors.grey[600], fontSize: 14),
      ),
      trailing: DropdownButton<int>(
        value: _settings!.newEventsDistance,
        items: [5, 10, 15, 25, 50, 100].map((miles) {
          return DropdownMenuItem(value: miles, child: Text('${miles} miles'));
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
