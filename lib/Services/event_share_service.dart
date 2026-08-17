import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/models/event_model.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class EventShareService {
  const EventShareService._();

  static Uri eventUri(String eventId) => AppConstants.buildEventUri(eventId);

  static String? eventIdFromUri(Uri uri) {
    if (uri.host.isNotEmpty && uri.host != 'attendus.app') return null;
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    final canonical = segments.length == 2 && segments.first == 'event';
    final application =
        segments.length == 3 && segments[0] == 'app' && segments[1] == 'event';
    if (!canonical && !application) return null;
    final eventId = segments.last.trim();
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(eventId) ? eventId : null;
  }

  static String shareText(EventModel event) {
    final date = DateFormat('EEEE, MMMM d, y').format(event.selectedDateTime);
    final start = DateFormat('h:mm a').format(event.selectedDateTime);
    final end = DateFormat('h:mm a').format(event.eventEndTime);
    final location = event.locationName?.trim().isNotEmpty == true
        ? event.locationName!.trim()
        : event.location.trim();
    return [
      event.title.trim(),
      '$date, $start–$end',
      if (location.isNotEmpty) location,
      '',
      'View event: ${eventUri(event.id)}',
    ].join('\n');
  }

  static Future<ShareResult> shareLink(EventModel event) {
    return SharePlus.instance.share(
      ShareParams(
        title: event.title,
        subject: 'You’re invited: ${event.title}',
        text: shareText(event),
      ),
    );
  }

  static Future<void> copyLink(EventModel event) {
    return Clipboard.setData(
      ClipboardData(text: eventUri(event.id).toString()),
    );
  }
}
