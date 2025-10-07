import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:attendus/controller/customer_controller.dart';
// import 'package:attendus/firebase/FirebaseFirestoreHelper.dart'; // Unused import

import 'package:attendus/screens/Feedback/feedback_screen.dart';

import 'package:attendus/screens/Home/analytics_dashboard_screen.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/theme_provider.dart';

// import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/screens/Home/delete_account_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:attendus/Services/auth_service.dart';

import 'package:attendus/screens/MyProfile/user_profile_screen.dart';

import 'package:attendus/screens/Home/attendee_notification_screen.dart';
import 'package:attendus/screens/Home/about_us_screen.dart';
import 'package:attendus/screens/Home/blocked_users_screen.dart';
import 'package:attendus/screens/Legal/terms_conditions_screen.dart';
import 'package:attendus/screens/Legal/privacy_policy_screen.dart';
import 'package:attendus/screens/Home/help_screen.dart';
import 'package:attendus/screens/Premium/premium_upgrade_screen.dart';
import 'package:attendus/screens/Premium/subscription_management_screen.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/Utils/logger.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _isLoadingUserData = false;
  
  @override
  void initState() {
    super.initState();
    _ensureUserDataLoaded();
  }
  
  /// Ensure user data is fully loaded from Firestore
  Future<void> _ensureUserDataLoaded() async {
    // Check if user data needs to be loaded/refreshed
    final user = CustomerController.logeInCustomer;
    if (user == null) {
      Logger.warning('AccountScreen: No logged in user found');
      return;
    }
    
    // If user name is empty or looks like an email prefix, try to refresh
    final needsRefresh = user.name.isEmpty || 
                         user.name == user.email.split('@')[0] ||
                         user.name.toLowerCase() == 'user';
    
    if (needsRefresh) {
      if (mounted) {
        setState(() => _isLoadingUserData = true);
      }
      
      try {
        Logger.info('AccountScreen: Refreshing user data...');
        final authService = AuthService();
        await authService.refreshUserData();
        
        // If still incomplete, try aggressive update
        final updatedUser = CustomerController.logeInCustomer;
        if (updatedUser != null && 
            (updatedUser.name.isEmpty || updatedUser.name == updatedUser.email.split('@')[0])) {
          await authService.aggressiveProfileUpdate();
        }
      } catch (e) {
        Logger.warning('AccountScreen: Failed to refresh user data: $e');
      } finally {
        if (mounted) {
          setState(() => _isLoadingUserData = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Safely handle back button press
        if (Navigator.of(context).canPop()) {
          return true; // Allow pop
        } else {
          // If can't pop, navigate to dashboard instead
          Logger.info('AccountScreen: Cannot pop, staying on screen');
          return false; // Prevent pop
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(child: _bodyView()),
      ),
    );
  }

  Widget _bodyView() {
    return SingleChildScrollView(
      child: Column(children: [_buildProfileHeader(), _buildSettingsSection()]),
    );
  }

  Widget _buildProfileHeader() {
    final user = CustomerController.logeInCustomer;
    
    // Show loading indicator if user data is being refreshed
    if (_isLoadingUserData && user != null) {
      Logger.debug('AccountScreen: Still loading user data...');
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              // Safely handle back button press
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Logger.info('AccountScreen: Cannot pop navigation stack');
              }
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.arrow_back,
                color: Theme.of(context).colorScheme.onSurface,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Account',
            style: TextStyle(
              color: Theme.of(context).textTheme.titleLarge?.color,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              fontFamily: 'Roboto',
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              if (user == null) {
                ShowToast().showNormalToast(msg: 'User data not available');
                return;
              }
              
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      UserProfileScreen(user: user, isOwnProfile: true),
                ),
              ).then((_) {
                // Refresh user data when returning from profile screen
                if (mounted) {
                  _ensureUserDataLoaded();
                }
              });
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).shadowColor.withValues(alpha: 0.06),
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.person,
        size: 25,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Consumer<SubscriptionService>(
      builder: (context, subscriptionService, child) {
        return Container(
          margin: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
                spreadRadius: 0,
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Premium upgrade button at top (only show if not premium)
              if (!subscriptionService.hasPremium) ...[
                _buildPremiumUpgradeItem(),
                _buildDivider(),
              ],
              // If user has premium, show premium management
              if (subscriptionService.hasPremium) ...[
                _buildPremiumManageItem(subscriptionService),
                _buildDivider(),
              ],
              // Feedback
              _buildSettingsItem(
                icon: Icons.feedback,
                title: 'Feedback',
                subtitle: 'Share your thoughts with us',
                onTap: () =>
                    RouterClass.nextScreenNormal(context, FeedbackScreen()),
              ),
              _buildDivider(),
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
                subtitle: 'Send SMS or in-app notifications',
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
                onTap: () => RouterClass.nextScreenNormal(
                  context,
                  const AboutUsScreen(),
                ),
              ),
              _buildDivider(),
              _buildSettingsItem(
                icon: Icons.help,
                title: 'Help',
                subtitle: 'Get help and support',
                onTap: () =>
                    RouterClass.nextScreenNormal(context, const HelpScreen()),
              ),
              _buildDivider(),
              _buildDarkModeToggle(),
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
                  const PrivacyPolicyScreen(),
                ),
              ),
              _buildDivider(),
              _buildSettingsItem(
                icon: CupertinoIcons.question_diamond,
                title: 'Terms & Conditions',
                subtitle: 'Read our terms of service',
                onTap: () => RouterClass.nextScreenNormal(
                  context,
                  const TermsConditionsScreen(),
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
                  try {
                    await AuthService().signOut();
                    if (mounted) {
                      RouterClass().appRest(context: context);
                    }
                  } catch (e) {
                    ShowToast().showNormalToast(
                      msg: 'Error signing out. Please try again.',
                    );
                  }
                },
                isDestructive: true,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPremiumUpgradeItem() {
    // Subtle inline CTA matching settings list style
    return _buildSettingsItem(
      icon: Icons.workspace_premium,
      title: 'Upgrade to Premium',
      subtitle: 'Unlock unlimited events • \$5/month',
      onTap: () =>
          RouterClass.nextScreenNormal(context, const PremiumUpgradeScreen()),
    );
  }

  Widget _buildPremiumManageItem(SubscriptionService subscriptionService) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.verified,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subscriptionService.getSubscriptionStatusText(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      subscriptionService.getNextBillingDate() != null
                          ? 'Next billing: ${subscriptionService.getNextBillingDate()}'
                          : 'Premium features active',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                RouterClass.nextScreenNormal(
                  context,
                  const SubscriptionManagementScreen(),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF667EEA),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Manage Subscription',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
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
              ? Theme.of(context).colorScheme.error.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: isDestructive
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.primary,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).textTheme.titleMedium?.color,
          fontWeight: FontWeight.w600,
          fontSize: 16,
          fontFamily: 'Roboto',
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyMedium?.color,
          fontSize: 14,
          fontFamily: 'Roboto',
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 16,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      height: 1,
      color: Theme.of(context).dividerColor,
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
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getThemeIcon(themeProvider.isDarkMode),
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
          ),
          title: Text(
            'Theme',
            style: TextStyle(
              color: Theme.of(context).textTheme.titleMedium?.color,
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
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 14,
              fontFamily: 'Roboto',
            ),
          ),
          trailing: Icon(
            Icons.arrow_forward_ios,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
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
              color: Colors.black.withValues(alpha: 0.1),
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
                ).colorScheme.onSurface.withValues(alpha: 0.3),
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
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
