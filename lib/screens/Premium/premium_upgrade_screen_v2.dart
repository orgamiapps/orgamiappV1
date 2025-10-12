import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/Services/payment_placeholder_service.dart';
import 'package:attendus/models/subscription_model.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/screens/Premium/subscription_management_screen.dart';

class PremiumUpgradeScreenV2 extends StatefulWidget {
  const PremiumUpgradeScreenV2({super.key});

  @override
  State<PremiumUpgradeScreenV2> createState() => _PremiumUpgradeScreenV2State();
}

class _PremiumUpgradeScreenV2State extends State<PremiumUpgradeScreenV2>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  int _selectedBillingIndex = 0; // 0 = Monthly, 1 = 6-month, 2 = Annual
  bool _isProcessing = false;
  bool _isNavigating = false;

  static const List<String> billingPeriods = ['Monthly', '6 Months', 'Annual'];
  static const List<String> billingDescriptions = [
    'Billed monthly',
    'Billed every 6 months',
    'Billed annually',
  ];

  @override
  void initState() {
    super.initState();
    _setupAnimations();

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
      canPop: !_isProcessing && !_isNavigating,
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
    return Consumer<SubscriptionService>(
      builder: (context, subscriptionService, child) {
        if (subscriptionService.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        // If user already has an active subscription, redirect to management
        if (subscriptionService.hasPremium) {
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
              _buildTitle(),
              const SizedBox(height: 16),
              _buildSubtitle(),
              const SizedBox(height: 32),
              _buildPricingToggle(),
              const SizedBox(height: 24),
              _buildPlanCards(),
              const SizedBox(height: 32),
              _buildFeatureComparison(),
              const SizedBox(height: 24),
              _buildDisclaimer(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      'Choose Your Plan',
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
      'Unlock powerful features to grow your events',
      style: TextStyle(
        fontSize: 16,
        color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.9),
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildPricingToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(3, (index) {
          final isSelected = _selectedBillingIndex == index;
          final hasSavings = index > 0;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedBillingIndex = index;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  children: [
                    Text(
                      billingPeriods[index],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (hasSavings) ...[
                      const SizedBox(height: 4),
                      Text(
                        index == 1 ? 'Save 17%' : 'Save 27%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? Colors.green.shade700
                              : Colors.green.shade200,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPlanCards() {
    return Row(
      children: [
        Expanded(
          child: _buildPlanCard(
            tier: SubscriptionTier.basic,
            isPopular: false,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildPlanCard(
            tier: SubscriptionTier.premium,
            isPopular: true,
          ),
        ),
      ],
    );
  }

  Widget _buildPlanCard({
    required SubscriptionTier tier,
    required bool isPopular,
  }) {
    final isBasic = tier == SubscriptionTier.basic;
    final prices = isBasic
        ? SubscriptionService.basicPrices
        : SubscriptionService.premiumPrices;
    final price = prices[_selectedBillingIndex] / 100;

    final features = isBasic
        ? [
            '5 events/month',
            'RSVP tracking',
            'Attendance sheet',
            'Event sharing',
          ]
        : [
            'Unlimited events',
            'Event analytics',
            'Create groups',
            'Priority support',
          ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isPopular
            ? Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 3,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isPopular)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.secondary,
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(17),
                  topRight: Radius.circular(17),
                ),
              ),
              child: const Text(
                'MOST POPULAR',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  tier.displayName,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '\$',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Text(
                      price.toStringAsFixed(0),
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                Text(
                  billingDescriptions[_selectedBillingIndex],
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ...features.map((feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: isBasic
                                ? Colors.blue
                                : Theme.of(context).colorScheme.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feature,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isProcessing
                        ? null
                        : () => _handlePlanSelection(tier),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPopular
                          ? Theme.of(context).colorScheme.primary
                          : Colors.blue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Choose Plan',
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
      ),
    );
  }

  Widget _buildFeatureComparison() {
    return Container(
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
          Text(
            'Feature Comparison',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _buildComparisonRow('Browse & RSVP to events', true, true, true),
          _buildComparisonRow('Create events', true, true, true),
          _buildComparisonRow('Event limit', '5 lifetime', '5/month', 'Unlimited'),
          _buildComparisonRow('Attendance tracking', true, true, true),
          _buildComparisonRow('Event analytics', false, false, true),
          _buildComparisonRow('Create groups', false, false, true),
          _buildComparisonRow('Priority support', false, false, true),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(String feature, dynamic free, dynamic basic, dynamic premium) {
    Widget buildCell(dynamic value) {
      if (value is bool) {
        return value
            ? const Icon(Icons.check, color: Colors.green, size: 18)
            : const Icon(Icons.close, color: Colors.red, size: 18);
      } else {
        return Text(
          value.toString(),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              feature,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Center(child: buildCell(free)),
          ),
          Expanded(
            child: Center(child: buildCell(basic)),
          ),
          Expanded(
            child: Center(child: buildCell(premium)),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimer() {
    return Text(
      'For testing purposes, this will activate a free subscription. Payment integration will be added later.',
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7),
        fontStyle: FontStyle.italic,
      ),
      textAlign: TextAlign.center,
    );
  }

  Future<void> _handlePlanSelection(SubscriptionTier tier) async {
    if (!mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Calculate price based on tier and billing period
      final double basePrice = tier == SubscriptionTier.basic ? 2.99 : 4.99;
      final double amount = _selectedBillingIndex == 0
          ? basePrice
          : _selectedBillingIndex == 1
              ? basePrice * 6 * 0.9 // 10% discount for 6 months
              : basePrice * 12 * 0.8; // 20% discount for annual

      final String productName = '${tier.displayName} ${billingPeriods[_selectedBillingIndex]}';

      // Show Apple Pay placeholder UI
      final paymentSuccess = await PaymentPlaceholderService().showApplePayPlaceholder(
        context: context,
        productName: productName,
        amount: amount,
        currency: 'USD',
      );

      if (!mounted) return;

      if (!paymentSuccess) {
        // User cancelled payment
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      // Payment successful, create subscription
      final subscriptionService = context.read<SubscriptionService>();

      // Determine plan ID based on tier and billing period
      final tierPrefix = tier == SubscriptionTier.basic ? 'basic' : 'premium';
      final billingSuffix = _selectedBillingIndex == 0
          ? 'monthly'
          : _selectedBillingIndex == 1
              ? '6month'
              : 'yearly';
      final planId = '${tierPrefix}_$billingSuffix';

      final success = await subscriptionService.createPremiumSubscription(
        planId: planId,
        tier: tier,
      );

      if (!mounted) return;

      if (success) {
        ShowToast().showNormalToast(
          msg: '🎉 Welcome to ${tier.displayName}! You can now enjoy your benefits.',
        );

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
          msg: 'Failed to activate subscription. Please try again.',
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
          _isProcessing = false;
        });
      }
    }
  }
}

