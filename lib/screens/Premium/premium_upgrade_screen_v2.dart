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

  int _selectedBillingIndex =
      2; // 0 = Monthly, 1 = 6-month, 2 = Annual (default to best value)
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
        backgroundColor: const Color(0xFFF8F9FA),
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16.0, top: 8.0),
                  child: AppAppBarView.modernBackButton(
                    context: context,
                    backgroundColor: Colors.white,
                    iconColor: Colors.grey.shade800,
                  ),
                ),
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Consumer<SubscriptionService>(
      builder: (context, subscriptionService, child) {
        if (subscriptionService.isLoading) {
          return const Center(child: CircularProgressIndicator());
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
          return const Center(child: CircularProgressIndicator());
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
              const SizedBox(height: 16),
              _buildTitle(),
              const SizedBox(height: 12),
              _buildSubtitle(),
              const SizedBox(height: 24),
              _buildPricingToggle(),
              const SizedBox(height: 24),
              _buildPlanCards(),
              const SizedBox(height: 24),
              _buildDisclaimer(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      'Unlock Your Potential',
      style: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade900,
        letterSpacing: 0.5,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSubtitle() {
    return Text(
      'Choose the plan that fits your needs.\nCancel anytime.',
      style: TextStyle(fontSize: 16, height: 1.5, color: Colors.grey.shade600),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildPricingToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: List.generate(3, (index) {
          final isSelected = _selectedBillingIndex == index;
          final isBestValue = index == 2;

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
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withAlpha(26),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      billingPeriods[index],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (isBestValue) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Best Value',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Colors.deepOrange.shade600
                              : Colors.orange.shade700,
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
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildPlanCard(tier: SubscriptionTier.basic)),
          const SizedBox(width: 16),
          Expanded(child: _buildPlanCard(tier: SubscriptionTier.premium)),
        ],
      ),
    );
  }

  Widget _buildPlanCard({required SubscriptionTier tier}) {
    final isBasic = tier == SubscriptionTier.basic;
    final isPremium = !isBasic;
    final prices = isBasic
        ? SubscriptionService.basicPrices
        : SubscriptionService.premiumPrices;
    final price = prices[_selectedBillingIndex] / 100;

    final features = isBasic
        ? [
            '5 events per month',
            'Track RSVPs easily',
            'Manage attendance',
            'Share events',
          ]
        : [
            'Unlimited events',
            'Deep analytics & insights',
            'Create & manage groups',
            'Priority support 24/7',
          ];

    final ctaText = isBasic ? 'Choose Basic' : 'Choose Premium';
    final cardColor = Colors.white;
    final textColor = Colors.grey.shade800;
    final priceColor = Theme.of(context).colorScheme.primary;
    final buttonStyle = isPremium
        ? ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          )
        : ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Theme.of(context).colorScheme.primary,
            side: BorderSide(
              color: Theme.of(context).colorScheme.primary.withAlpha(128),
              width: 1.5,
            ),
          );

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: isPremium
            ? Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2.0,
              )
            : Border.all(color: Colors.grey.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 25,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              tier.displayName,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: isPremium
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    '\$',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: priceColor,
                    ),
                  ),
                ),
                Text(
                  price.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: priceColor,
                    height: 1.0,
                  ),
                ),
              ],
            ),
            Text(
              billingDescriptions[_selectedBillingIndex],
              style: TextStyle(
                fontSize: 12,
                color: textColor.withAlpha(179),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ...features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check, color: Colors.blue.shade600, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        feature,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing
                    ? null
                    : () => _handlePlanSelection(tier),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ).merge(buttonStyle),
                child: _isProcessing
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isPremium
                              ? Colors.white
                              : Theme.of(context).colorScheme.primary,
                        ),
                      )
                    : Text(
                        ctaText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisclaimer() {
    return Text(
      '🔒 Secure Payments • Cancel Anytime',
      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
          ? basePrice *
                6 *
                0.9 // 10% discount for 6 months
          : basePrice * 12 * 0.8; // 20% discount for annual

      final String productName =
          '${tier.displayName} ${billingPeriods[_selectedBillingIndex]}';

      // Show Apple Pay placeholder UI
      final paymentSuccess = await PaymentPlaceholderService()
          .showApplePayPlaceholder(
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
          msg:
              '🎉 Welcome to ${tier.displayName}! You can now enjoy your benefits.',
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
