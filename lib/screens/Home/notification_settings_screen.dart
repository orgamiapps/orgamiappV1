import 'package:flutter/material.dart';
import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:attendus/models/notification_model.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseMessagingHelper _messagingHelper = FirebaseMessagingHelper();
  UserNotificationSettings? _settings;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _hasPermission = false;
  bool _permissionChecked = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _loadSettings();
    _checkPermissionStatus();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissionStatus() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    setState(() {
      _hasPermission =
          settings.authorizationStatus == AuthorizationStatus.authorized;
      _permissionChecked = true;
    });
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _messagingHelper.getUserNotificationSettings();
      setState(() {
        _settings = settings;
      });
      _animationController.forward();
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
    } catch (e) {
      if (!mounted) return;
      ShowToast().showSnackBar('Error updating settings: $e', context);
    }
  }

  Future<void> _requestPermission() async {
    final result = await _messagingHelper.requestPermissions();
    setState(() {
      _hasPermission =
          result.authorizationStatus == AuthorizationStatus.authorized;
    });
    if (!mounted) return;

    if (_hasPermission) {
      ShowToast().showSnackBar('Notifications enabled successfully!', context);
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Enable Notifications'),
          content: const Text(
            'To receive notifications, you need to enable them in your device settings. '
            'Go to Settings > Notifications > AttendUs and turn on Allow Notifications.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _settings == null
          ? const Center(child: CircularProgressIndicator())
          : FadeTransition(
              opacity: _fadeAnimation,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Permission Banner (only if no permission)
                    if (_permissionChecked && !_hasPermission)
                      _buildPermissionBanner(),

                    // Master Toggle Section
                    _buildMasterToggle(),

                    const SizedBox(height: 8),

                    // Events Section
                    _buildSectionHeader('Events', Icons.event_note_rounded),
                    _buildEventsSection(),

                    const SizedBox(height: 8),

                    // Communication Section
                    _buildSectionHeader(
                      'Communication',
                      Icons.chat_bubble_outline_rounded,
                    ),
                    _buildCommunicationSection(),

                    const SizedBox(height: 8),

                    // Activity Section
                    _buildSectionHeader(
                      'Activity',
                      Icons.notifications_active_outlined,
                    ),
                    _buildActivitySection(),

                    const SizedBox(height: 8),

                    // Preferences Section
                    _buildSectionHeader('Preferences', Icons.settings_outlined),
                    _buildPreferencesSection(),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF667EEA).withValues(alpha: 0.1),
            const Color(0xFF764BA2).withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF667EEA).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.notifications_off_outlined,
            size: 48,
            color: Color(0xFF667EEA),
          ),
          const SizedBox(height: 12),
          const Text(
            'Notifications are turned off',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enable notifications to stay updated with events, messages, and important updates.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _requestPermission,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF667EEA),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Enable Notifications',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterToggle() {
    final allEnabled =
        _settings!.eventReminders &&
        _settings!.newEvents &&
        _settings!.ticketUpdates &&
        _settings!.generalNotifications;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SwitchListTile(
        title: const Text(
          'All Notifications',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
        ),
        subtitle: const Text(
          'Master switch for all notification types',
          style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
        ),
        value: allEnabled,
        onChanged: _hasPermission
            ? (value) {
                _updateSettings(
                  _settings!.copyWith(
                    eventReminders: value,
                    newEvents: value,
                    ticketUpdates: value,
                    eventFeedback: value,
                    generalNotifications: value,
                    eventChanges: value,
                    geofenceCheckIn: value,
                    messagesAll: value,
                    messageMentions: value,
                    organizationUpdates: value,
                    organizerFeedback: value,
                  ),
                );
              }
            : null,
        activeColor: const Color(0xFF667EEA),
        inactiveThumbColor: _hasPermission ? null : Colors.grey[400],
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF667EEA)),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildCompactSwitch(
            title: 'Event Reminders',
            subtitle: 'Get notified before events start',
            value: _settings!.eventReminders,
            onChanged: (value) {
              _updateSettings(_settings!.copyWith(eventReminders: value));
            },
            showDivider: true,
          ),
          if (_settings!.eventReminders) ...[
            _buildReminderTimeSelector(),
            const Divider(height: 1),
          ],
          _buildCompactSwitch(
            title: 'Event Updates',
            subtitle: 'Time, location, or cancellation changes',
            value: _settings!.eventChanges,
            onChanged: (value) {
              _updateSettings(_settings!.copyWith(eventChanges: value));
            },
            showDivider: true,
          ),
          _buildCompactSwitch(
            title: 'Nearby Events',
            subtitle: 'New events in your area',
            value: _settings!.newEvents,
            onChanged: (value) {
              _updateSettings(_settings!.copyWith(newEvents: value));
            },
            showDivider: true,
          ),
          if (_settings!.newEvents) ...[
            _buildDistanceSelector(),
            const Divider(height: 1),
          ],
          _buildCompactSwitch(
            title: 'Group Events',
            subtitle: 'New events in your groups',
            value: _settings!.newEvents && _settings!.organizationUpdates,
            onChanged: (value) {
              _updateSettings(
                _settings!.copyWith(
                  newEvents: value,
                  organizationUpdates: value,
                ),
              );
            },
            showDivider: true,
          ),
          _buildCompactSwitch(
            title: 'Check-in Reminders',
            subtitle: 'When you\'re near the venue',
            value: _settings!.geofenceCheckIn,
            onChanged: (value) {
              _updateSettings(_settings!.copyWith(geofenceCheckIn: value));
            },
            showDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _buildCommunicationSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildCompactSwitch(
            title: 'All Messages',
            subtitle: 'New message notifications',
            value: _settings!.messagesAll,
            onChanged: (value) {
              _updateSettings(_settings!.copyWith(messagesAll: value));
            },
            showDivider: true,
          ),
          _buildCompactSwitch(
            title: 'Mentions',
            subtitle: 'When someone mentions you',
            value: _settings!.messageMentions,
            onChanged: (value) {
              _updateSettings(_settings!.copyWith(messageMentions: value));
            },
            showDivider: true,
          ),
          _buildCompactSwitch(
            title: 'Group Updates',
            subtitle: 'Join requests and member changes',
            value: _settings!.organizationUpdates,
            onChanged: (value) {
              _updateSettings(_settings!.copyWith(organizationUpdates: value));
            },
            showDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _buildActivitySection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildCompactSwitch(
            title: 'Ticket Updates',
            subtitle: 'Confirmations and changes',
            value: _settings!.ticketUpdates,
            onChanged: (value) {
              _updateSettings(_settings!.copyWith(ticketUpdates: value));
            },
            showDivider: true,
          ),
          _buildCompactSwitch(
            title: 'Feedback Requests',
            subtitle: 'Rate events you attended',
            value: _settings!.eventFeedback,
            onChanged: (value) {
              _updateSettings(_settings!.copyWith(eventFeedback: value));
            },
            showDivider: true,
          ),
          _buildCompactSwitch(
            title: 'Organizer Feedback',
            subtitle: 'Reviews on your events',
            value: _settings!.organizerFeedback,
            onChanged: (value) {
              _updateSettings(_settings!.copyWith(organizerFeedback: value));
            },
            showDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildCompactSwitch(
            title: 'Sound',
            subtitle: 'Play notification sounds',
            value: _settings!.soundEnabled,
            onChanged: (value) {
              _updateSettings(_settings!.copyWith(soundEnabled: value));
            },
            showDivider: true,
            icon: Icons.volume_up_outlined,
          ),
          _buildCompactSwitch(
            title: 'Vibration',
            subtitle: 'Vibrate on notifications',
            value: _settings!.vibrationEnabled,
            onChanged: (value) {
              _updateSettings(_settings!.copyWith(vibrationEnabled: value));
            },
            showDivider: true,
            icon: Icons.vibration_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool showDivider,
    IconData? icon,
  }) {
    return Column(
      children: [
        SwitchListTile(
          secondary: icon != null
              ? Icon(icon, color: const Color(0xFF6B7280), size: 22)
              : null,
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1A1A1A),
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
          value: value,
          onChanged: _hasPermission ? onChanged : null,
          activeColor: const Color(0xFF667EEA),
          inactiveThumbColor: _hasPermission ? null : Colors.grey[400],
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }

  Widget _buildReminderTimeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFF9FAFB),
      child: Row(
        children: [
          const Icon(Icons.access_time, size: 20, color: Color(0xFF6B7280)),
          const SizedBox(width: 12),
          const Text(
            'Remind me',
            style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _settings!.reminderTime,
                isDense: true,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A1A),
                ),
                items: [
                  const DropdownMenuItem(value: 15, child: Text('15 minutes')),
                  const DropdownMenuItem(value: 30, child: Text('30 minutes')),
                  const DropdownMenuItem(value: 60, child: Text('1 hour')),
                  const DropdownMenuItem(value: 120, child: Text('2 hours')),
                  const DropdownMenuItem(value: 1440, child: Text('1 day')),
                ].toList(),
                onChanged: _hasPermission
                    ? (value) {
                        if (value != null) {
                          _updateSettings(
                            _settings!.copyWith(reminderTime: value),
                          );
                        }
                      }
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'before',
            style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFF9FAFB),
      child: Row(
        children: [
          const Icon(
            Icons.location_on_outlined,
            size: 20,
            color: Color(0xFF6B7280),
          ),
          const SizedBox(width: 12),
          const Text(
            'Within',
            style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _settings!.newEventsDistance,
                isDense: true,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A1A),
                ),
                items: [
                  const DropdownMenuItem(value: 5, child: Text('5 miles')),
                  const DropdownMenuItem(value: 10, child: Text('10 miles')),
                  const DropdownMenuItem(value: 15, child: Text('15 miles')),
                  const DropdownMenuItem(value: 25, child: Text('25 miles')),
                  const DropdownMenuItem(value: 50, child: Text('50 miles')),
                ].toList(),
                onChanged: _hasPermission
                    ? (value) {
                        if (value != null) {
                          _updateSettings(
                            _settings!.copyWith(newEventsDistance: value),
                          );
                        }
                      }
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'of my location',
            style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}
