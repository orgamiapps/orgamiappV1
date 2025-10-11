import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/models/subscription_model.dart';
import 'package:attendus/widgets/tier_comparison_widget.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/logger.dart';

class SubscriptionMigrationDialog {
  static const String _migrationKey = 'tier_migration_completed';

  /// Check if user needs to see migration dialog
  static Future<bool> needsMigration(BuildContext context) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return false;

    try {
      final subscriptionService = context.read<SubscriptionService>();
      final subscription = subscriptionService.currentSubscription;

      // No subscription = no migration needed
      if (subscription == null || !subscription.isActive) {
        return false;
      }

      // Already has tier set = migration done
      if (subscription.tier != 'free' && subscription.tier.isNotEmpty) {
        return false;
      }

      // Check if migration was already completed
      final doc = await FirebaseFirestore.instance
          .collection('Customers')
          .doc(userId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (data[_migrationKey] == true) {
          return false;
        }
      }

      // User has old subscription without tier
      return true;
    } catch (e) {
      Logger.error('Error checking migration status', e);
      return false;
    }
  }

  /// Show migration dialog
  static Future<void> show(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _MigrationDialogContent();
      },
    );
  }

  /// Mark migration as completed
  static Future<void> _markMigrationCompleted() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('Customers')
          .doc(userId)
          .set({
        _migrationKey: true,
        'migrationCompletedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      Logger.error('Error marking migration as completed', e);
    }
  }
}

class _MigrationDialogContent extends StatefulWidget {
  @override
  State<_MigrationDialogContent> createState() =>
      __MigrationDialogContentState();
}

class __MigrationDialogContentState extends State<_MigrationDialogContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool _isProcessing = false;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: _currentPage == 0 ? _buildWelcomePage() : _buildSelectionPage(),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomePage() {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withValues(alpha: 0.8),
              ],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.celebration,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Exciting News!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'We\'ve introduced new subscription tiers',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),

        // Content
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What\'s New?',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildFeatureBullet(
                'Basic Plan',
                '\$5/month - Create 5 events monthly with essential features',
                Icons.star,
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildFeatureBullet(
                'Premium Plan',
                '\$20/month - Unlimited events, analytics, and group creation',
                Icons.diamond,
                theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Please choose the plan that best fits your needs.',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _currentPage = 1;
                      _animationController.reset();
                      _animationController.forward();
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionPage() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              Text(
                'Choose Your Plan',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select the subscription tier that works for you',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),

        // Tier comparison
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: TierComparisonWidget(
              onBasicSelected: () => _handleTierSelection(SubscriptionTier.basic),
              onPremiumSelected: () => _handleTierSelection(SubscriptionTier.premium),
            ),
          ),
        ),

        // Footer
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: TextButton(
            onPressed: _isProcessing ? null : () => _handleLater(),
            child: const Text(
              'I\'ll decide later',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureBullet(String title, String description, IconData icon, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleTierSelection(SubscriptionTier tier) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final subscriptionService = context.read<SubscriptionService>();

      // Update subscription tier
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        await FirebaseFirestore.instance
            .collection('subscriptions')
            .doc(userId)
            .update({
          'tier': tier.value,
          'updatedAt': Timestamp.now(),
        });

        // Mark migration as completed
        await SubscriptionMigrationDialog._markMigrationCompleted();

        // Reload subscription
        await subscriptionService.refresh();

        if (!mounted) return;

        ShowToast().showNormalToast(
          msg: '✨ Successfully updated to ${tier.displayName} tier!',
        );

        Navigator.of(context).pop();
      }
    } catch (e) {
      Logger.error('Error updating subscription tier', e);
      if (!mounted) return;

      ShowToast().showNormalToast(
        msg: 'Failed to update subscription. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _handleLater() async {
    // Default to Premium for now, mark migration as pending
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        await FirebaseFirestore.instance
            .collection('subscriptions')
            .doc(userId)
            .update({
          'tier': 'premium', // Default to premium with grace period
          'migrationPending': true,
          'updatedAt': Timestamp.now(),
        });

        await SubscriptionMigrationDialog._markMigrationCompleted();

        if (!mounted) return;

        ShowToast().showNormalToast(
          msg: 'You can change your plan anytime in Account settings.',
        );

        Navigator.of(context).pop();
      }
    } catch (e) {
      Logger.error('Error handling migration later', e);
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }
}

