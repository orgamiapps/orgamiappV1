import 'package:flutter/material.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/screens/Authentication/create_account/suggested_contacts_screen.dart';
import 'package:attendus/widgets/attendus_design_system.dart';

class StepContacts extends StatelessWidget {
  const StepContacts({super.key, required this.onFinish});
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return AttendUsPageSection(
      title: 'Find people you know',
      subtitle:
          'Contact sync is optional. You can skip this now and manage contacts later from Settings.',
      icon: Icons.contacts_outlined,
      framed: false,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AttendUsActionTile(
            icon: Icons.people_alt_outlined,
            title: 'Connect with attendees and organizers',
            subtitle:
                'Attendus can help suggest contacts after you grant permission.',
            tone: AttendUsStatusTone.info,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onFinish,
                  child: const Text('Skip for now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AttendUsButton.primary(
                  label: 'Sync contacts',
                  icon: Icons.sync,
                  onPressed: () {
                    RouterClass.nextScreenNormal(
                      context,
                      const SuggestedContactsScreen(),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
