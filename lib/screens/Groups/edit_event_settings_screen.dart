import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/models/organization_model.dart';

class EditEventSettingsScreen extends StatefulWidget {
  final String organizationId;
  final OrganizationModel organization;

  const EditEventSettingsScreen({
    super.key,
    required this.organizationId,
    required this.organization,
  });

  @override
  State<EditEventSettingsScreen> createState() =>
      _EditEventSettingsScreenState();
}

class _EditEventSettingsScreenState extends State<EditEventSettingsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _saving = false;
  bool _hasChanges = false;

  // Event visibility and permissions
  String _defaultEventVisibility = 'public';
  bool _allowMemberEventCreation = true;
  bool _requireEventApproval = false;
  bool _allowEventComments = true;
  bool _allowEventRSVP = true;
  bool _allowEventSharing = true;
  bool _allowEventPhotos = true;
  bool _allowEventPolls = false;
  bool _allowEventCheckIn = true;
  bool _allowEventFeedback = true;
  bool _autoArchiveEvents = true;
  int _autoArchiveDays = 30;
  bool _sendEventReminders = true;
  int _reminderHoursBefore = 24;
  bool _allowTicketSales = true;
  bool _allowEventCoHosts = true;
  int _maxCoHosts = 5;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    try {
      final doc = await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _defaultEventVisibility = data['defaultEventVisibility'] ?? 'public';
          _allowMemberEventCreation = data['allowMemberEventCreation'] ?? true;
          _requireEventApproval = data['requireEventApproval'] ?? false;
          _allowEventComments = data['allowEventComments'] ?? true;
          _allowEventRSVP = data['allowEventRSVP'] ?? true;
          _allowEventSharing = data['allowEventSharing'] ?? true;
          _allowEventPhotos = data['allowEventPhotos'] ?? true;
          _allowEventPolls = data['allowEventPolls'] ?? false;
          _allowEventCheckIn = data['allowEventCheckIn'] ?? true;
          _allowEventFeedback = data['allowEventFeedback'] ?? true;
          _autoArchiveEvents = data['autoArchiveEvents'] ?? true;
          _autoArchiveDays = data['autoArchiveDays'] ?? 30;
          _sendEventReminders = data['sendEventReminders'] ?? true;
          _reminderHoursBefore = data['reminderHoursBefore'] ?? 24;
          _allowTicketSales = data['allowTicketSales'] ?? true;
          _allowEventCoHosts = data['allowEventCoHosts'] ?? true;
          _maxCoHosts = data['maxCoHosts'] ?? 5;
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  void _onSettingChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      await _db.collection('Organizations').doc(widget.organizationId).update({
        'defaultEventVisibility': _defaultEventVisibility,
        'allowMemberEventCreation': _allowMemberEventCreation,
        'requireEventApproval': _requireEventApproval,
        'allowEventComments': _allowEventComments,
        'allowEventRSVP': _allowEventRSVP,
        'allowEventSharing': _allowEventSharing,
        'allowEventPhotos': _allowEventPhotos,
        'allowEventPolls': _allowEventPolls,
        'allowEventCheckIn': _allowEventCheckIn,
        'allowEventFeedback': _allowEventFeedback,
        'autoArchiveEvents': _autoArchiveEvents,
        'autoArchiveDays': _autoArchiveDays,
        'sendEventReminders': _sendEventReminders,
        'reminderHoursBefore': _reminderHoursBefore,
        'allowTicketSales': _allowTicketSales,
        'allowEventCoHosts': _allowEventCoHosts,
        'maxCoHosts': _maxCoHosts,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() => _hasChanges = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event settings updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Event Settings',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _saving ? null : _saveSettings,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Event Visibility Section
          _buildSection(
            'Event Visibility',
            Icons.visibility_outlined,
            'Control who can see events created in this group',
            [
              _buildVisibilitySelector(),
              const SizedBox(height: 16),
              _buildInfoCard(
                _defaultEventVisibility == 'public'
                    ? 'Events will be visible to everyone and discoverable in search'
                    : 'Events will only be visible to group members',
                Icons.info_outline,
                _defaultEventVisibility == 'public'
                    ? Colors.blue
                    : Colors.orange,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Event Creation Section
          _buildSection(
            'Event Creation',
            Icons.event_note_outlined,
            'Manage who can create events and approval processes',
            [
              _buildSwitchTile(
                'Allow Member Event Creation',
                'Let group members create events',
                _allowMemberEventCreation,
                (value) {
                  setState(() => _allowMemberEventCreation = value);
                  _onSettingChanged();
                },
              ),
              if (_allowMemberEventCreation) ...[
                const SizedBox(height: 12),
                _buildSwitchTile(
                  'Require Admin Approval',
                  'Member-created events need admin approval before publishing',
                  _requireEventApproval,
                  (value) {
                    setState(() => _requireEventApproval = value);
                    _onSettingChanged();
                  },
                ),
              ],
              const SizedBox(height: 12),
              _buildSwitchTile(
                'Allow Co-hosts',
                'Event creators can add co-hosts to help manage events',
                _allowEventCoHosts,
                (value) {
                  setState(() => _allowEventCoHosts = value);
                  _onSettingChanged();
                },
              ),
              if (_allowEventCoHosts) ...[
                const SizedBox(height: 16),
                _buildSliderTile(
                  'Maximum Co-hosts',
                  'Maximum number of co-hosts per event',
                  _maxCoHosts.toDouble(),
                  1,
                  10,
                  (value) {
                    setState(() => _maxCoHosts = value.round());
                    _onSettingChanged();
                  },
                ),
              ],
            ],
          ),

          const SizedBox(height: 24),

          // Event Features Section
          _buildSection(
            'Event Features',
            Icons.tune_outlined,
            'Enable or disable specific features for events',
            [
              _buildSwitchTile(
                'Event RSVP',
                'Allow attendees to RSVP to events',
                _allowEventRSVP,
                (value) {
                  setState(() => _allowEventRSVP = value);
                  _onSettingChanged();
                },
              ),
              const SizedBox(height: 12),
              _buildSwitchTile(
                'Event Comments',
                'Allow comments and discussions on events',
                _allowEventComments,
                (value) {
                  setState(() => _allowEventComments = value);
                  _onSettingChanged();
                },
              ),
              const SizedBox(height: 12),
              _buildSwitchTile(
                'Event Sharing',
                'Allow sharing events outside the group',
                _allowEventSharing,
                (value) {
                  setState(() => _allowEventSharing = value);
                  _onSettingChanged();
                },
              ),
              const SizedBox(height: 12),
              _buildSwitchTile(
                'Event Photos',
                'Allow photo uploads during events',
                _allowEventPhotos,
                (value) {
                  setState(() => _allowEventPhotos = value);
                  _onSettingChanged();
                },
              ),
              const SizedBox(height: 12),
              _buildSwitchTile(
                'Event Polls',
                'Allow polls to be created within events',
                _allowEventPolls,
                (value) {
                  setState(() => _allowEventPolls = value);
                  _onSettingChanged();
                },
              ),
              const SizedBox(height: 12),
              _buildSwitchTile(
                'Event Check-in',
                'Allow QR code and location-based check-ins',
                _allowEventCheckIn,
                (value) {
                  setState(() => _allowEventCheckIn = value);
                  _onSettingChanged();
                },
              ),
              const SizedBox(height: 12),
              _buildSwitchTile(
                'Event Feedback',
                'Collect feedback after events end',
                _allowEventFeedback,
                (value) {
                  setState(() => _allowEventFeedback = value);
                  _onSettingChanged();
                },
              ),
              const SizedBox(height: 12),
              _buildSwitchTile(
                'Ticket Sales',
                'Allow paid events with ticket sales',
                _allowTicketSales,
                (value) {
                  setState(() => _allowTicketSales = value);
                  _onSettingChanged();
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Automation Section
          _buildSection(
            'Automation',
            Icons.auto_mode_outlined,
            'Automated actions and notifications for events',
            [
              _buildSwitchTile(
                'Send Event Reminders',
                'Automatically notify attendees before events',
                _sendEventReminders,
                (value) {
                  setState(() => _sendEventReminders = value);
                  _onSettingChanged();
                },
              ),
              if (_sendEventReminders) ...[
                const SizedBox(height: 16),
                _buildSliderTile(
                  'Reminder Timing',
                  'Send reminders this many hours before events',
                  _reminderHoursBefore.toDouble(),
                  1,
                  168, // 1 week
                  (value) {
                    setState(() => _reminderHoursBefore = value.round());
                    _onSettingChanged();
                  },
                ),
              ],
              const SizedBox(height: 12),
              _buildSwitchTile(
                'Auto-archive Old Events',
                'Automatically hide events after they end',
                _autoArchiveEvents,
                (value) {
                  setState(() => _autoArchiveEvents = value);
                  _onSettingChanged();
                },
              ),
              if (_autoArchiveEvents) ...[
                const SizedBox(height: 16),
                _buildSliderTile(
                  'Archive After',
                  'Days after event ends to auto-archive',
                  _autoArchiveDays.toDouble(),
                  1,
                  365,
                  (value) {
                    setState(() => _autoArchiveDays = value.round());
                    _onSettingChanged();
                  },
                ),
              ],
            ],
          ),

          const SizedBox(height: 32),

          // Save Button (mobile convenience)
          if (_hasChanges)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _saveSettings,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _saving
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Saving...'),
                        ],
                      )
                    : const Text(
                        'Save Event Settings',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSection(
    String title,
    IconData icon,
    String description,
    List<Widget> children,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF667EEA)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildVisibilitySelector() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildVisibilityOption(
              'Public',
              'Visible to everyone',
              Icons.public,
              'public',
              _defaultEventVisibility == 'public',
            ),
          ),
          Container(width: 1, height: 60, color: Colors.grey.shade300),
          Expanded(
            child: _buildVisibilityOption(
              'Members Only',
              'Visible to members',
              Icons.group,
              'private',
              _defaultEventVisibility == 'private',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisibilityOption(
    String title,
    String subtitle,
    IconData icon,
    String value,
    bool isSelected,
  ) {
    return InkWell(
      onTap: () {
        setState(() => _defaultEventVisibility = value);
        _onSettingChanged();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF667EEA).withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? const Color(0xFF667EEA)
                  : Colors.grey.shade600,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isSelected ? const Color(0xFF667EEA) : Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: (newValue) {
              onChanged(newValue);
              _onSettingChanged();
            },
            activeTrackColor: const Color(0xFF667EEA),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderTile(
    String title,
    String subtitle,
    double value,
    double min,
    double max,
    Function(double) onChanged,
  ) {
    String getValueLabel() {
      if (title.contains('Reminder')) {
        if (value < 24) return '${value.round()} hours';
        if (value < 168) return '${(value / 24).round()} days';
        return '${(value / 168).round()} weeks';
      }
      if (title.contains('Archive')) {
        if (value < 30) return '${value.round()} days';
        if (value < 365) return '${(value / 30).round()} months';
        return '${(value / 365).round()} years';
      }
      return value.round().toString();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  getValueLabel(),
                  style: const TextStyle(
                    color: Color(0xFF667EEA),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF667EEA),
              thumbColor: const Color(0xFF667EEA),
              overlayColor: const Color(0xFF667EEA).withValues(alpha: 0.2),
              valueIndicatorColor: const Color(0xFF667EEA),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: (max - min).round(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
