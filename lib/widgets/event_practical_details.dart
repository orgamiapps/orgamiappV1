import 'package:flutter/material.dart';
import 'package:attendus/models/event_model.dart';

class EventPracticalDetails extends StatelessWidget {
  const EventPracticalDetails({super.key, required this.event});
  final EventModel event;
  @override
  Widget build(BuildContext context) {
    final experience = event.experience;
    final sections = <Widget>[];
    void section(String title, String text) {
      if (text.trim().isEmpty) return;
      sections.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              SelectableText(text),
            ],
          ),
        ),
      );
    }

    final agenda = (experience['agenda'] as List? ?? []).whereType<Map>();
    section(
      'Agenda',
      agenda
          .map(
            (item) =>
                '${item['title'] ?? ''}${(item['details']?.toString().isNotEmpty ?? false) ? '\n${item['details']}' : ''}',
          )
          .join('\n\n'),
    );
    section(
      'Accessibility',
      [
        ...(experience['accessibilityOptions'] as List? ?? []),
        experience['accessibilityDetails'] ?? '',
      ].where((item) => item.toString().isNotEmpty).join('\n'),
    );
    section(
      'Things to bring',
      (experience['thingsToBring'] as List? ?? []).join('\n'),
    );
    final contact = experience['publicContact'];
    if (contact is Map && contact['visible'] == true) {
      section(
        'Contact the organizer',
        [
          contact['name'],
          contact['email'],
        ].whereType<String>().where((s) => s.isNotEmpty).join('\n'),
      );
    }
    section(
      'Refund terms',
      event.registrationPolicy['refundTerms']?.toString() ?? '',
    );
    if (sections.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections,
      ),
    );
  }
}
