
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/models/subscription_model.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/screens/Premium/subscription_management_screen.dart';

class PremiumUpgradeScreen extends StatefulWidget {
  const PremiumUpgradeScreen({super.key});

  @override
  State<PremiumUpgradeScreen> createState() => _PremiumUpgradeScreenState();
}

// State class for Selector optimization
class _SubscriptionState {
  final bool isLoading;
  final bool hasPremium;
  final SubscriptionModel? subscription;

  const _SubscriptionState({
    required this.isLoading,
    required this.hasPremium,
    this.subscription,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SubscriptionState &&
          runtimeType == other.runtimeType &&
          isLoading == other.isLoading &&
          hasPremium == other.hasPremium &&
          subscription == other.subscription;

  @override
  int get hashCode =>
      isLoading.hashCode ^ hasPremium.hashCode ^ subscription.hashCode;
}

class _PremiumUpgradeScreenState extends State<PremiumUpgradeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isUpgrading = false;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();

    // Initialize subscription service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<SubscriptionService>(context, listen: false).initialize();
      }
    });
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
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
    return PopScope(
      canPop: !_isUpgrading && !_isNavigating,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _isNavigating = true;
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            _buildGradientBackground(),
            SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: AppAppBarView.modernBackButton(
                        context: context,
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        iconColor: Colors.white,
                      ),
                    ),
                  ),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ],
        ),
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
    // Use Selector instead of Consumer for targeted rebuilds
    return Selector<SubscriptionService, _SubscriptionState>(
      selector: (context, service) => _SubscriptionState(
        isLoading: service.isLoading,
        hasPremium: service.hasPremium,
        subscription: service.currentSubscription,
      ),
      builder: (context, state, child) {
        if (state.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        // If user already has premium, navigate to management screen
        if (state.hasPremium) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isNavigating) {
              _isNavigating = true;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const SubscriptionManagementScreen(),
                ),
              );
            }
          });
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        // Show upgrade options
        return _buildUpgradeView();
      },
    );
  }

  Widget _buildUpgradeView() {
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
              _buildUpgradeButton(),
              const SizedBox(height: 8),
              _buildTrialHelperLine(),
              const SizedBox(height: 16),
              _buildDisclaimer(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumIcon() {
    final theme = Theme.of(context);

    // Use RepaintBoundary to avoid repainting this expensive widget
    return RepaintBoundary(
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              theme.colorScheme.secondary,
              theme.colorScheme.primary,
              theme.colorScheme.tertiary,
              theme.colorScheme.secondary,
            ],
            stops: const [0.0, 0.33, 0.66, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 30,
              offset: const Offset(0, 18),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.95),
                Colors.white.withValues(alpha: 0.65),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.workspace_premium,
            size: 56,
            color: Color(0xFF8667F2),
          ),
        ),
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
      'Track attendance',
      'Export attendee data',
      'Sell tickets',
      'Manage events',
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
          // Pre-build feature list to avoid rebuilding on every frame
          ...features.map((feature) => _FeatureItem(feature: feature)),
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
                '5',
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

  Widget _buildUpgradeButton() {
    final subscriptionService = context.read<SubscriptionService>();
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isUpgrading
            ? null
            : () => _handleUpgrade(subscriptionService),
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
                'Start 1-Month Free Trial',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  Widget _buildTrialHelperLine() {
    return Text(
      'Free for 1 month, then \$5/month. Cancel anytime',
      style: TextStyle(
        fontSize: 14,
        color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.9),
      ),
      textAlign: TextAlign.center,
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

  Future<void> _handleUpgrade(SubscriptionService subscriptionService) async {
    if (!mounted) return;

    setState(() {
      _isUpgrading = true;
    });

    try {
      final success = await subscriptionService.createPremiumSubscription();

      if (!mounted) return;

      if (success) {
        ShowToast().showNormalToast(
          msg: '🎉 Welcome to Premium! You can now create events.',
        );

        // Navigate to subscription management screen
        if (mounted) {
          _isNavigating = true;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const SubscriptionManagementScreen(),
            ),
          );
        }
      } else {
        ShowToast().showNormalToast(
          msg: 'Failed to activate premium subscription. Please try again.',
        );
      }
    } catch (e) {
      if (!mounted) return;

      ShowToast().showNormalToast(
        msg: 'An error occurred. Please try again later.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpgrading = false;
        });
      }
    }
  }
}

// Optimized feature item widget - extracted to avoid rebuilding
class _FeatureItem extends StatelessWidget {
  final String feature;

  const _FeatureItem({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF667EEA), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              feature,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(
                  context,
                ).colorScheme.onPrimary.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
