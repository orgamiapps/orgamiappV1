import 'package:flutter/material.dart';
import 'package:attendus/widgets/event_announcement_composer.dart';

class AttendeeNotificationScreen extends StatelessWidget {
  const AttendeeNotificationScreen({super.key, this.eventId});
  final String? eventId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Event announcements')),
    body: eventId == null
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Open an event you manage and choose Notify attendees to send an event-specific announcement.',
              ),
            ),
          )
        : EventAnnouncementComposer(eventId: eventId!),
  );
}
