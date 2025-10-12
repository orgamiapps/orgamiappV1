import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:attendus/Utils/toast.dart';

/// Helper class for calendar integration across the app
class CalendarHelper {
  /// Show calendar options dialog to user
  static void showCalendarOptions(
    BuildContext context, {
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String description,
    required String location,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.calendar_today,
                color: Color(0xFF667EEA),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Add to Calendar',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose your calendar app:',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            _buildCalendarOptionButton(
              context: context,
              icon: Icons.calendar_today,
              title: 'Google Calendar',
              subtitle: 'Add to your Google Calendar',
              color: const Color(0xFF4285F4),
              onTap: () {
                Navigator.pop(context);
                openGoogleCalendar(
                  title: title,
                  startTime: startTime,
                  endTime: endTime,
                  description: description,
                  location: location,
                );
              },
            ),
            const SizedBox(height: 12),
            _buildCalendarOptionButton(
              context: context,
              icon: Icons.apple,
              title: 'Apple Calendar',
              subtitle: 'Add to your iCloud Calendar',
              color: const Color(0xFF000000),
              onTap: () {
                Navigator.pop(context);
                openAppleCalendar(
                  title: title,
                  startTime: startTime,
                  endTime: endTime,
                  description: description,
                  location: location,
                );
              },
            ),
            const SizedBox(height: 12),
            _buildCalendarOptionButton(
              context: context,
              icon: Icons.calendar_month,
              title: 'Outlook Calendar',
              subtitle: 'Add to your Outlook Calendar',
              color: const Color(0xFF0078D4),
              onTap: () {
                Navigator.pop(context);
                openOutlookCalendar(
                  title: title,
                  startTime: startTime,
                  endTime: endTime,
                  description: description,
                  location: location,
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildCalendarOptionButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  /// Open Google Calendar with event details
  static Future<void> openGoogleCalendar({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String description,
    required String location,
  }) async {
    try {
      final eventUrl = Uri.encodeFull(
        'https://calendar.google.com/calendar/render?action=TEMPLATE'
        '&text=${Uri.encodeComponent(title)}'
        '&dates=${DateFormat('yyyyMMddTHHmmss').format(startTime)}/${DateFormat('yyyyMMddTHHmmss').format(endTime)}'
        '&details=${Uri.encodeComponent(description)}'
        '&location=${Uri.encodeComponent(location)}',
      );

      final uri = Uri.parse(eventUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        ShowToast().showNormalToast(msg: 'Opening Google Calendar...');
      } else {
        ShowToast().showNormalToast(msg: 'Could not open Google Calendar');
      }
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to open Google Calendar');
    }
  }

  /// Open Apple Calendar with event details
  static Future<void> openAppleCalendar({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String description,
    required String location,
  }) async {
    try {
      // Apple Calendar uses webcal:// protocol or Google Calendar format as fallback
      final eventUrl = Uri.encodeFull(
        'https://calendar.google.com/calendar/render?action=TEMPLATE'
        '&text=${Uri.encodeComponent(title)}'
        '&dates=${DateFormat('yyyyMMddTHHmmss').format(startTime)}/${DateFormat('yyyyMMddTHHmmss').format(endTime)}'
        '&details=${Uri.encodeComponent(description)}'
        '&location=${Uri.encodeComponent(location)}',
      );

      final uri = Uri.parse(eventUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        ShowToast().showNormalToast(msg: 'Opening Apple Calendar...');
      } else {
        ShowToast().showNormalToast(msg: 'Could not open Apple Calendar');
      }
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to open Apple Calendar');
    }
  }

  /// Open Outlook Calendar with event details
  static Future<void> openOutlookCalendar({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String description,
    required String location,
  }) async {
    try {
      final eventUrl = Uri.encodeFull(
        'https://outlook.live.com/calendar/0/deeplink/compose'
        '?subject=${Uri.encodeComponent(title)}'
        '&body=${Uri.encodeComponent(description)}'
        '&startdt=${DateFormat('yyyy-MM-ddTHH:mm:ss').format(startTime)}'
        '&enddt=${DateFormat('yyyy-MM-ddTHH:mm:ss').format(endTime)}'
        '&location=${Uri.encodeComponent(location)}',
      );

      final uri = Uri.parse(eventUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        ShowToast().showNormalToast(msg: 'Opening Outlook Calendar...');
      } else {
        ShowToast().showNormalToast(msg: 'Could not open Outlook Calendar');
      }
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to open Outlook Calendar');
    }
  }
}

