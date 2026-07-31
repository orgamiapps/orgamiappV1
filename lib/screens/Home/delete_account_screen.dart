import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';
import 'package:attendus/widgets/attendus_design_system.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _isDeleting = false;

  Future<void> _handleDelete() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      await FirebaseFirestoreHelper().deleteAccountViaCloudFunction(user.uid);

      await AuthService().signOut();
      if (!mounted) return;
      RouterClass().appRest(context: context);
    } catch (e) {
      if (!mounted) return;
      ShowToast().showNormalToast(
        msg: 'Failed to delete account. Please try again.',
      );
      setState(() {
        _isDeleting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            AppAppBarView.modernHeader(
              context: context,
              title: 'Delete Account',
              subtitle: 'Permanently delete your account',
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: AttendUsPageSection(
                      title: 'Permanent account deletion',
                      subtitle:
                          'This action removes your Attendus account and associated account data. It cannot be undone.',
                      icon: Icons.warning_amber_rounded,
                      framed: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildWarningItem(
                            context,
                            icon: Icons.person_remove_outlined,
                            text:
                                'Your profile, followers, and following will be removed.',
                          ),
                          const SizedBox(height: 10),
                          _buildWarningItem(
                            context,
                            icon: Icons.chat_bubble_outline,
                            text: 'Your messages and comments may be deleted.',
                          ),
                          const SizedBox(height: 10),
                          _buildWarningItem(
                            context,
                            icon: Icons.event_busy_outlined,
                            text:
                                'Tickets, attendance records, and related user data will be deleted.',
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: AttendUsButton.secondary(
                                  label: 'Cancel',
                                  onPressed: _isDeleting
                                      ? null
                                      : () => Navigator.pop(context),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AttendUsButton.destructive(
                                  label: 'Delete Account',
                                  icon: Icons.delete_forever_outlined,
                                  loading: _isDeleting,
                                  onPressed: _handleDelete,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningItem(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
