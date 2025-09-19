import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/screens/Premium/subscription_management_screen.dart';

class PremiumUpgradeScreen extends StatefulWidget {
  const PremiumUpgradeScreen({super.key});

  @override
  State<PremiumUpgradeScreen> createState() => _PremiumUpgradeScreenState();
}

class _PremiumUpgradeScreenState extends State<PremiumUpgradeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isUpgrading = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    
    // Initialize subscription service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SubscriptionService>(context, listen: false).initialize();
    });
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          _buildGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                AppAppBarView.appBarWithOnlyBackButton(
                  context: context,
                  backButtonColor: Colors.white.withValues(alpha: 0.15),
                  iconColor: Colors.white,
                ),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
            Theme.of(context).scaffoldBackgroundColor,
          ],
          stops: const [0.0, 0.3, 1.0],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Consumer<SubscriptionService>(
      builder: (context, subscriptionService, child) {
        if (subscriptionService.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        // If user already has premium, show management screen
        if (subscriptionService.hasPremium) {
          return _buildManagementView(subscriptionService);
        }

        // Show upgrade options
        return _buildUpgradeView(subscriptionService);
      },
    );
  }

  Widget _buildUpgradeView(SubscriptionService subscriptionService) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              _buildPremiumIcon(),
              const SizedBox(height: 24),
              _buildTitle(),
              const SizedBox(height: 16),
              _buildSubtitle(),
              const SizedBox(height: 40),
              _buildFeaturesList(),
              const SizedBox(height: 40),
              _buildPricingCard(),
              const SizedBox(height: 32),
              _buildUpgradeButton(subscriptionService),
              const SizedBox(height: 16),
              _buildDisclaimer(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManagementView(SubscriptionService subscriptionService) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            _buildPremiumIcon(),
            const SizedBox(height: 24),
            Text(
              '🎉 You\'re Premium!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'You have full access to create unlimited events',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.9),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            _buildSubscriptionStatusCard(subscriptionService),
            const SizedBox(height: 24),
            _buildManagementButtons(subscriptionService),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumIcon() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.2),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: const Icon(
        Icons.workspace_premium,
        size: 50,
        color: Colors.white,
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      'Upgrade to Premium',
      style: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSubtitle() {
    return Text(
      'Unlock the power to create unlimited events and connect with your community',
      style: TextStyle(
        fontSize: 16,
        color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.9),
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildFeaturesList() {
    final features = [
      'Create unlimited events',
      'Advanced event analytics',
      'Priority customer support',
      'Custom event branding',
      'Advanced attendee management',
      'Export attendee data',
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Premium Features',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          const SizedBox(height: 16),
          ...features.map((feature) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: const Color(0xFF667EEA),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        feature,
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildPricingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Premium Monthly',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '\$',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Text(
                '20',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '/month',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Billed monthly • Cancel anytime',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradeButton(SubscriptionService subscriptionService) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isUpgrading ? null : () => _handleUpgrade(subscriptionService),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Theme.of(context).colorScheme.primary,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isUpgrading
            ? const CircularProgressIndicator()
            : const Text(
                'Start Free Trial',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildDisclaimer() {
    return Text(
      'For testing purposes, this will activate a free premium account. Payment integration will be added later.',
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7),
        fontStyle: FontStyle.italic,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSubscriptionStatusCard(SubscriptionService subscriptionService) {
    final subscription = subscriptionService.currentSubscription!;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified,
                color: const Color(0xFF667EEA),
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                subscriptionService.getSubscriptionStatusText(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Plan: ${subscription.planDisplayName}',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.9),
            ),
          ),
          if (subscription.isTrial && subscription.trialEndsAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Trial ends: ${_formatDate(subscription.trialEndsAt!)}',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.9),
              ),
            ),
          ] else if (subscriptionService.getNextBillingDate() != null) ...[
            const SizedBox(height: 4),
            Text(
              'Next billing: ${subscriptionService.getNextBillingDate()}',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.9),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManagementButtons(SubscriptionService subscriptionService) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: () {
              RouterClass.nextScreenNormal(
                context,
                const SubscriptionManagementScreen(),
              );
            },
            icon: const Icon(Icons.settings),
            label: const Text('Manage Subscription'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text(
              'Back to Account',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.9),
                fontSize: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleUpgrade(SubscriptionService subscriptionService) async {
    setState(() {
      _isUpgrading = true;
    });

    try {
      final success = await subscriptionService.createPremiumSubscription();
      
      if (success) {
        ShowToast().showNormalToast(
          msg: '🎉 Welcome to Premium! You can now create events.',
        );
        
        // Refresh the UI
        setState(() {});
      } else {
        ShowToast().showNormalToast(
          msg: 'Failed to activate premium subscription. Please try again.',
        );
      }
    } catch (e) {
      ShowToast().showNormalToast(
        msg: 'An error occurred. Please try again later.',
      );
    } finally {
      setState(() {
        _isUpgrading = false;
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
