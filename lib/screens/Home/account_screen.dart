import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:attendus/controller/customer_controller.dart';
// import 'package:attendus/firebase/FirebaseFirestoreHelper.dart'; // Unused import

import 'package:attendus/screens/Feedback/feedback_screen.dart';

import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/theme_provider.dart';

// import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/screens/Home/delete_account_screen.dart';
import 'package:attendus/Services/auth_service.dart';

import 'package:attendus/screens/MyProfile/user_profile_screen.dart';

import 'package:attendus/screens/Home/about_us_screen.dart';
import 'package:attendus/screens/Home/blocked_users_screen.dart';
import 'package:attendus/screens/Legal/terms_conditions_screen.dart';
import 'package:attendus/screens/Legal/privacy_policy_screen.dart';
import 'package:attendus/screens/Home/help_screen.dart';
import 'package:attendus/screens/Premium/premium_upgrade_screen_v2.dart';
import 'package:attendus/screens/Premium/subscription_management_screen.dart';
import 'package:attendus/screens/Premium/premium_features_screen.dart';
import 'package:attendus/models/subscription_model.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/Utils/cached_image.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _isLoadingUserData = false;
  bool _isLoadingSubscription = false;

  @override
  void initState() {
    super.initState();
    // CRITICAL FIX: Defer initialization to post-frame callback to prevent
    // setState during build error
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeScreenData();
      }
    });
  }

  /// Initialize all necessary data for the screen
  Future<void> _initializeScreenData() async {
    // Run user data and subscription loading in parallel
    await Future.wait([_ensureUserDataLoaded(), _ensureSubscriptionLoaded()]);
  }

  /// Ensure subscription data is loaded from Firestore
  Future<void> _ensureSubscriptionLoaded() async {
    try {
      if (mounted) {
        setState(() => _isLoadingSubscription = true);
      }

      // Get subscription service and ensure it's initialized
      final subscriptionService = Provider.of<SubscriptionService>(
        context,
        listen: false,
      );

      // Initialize if not already done (this is safe now as we're in post-frame)
      await subscriptionService.initialize();

      // Refresh to get latest data
      await subscriptionService.refresh();

      Logger.info(
        'AccountScreen: Subscription loaded - hasPremium: ${subscriptionService.hasPremium}',
      );
    } catch (e) {
      Logger.error('AccountScreen: Failed to load subscription data', e);
    } finally {
      if (mounted) {
        setState(() => _isLoadingSubscription = false);
      }
    }
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
    final isNameIncomplete =
        user.name.isEmpty ||
        user.name == user.email.split('@')[0] ||
        user.name.toLowerCase() == 'user';

    // Also refresh if profile picture is missing
    final isProfilePictureMissing =
        user.profilePictureUrl == null || user.profilePictureUrl!.isEmpty;

    final needsRefresh = isNameIncomplete || isProfilePictureMissing;

    if (needsRefresh) {
      if (mounted) {
        setState(() => _isLoadingUserData = true);
      }

      try {
        Logger.info('AccountScreen: Refreshing user data...');
        final authService = AuthService();
        await authService.refreshUserData();

        // If still incomplete or photo missing, try aggressive update
        final updatedUser = CustomerController.logeInCustomer;
        final stillNameIncomplete =
            updatedUser != null &&
            (updatedUser.name.isEmpty ||
                updatedUser.name == updatedUser.email.split('@')[0]);
        final stillMissingPhoto =
            updatedUser != null &&
            (updatedUser.profilePictureUrl == null ||
                updatedUser.profilePictureUrl!.isEmpty);

        if (stillNameIncomplete || stillMissingPhoto) {
          await authService.aggressiveProfileUpdate();
          await authService.refreshUserData();
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
    final canPop = Navigator.of(context).canPop();

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
          // Only show back button if there's navigation history
          if (canPop) ...[
            GestureDetector(
              onTap: () {
                // Always try to pop the navigation stack to go back to previous screen
                try {
                  Navigator.of(context).pop();
                } catch (e) {
                  Logger.error(
                    'AccountScreen: Error popping navigation stack',
                    e,
                  );
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
          ],
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
                child: (() {
                  final imageUrl = _getUserProfileImageUrl();
                  if (imageUrl != null && imageUrl.isNotEmpty) {
                    return SafeNetworkImage(
                      imageUrl: imageUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorWidget: _buildDefaultProfilePicture(),
                    );
                  }
                  return _buildDefaultProfilePicture();
                })(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultProfilePicture() {
    final initial = _getUserInitial();
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  String? _getUserProfileImageUrl() {
    final model = CustomerController.logeInCustomer;
    final modelUrl = model?.profilePictureUrl;
    if (modelUrl != null && modelUrl.isNotEmpty) return modelUrl;

    final authUrl = FirebaseAuth.instance.currentUser?.photoURL;
    if (authUrl != null && authUrl.isNotEmpty) return authUrl;
    return null;
  }

  String _getUserInitial() {
    final model = CustomerController.logeInCustomer;
    final name = model?.name.trim();
    if (name != null && name.isNotEmpty) {
      return name.characters.first.toUpperCase();
    }
    final email = model?.email.trim();
    if (email != null && email.isNotEmpty) {
      return email.characters.first.toUpperCase();
    }
    return '?';
  }

  Widget _buildSettingsSection() {
    // Use Consumer instead of Selector for more reliable updates
    return Consumer<SubscriptionService>(
      builder: (context, subscriptionService, child) {
        // Show loading state while subscription data is being fetched
        final isLoading =
            _isLoadingSubscription || subscriptionService.isLoading;
        final hasPremium = subscriptionService.hasPremium;

        // Log current state for debugging
        if (isLoading) {
          Logger.debug('AccountScreen: Loading subscription data...');
        } else {
          Logger.debug('AccountScreen: hasPremium = $hasPremium');
        }

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
              // Show loading indicator while fetching subscription data
              if (isLoading) ...[
                _buildPremiumLoadingItem(),
                _buildDivider(),
              ]
              // Premium upgrade button at top (only show if not premium and not loading)
              else if (!hasPremium) ...[
                _buildPremiumUpgradeItem(),
                _buildDivider(),
              ]
              // If user has premium, show premium management
              else if (hasPremium) ...[
                _buildPremiumManageItem(subscriptionService),
                _buildDivider(),
              ],
              // Premium Features (only show if user has premium)
              if (hasPremium) ...[
                _buildSettingsItem(
                  icon: Icons.workspace_premium,
                  title: 'Premium Features',
                  subtitle: 'Access analytics and advanced tools',
                  onTap: () => RouterClass.nextScreenNormal(
                    context,
                    const PremiumFeaturesScreen(),
                  ),
                ),
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

  Widget _buildPremiumLoadingItem() {
    // Loading state for subscription data
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
      title: Text(
        'Loading Subscription',
        style: TextStyle(
          color: Theme.of(context).textTheme.titleMedium?.color,
          fontWeight: FontWeight.w600,
          fontSize: 16,
          fontFamily: 'Roboto',
        ),
      ),
      subtitle: Text(
        'Please wait...',
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyMedium?.color,
          fontSize: 14,
          fontFamily: 'Roboto',
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    );
  }

  Widget _buildPremiumUpgradeItem() {
    return _buildTierDisplayCard();
  }

  Widget _buildPremiumManageItem(SubscriptionService subscriptionService) {
    return _buildTierDisplayCard();
  }

  Widget _buildTierDisplayCard() {
    return Consumer<SubscriptionService>(
      builder: (context, subscriptionService, child) {
        final tier = subscriptionService.currentTier;
        final subscription = subscriptionService.currentSubscription;
        final theme = Theme.of(context);

        // Free tier - blend in with other items but with subtle upgrade hint
        if (tier == SubscriptionTier.free) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              onTap: () async {
                await RouterClass.nextScreenNormal(
                  context,
                  const PremiumUpgradeScreenV2(),
                );
                if (mounted) {
                  await _ensureSubscriptionLoaded();
                }
              },
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.workspace_premium,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              title: const Text(
                'Upgrade to Premium',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Create more events and unlock analytics',
                style: TextStyle(fontSize: 13),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 8,
              ),
            ),
          );
        }

        // Basic or Premium tier - blend in with other items
        if (subscription == null) return const SizedBox.shrink();

        final isBasic = tier == SubscriptionTier.basic;
        final tierColor = isBasic ? Colors.blue : theme.colorScheme.primary;
        final String? billingDate = subscriptionService.getNextBillingDate();

        // Build subtitle based on tier
        String subtitle = subscription.planDisplayName;
        if (isBasic) {
          final remaining = subscription.remainingEventsThisMonth ?? 0;
          subtitle = '$remaining of 5 events remaining this month';
        } else {
          subtitle = 'Unlimited events • Active';
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          decoration: BoxDecoration(
            color: tierColor.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              ListTile(
                onTap: () async {
                  await RouterClass.nextScreenNormal(
                    context,
                    const SubscriptionManagementScreen(),
                  );
                  if (mounted) {
                    await _ensureSubscriptionLoaded();
                  }
                },
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tierColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isBasic ? Icons.star : Icons.workspace_premium,
                    color: tierColor,
                    size: 20,
                  ),
                ),
                title: Row(
                  children: [
                    Text(
                      '${tier.displayName} Plan',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ACTIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subtitle, style: const TextStyle(fontSize: 13)),
                    if (billingDate != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Renews $billingDate',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),

              // Optional: Show upgrade option for Basic users inline
              if (isBasic)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () async {
                            await RouterClass.nextScreenNormal(
                              context,
                              const PremiumUpgradeScreenV2(),
                            );
                            if (mounted) {
                              await _ensureSubscriptionLoaded();
                            }
                          },
                          icon: Icon(
                            Icons.upgrade,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          label: Text(
                            'Upgrade to Premium',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
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
