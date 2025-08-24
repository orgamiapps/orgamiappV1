import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:orgami/controller/customer_controller.dart';
// import 'package:orgami/firebase/FirebaseFirestoreHelper.dart'; // Unused import

import 'package:orgami/Screens/Feedback/feedback_screen.dart';

import 'package:orgami/Screens/Home/analytics_dashboard_screen.dart';
import 'package:orgami/Utils/app_constants.dart';
import 'package:orgami/Utils/router.dart';
import 'package:orgami/Utils/theme_provider.dart';

import 'package:orgami/Utils/web_view_page.dart';
// import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/screens/Home/delete_account_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:orgami/Screens/MyProfile/user_profile_screen.dart';

import 'package:orgami/Screens/Home/attendee_notification_screen.dart';
import 'package:orgami/screens/Home/blocked_users_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: _bodyView()),
    );
  }

  Widget _bodyView() {
    return SingleChildScrollView(
      child: Column(children: [_buildProfileHeader(), _buildSettingsSection()]),
    );
  }

  Widget _buildProfileHeader() {
    final user = CustomerController.logeInCustomer;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Text(
            'Account',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 22,
              fontWeight: FontWeight.w600,
              fontFamily: 'Roboto',
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      UserProfileScreen(user: user!, isOwnProfile: true),
                ),
              );
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Color(0xFFE5E7EB), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: user?.profilePictureUrl != null
                    ? Image.network(
                        user!.profilePictureUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildDefaultProfilePicture();
                        },
                      )
                    : _buildDefaultProfilePicture(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultProfilePicture() {
    return Container(
      color: const Color(0xFFE1E5E9),
      child: const Icon(Icons.person, size: 25, color: Color(0xFF9CA3AF)),
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Profile moved to bottom app bar
          _buildSettingsItem(
            icon: Icons.analytics_rounded,
            title: 'Analytics Dashboard',
            subtitle: 'Comprehensive insights across all events',
            onTap: () => RouterClass.nextScreenNormal(
              context,
              const AnalyticsDashboardScreen(),
            ),
          ),
          _buildDivider(),
          _buildSettingsItem(
            icon: Icons.sms_rounded,
            title: 'Send Notifications',
            subtitle: 'Send SMS notifications to previous attendees',
            onTap: () => RouterClass.nextScreenNormal(
              context,
              const AttendeeNotificationScreen(),
            ),
          ),
          _buildDivider(),
          _buildSettingsItem(
            icon: Icons.block,
            title: 'Blocked Users',
            subtitle: 'Manage your blocked list',
            onTap: () => RouterClass.nextScreenNormal(
              context,
              const BlockedUsersScreen(),
            ),
          ),
          _buildDivider(),
          _buildSettingsItem(
            icon: CupertinoIcons.info,
            title: 'About Us',
            subtitle: 'Learn more about our app',
            onTap: () => {},
          ),
          _buildDivider(),
          _buildSettingsItem(
            icon: Icons.help,
            title: 'Help',
            subtitle: 'Get help and support',
            onTap: () => RouterClass.nextScreenNormal(
              context,
              WebViewPage(url: AppConstants.supportUrl, title: 'Support'),
            ),
          ),
          _buildDivider(),
          _buildDarkModeToggle(),
          _buildDivider(),
          _buildSettingsItem(
            icon: Icons.feedback,
            title: 'Feedback',
            subtitle: 'Share your thoughts with us',
            onTap: () =>
                RouterClass.nextScreenNormal(context, FeedbackScreen()),
          ),
          _buildDivider(),
          _buildSettingsItem(
            icon: Icons.delete_forever,
            title: 'Delete Account',
            subtitle: 'Permanently delete your account',
            onTap: () => RouterClass.nextScreenNormal(
              context,
              const DeleteAccountScreen(),
            ),
          ),
          _buildDivider(),
          _buildSettingsItem(
            icon: Icons.privacy_tip,
            title: 'Privacy Policy',
            subtitle: 'Read our privacy policy',
            onTap: () => RouterClass.nextScreenNormal(
              context,
              WebViewPage(
                url: AppConstants.privacyPolicyUrl,
                title: 'Privacy Policy',
              ),
            ),
          ),
          _buildDivider(),
          _buildSettingsItem(
            icon: CupertinoIcons.question_diamond,
            title: 'Terms & Conditions',
            subtitle: 'Read our terms of service',
            onTap: () => RouterClass.nextScreenNormal(
              context,
              WebViewPage(
                url: AppConstants.termsConditionsUrl,
                title: 'Terms & Conditions',
              ),
            ),
          ),
          _buildDivider(),
          if (FirebaseAuth.instance.currentUser?.email == 'pr@mail.com')
            _buildSettingsItem(
              icon: Icons.admin_panel_settings,
              title: 'Grant Admin (Debug)',
              subtitle: 'Sets admin claim for this account',
              onTap: _setSelfAdmin,
            ),
          if (FirebaseAuth.instance.currentUser?.email == 'pr@mail.com')
            _buildDivider(),
          _buildSettingsItem(
            icon: Icons.logout,
            title: 'Logout',
            subtitle: 'Sign out of your account',
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                setState(() {
                  CustomerController.logeInCustomer = null;
                });
                RouterClass().appRest(context: context);
              }
            },
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDestructive
              ? const Color(0xFFEF4444).withOpacity(0.1)
              : const Color(0xFF667EEA).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: isDestructive
              ? const Color(0xFFEF4444)
              : const Color(0xFF667EEA),
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive
              ? const Color(0xFFEF4444)
              : Theme.of(context).textTheme.titleMedium?.color ??
                    const Color(0xFF1A1A1A),
          fontWeight: FontWeight.w600,
          fontSize: 16,
          fontFamily: 'Roboto',
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color:
              Theme.of(context).textTheme.bodyMedium?.color ??
              const Color(0xFF9CA3AF),
          fontSize: 14,
          fontFamily: 'Roboto',
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        color: const Color(0xFF9CA3AF),
        size: 16,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      height: 1,
      color: const Color(0xFFE1E5E9),
    );
  }

  Widget _buildDarkModeToggle() {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getThemeIcon(themeProvider.isDarkMode),
              color: const Color(0xFF667EEA),
              size: 20,
            ),
          ),
          title: Text(
            'Theme',
            style: TextStyle(
              color:
                  Theme.of(context).textTheme.titleMedium?.color ??
                  const Color(0xFF1A1A1A),
              fontWeight: FontWeight.w600,
              fontSize: 16,
              fontFamily: 'Roboto',
            ),
          ),
          subtitle: Text(
            _getThemeModeText(themeProvider.isDarkMode),
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 14,
              fontFamily: 'Roboto',
            ),
          ),
          trailing: Icon(
            Icons.arrow_forward_ios,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withOpacity(0.6),
            size: 16,
          ),
          onTap: () => _showThemeSelector(context, themeProvider),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 8,
          ),
        );
      },
    );
  }

  String _getThemeModeText(bool isDark) {
    return isDark ? 'Dark mode enabled' : 'Light mode enabled';
  }

  Future<void> _setSelfAdmin() async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('setSelfAdmin');
      await callable.call(<String, dynamic>{});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin claim set. Please sign out and sign back in.'),
        ),
      );
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to set admin: $e');
    }
  }

  void _showThemeSelector(BuildContext context, ThemeProvider themeProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Choose Theme',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
            ),
            _buildThemeOption(
              context,
              themeProvider,
              false,
              Icons.light_mode,
              'Light',
              'Use light theme',
            ),
            _buildThemeOption(
              context,
              themeProvider,
              true,
              Icons.dark_mode,
              'Dark',
              'Use dark theme',
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    ThemeProvider themeProvider,
    bool isDark,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final isSelected = themeProvider.isDarkMode == isDark;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: isSelected
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.primary,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          fontSize: 16,
          fontFamily: 'Roboto',
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color:
              Theme.of(context).textTheme.bodyMedium?.color ??
              const Color(0xFF9CA3AF),
          fontSize: 14,
          fontFamily: 'Roboto',
        ),
      ),
      trailing: isSelected
          ? Icon(
              Icons.check,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            )
          : null,
      onTap: () {
        themeProvider.setTheme(isDark);
        Navigator.pop(context);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    );
  }

  IconData _getThemeIcon(bool isDark) {
    return isDark ? Icons.dark_mode : Icons.light_mode;
  }
}
