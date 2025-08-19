import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:orgami/Utils/router.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:orgami/controller/customer_controller.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';

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

      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() {
        CustomerController.logeInCustomer = null;
      });
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
    return Scaffold(
      appBar: AppBar(title: const Text('Delete Account')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete your account?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'This will permanently delete your account and associated data. '
              'This action cannot be undone.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _buildWarningItem(
              context,
              icon: Icons.delete_forever,
              text: 'Your profile, followers, and following will be removed.',
            ),
            const SizedBox(height: 8),
            _buildWarningItem(
              context,
              icon: Icons.chat_bubble_outline,
              text: 'Your messages and comments may be deleted.',
            ),
            const SizedBox(height: 8),
            _buildWarningItem(
              context,
              icon: Icons.event,
              text:
                  'Tickets, attendance records, and related user data will be deleted.',
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isDeleting
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isDeleting ? null : _handleDelete,
                    child: _isDeleting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text('Delete Account'),
                  ),
                ),
              ],
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
        Icon(icon, color: const Color(0xFFEF4444)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
