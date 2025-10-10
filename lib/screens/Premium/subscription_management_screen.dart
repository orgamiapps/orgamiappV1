import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:intl/intl.dart';

class SubscriptionManagementScreen extends StatefulWidget {
  const SubscriptionManagementScreen({super.key});

  @override
  State<SubscriptionManagementScreen> createState() =>
      _SubscriptionManagementScreenState();
}

class _SubscriptionManagementScreenState
    extends State<SubscriptionManagementScreen> {
  bool _isLoading = false;
  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_isLoading && !_isNavigating,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _isNavigating = true;
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              AppAppBarView.modernHeader(
                context: context,
                title: 'Manage Subscription',
                subtitle: 'View and update your plan',
                trailing: _buildPremiumBadge(theme),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.colorScheme.primary.withValues(
                          alpha: theme.brightness == Brightness.dark
                              ? 0.18
                              : 0.08,
                        ),
                        theme.scaffoldBackgroundColor,
                      ],
                    ),
                  ),
                  child: _buildBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.workspace_premium_rounded,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            'Premium',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Consumer<SubscriptionService>(
      builder: (context, subscriptionService, child) {
        if (subscriptionService.isLoading || _isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final subscription = subscriptionService.currentSubscription;
        if (subscription == null) {
          return _buildNoSubscription();
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeaderCard(subscription, subscriptionService),
              const SizedBox(height: 20),
              _buildPlanSummaryCard(subscription, subscriptionService),
              const SizedBox(height: 20),
              _buildBenefitsCard(),
              const SizedBox(height: 20),
              _buildPlanOptionsCard(subscription),
              const SizedBox(height: 20),
              _buildManageCard(subscription, subscriptionService),
              const SizedBox(height: 20),
              _buildBillingHistoryPlaceholder(),
              const SizedBox(height: 24),
              _buildSupportSection(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoSubscription() {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.workspace_premium_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No active subscription',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You do not currently have a premium plan. Return to explore premium options.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to premium'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    dynamic subscription,
    SubscriptionService subscriptionService,
  ) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(subscription.status);
    final isTrial = subscription.isTrial && subscription.trialEndsAt != null;
    final nextLabel = isTrial
        ? 'Trial ends ${_formatDate(subscription.trialEndsAt!)}'
        : 'Renews ${subscriptionService.getNextBillingDate() ?? 'soon'}';

    return Card(
      elevation: 3,
      shadowColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      color: theme.colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor.withValues(alpha: 0.2),
                  ),
                  child: Icon(
                    _getStatusIcon(subscription.status),
                    color: statusColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Split plan name into two lines: "Premium" and duration
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Premium',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            _getPlanDuration(subscription.planDisplayName),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onPrimaryContainer
                                  .withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subscriptionService.getSubscriptionStatusText(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _getDisplayPrice(subscription),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onPrimaryContainer,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getDisplayInterval(subscription),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildSummaryChip(
                  icon: Icons.calendar_month_outlined,
                  label: nextLabel,
                ),
                _buildSummaryChip(
                  icon: Icons.event_available_outlined,
                  label: 'Member since ${_formatDate(subscription.createdAt)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanSummaryCard(
    dynamic subscription,
    SubscriptionService subscriptionService,
  ) {
    String billingValue;
    switch (subscription.planId) {
      case 'premium_monthly':
        billingValue = '\$20.00/month';
        break;
      case 'premium_6month':
        billingValue = '\$100.00 every 6 months';
        break;
      case 'premium_yearly':
        billingValue = '\$175.00/year';
        break;
      default:
        billingValue =
            '${subscription.formattedPrice}/${subscription.intervalDisplayText}';
    }

    final details = <({String label, String value})>[
      (label: 'Plan', value: subscription.planDisplayName),
      (label: 'Billing', value: billingValue),
      (
        label: 'Current period',
        value:
            '${_formatDate(subscription.currentPeriodStart)} – ${_formatDate(subscription.currentPeriodEnd)}',
      ),
      (
        label: 'Next renewal',
        value: subscriptionService.getNextBillingDate() ?? 'Pending',
      ),
      if (subscription.savingsPercentage != null)
        (
          label: 'Savings',
          value: 'You save ${subscription.savingsPercentage} vs monthly',
        ),
      if (subscription.hasScheduledPlanChange)
        (
          label: 'Scheduled plan',
          value:
              '${subscription.scheduledPlanDisplayName} starting ${_formatDate(subscription.scheduledPlanStartDate!)}',
        ),
      if (subscription.cancelledAt != null)
        (label: 'Cancelled on', value: _formatDate(subscription.cancelledAt!)),
    ];

    return _buildSectionCard(
      title: 'Plan details',
      children: [
        for (int i = 0; i < details.length; i++) ...[
          _buildInfoRow(label: details[i].label, value: details[i].value),
          if (i != details.length - 1) const Divider(height: 24),
        ],
      ],
    );
  }

  Widget _buildBenefitsCard() {
    final theme = Theme.of(context);
    final benefits = <({IconData icon, String title, String subtitle})>[
      (
        icon: Icons.event_available_outlined,
        title: 'Unlimited events',
        subtitle: 'Launch as many events as your team needs.',
      ),
      (
        icon: Icons.query_stats_outlined,
        title: 'Advanced analytics',
        subtitle: 'Understand performance with deeper insights.',
      ),
      (
        icon: Icons.support_agent_outlined,
        title: 'Priority support',
        subtitle: 'Reach our dedicated team when you need help.',
      ),
    ];

    return _buildSectionCard(
      title: 'What you get',
      children: benefits
          .map(
            (benefit) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: theme.brightness == Brightness.dark ? 0.4 : 0.3,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      benefit.icon,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          benefit.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          benefit.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildPlanOptionsCard(dynamic subscription) {
    final theme = Theme.of(context);
    final currentPlanId = subscription.planId;
    final scheduledPlanId = subscription.scheduledPlanId;
    final hasScheduledChange = subscription.hasScheduledPlanChange;

    final plans = [
      {
        'id': 'premium_monthly',
        'name': 'Monthly',
        'price': '\$20.00/mo',
        'description': 'Flexible monthly plan',
      },
      {
        'id': 'premium_6month',
        'name': '6 Months',
        'price': '\$100.00',
        'description': 'Save 17% • \$16.67/mo',
        'badge': 'SAVE 17%',
      },
      {
        'id': 'premium_yearly',
        'name': 'Annual',
        'price': '\$175.00',
        'description': 'Save 27% • \$14.58/mo',
        'badge': 'BEST VALUE',
      },
    ];

    return _buildSectionCard(
      title: 'Available plans',
      children: [
        Text(
          'Compare pricing options to find the best fit for you.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        ...plans.map((plan) {
          final isCurrent = plan['id'] == currentPlanId;
          final isScheduled = plan['id'] == scheduledPlanId;
          final planId = plan['id'] as String;

          return GestureDetector(
            onTap: isCurrent ? null : () => _handlePlanSelection(planId),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isCurrent
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : isScheduled
                    ? theme.colorScheme.secondaryContainer.withValues(
                        alpha: 0.3,
                      )
                    : theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.3,
                      ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isCurrent
                      ? theme.colorScheme.primary
                      : isScheduled
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.outline.withValues(alpha: 0.2),
                  width: (isCurrent || isScheduled) ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              plan['name'] as String,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isCurrent)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'CURRENT',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            if (isScheduled)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.secondary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'SCHEDULED',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            if (!isCurrent &&
                                !isScheduled &&
                                plan['badge'] != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  plan['badge'] as String,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          plan['description'] as String,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        plan['price'] as String,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      if (!isCurrent) const SizedBox(height: 4),
                      if (!isCurrent)
                        Text(
                          'Tap to select',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        if (hasScheduledChange)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withValues(
                alpha: 0.3,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.secondary.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 16,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your plan will change to ${subscription.scheduledPlanDisplayName} on ${_formatDate(subscription.scheduledPlanStartDate!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _cancelScheduledPlanChange,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (!hasScheduledChange)
          Text(
            'Select a plan to schedule a change after your current billing period ends.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }

  Widget _buildManageCard(
    dynamic subscription,
    SubscriptionService subscriptionService,
  ) {
    final theme = Theme.of(context);
    final isActive = subscription.status == 'active';
    final helperText = isActive
        ? 'You will keep access until the end of the current billing period.'
        : 'Restore premium features immediately.';

    return _buildSectionCard(
      title: 'Manage subscription',
      children: [
        Text(
          helperText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: isActive
                ? () => _showCancelConfirmation(subscriptionService)
                : () => _reactivateSubscription(subscriptionService),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(
              isActive ? 'Cancel subscription' : 'Reactivate subscription',
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _showComingSoon('Payment method updates'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Update payment method'),
          ),
        ),
      ],
    );
  }

  Widget _buildBillingHistoryPlaceholder() {
    final theme = Theme.of(context);

    return _buildSectionCard(
      title: 'Billing history',
      children: [
        Text(
          'Billing receipts will appear here once available. You can download invoices and review renewals in this space.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildSupportSection() {
    final theme = Theme.of(context);

    return _buildSectionCard(
      title: 'Need a hand?',
      children: [
        Text(
          'Our support team is here to help with any billing or plan questions.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showComingSoon('Support chat'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Message support'),
          ),
        ),
      ],
    );
  }

  Future<void> _showCancelConfirmation(
    SubscriptionService subscriptionService,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Subscription'),
        content: const Text(
          'Are you sure you want to cancel your premium subscription? '
          'You will lose access to premium features at the end of your current billing period.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Subscription'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel Subscription'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _cancelSubscription(subscriptionService);
    }
  }

  Future<void> _cancelSubscription(
    SubscriptionService subscriptionService,
  ) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await subscriptionService.cancelSubscription();

      if (!mounted) return;

      if (success) {
        ShowToast().showNormalToast(
          msg: 'Subscription cancelled successfully.',
        );
      } else {
        ShowToast().showNormalToast(
          msg: 'Failed to cancel subscription. Please try again.',
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
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _reactivateSubscription(
    SubscriptionService subscriptionService,
  ) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await subscriptionService.reactivateSubscription();

      if (!mounted) return;

      if (success) {
        ShowToast().showNormalToast(
          msg: 'Subscription reactivated successfully!',
        );
      } else {
        ShowToast().showNormalToast(
          msg: 'Failed to reactivate subscription. Please try again.',
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
          _isLoading = false;
        });
      }
    }
  }

  void _showComingSoon(String feature) {
    ShowToast().showNormalToast(msg: '$feature will be available soon!');
  }

  Future<void> _handlePlanSelection(String planId) async {
    final subscriptionService = Provider.of<SubscriptionService>(
      context,
      listen: false,
    );
    final subscription = subscriptionService.currentSubscription;

    if (subscription == null) return;

    // If there's already a scheduled plan change, show different dialog
    if (subscription.hasScheduledPlanChange) {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change Scheduled Plan'),
          content: Text(
            'You already have a plan change scheduled to ${subscription.scheduledPlanDisplayName}. '
            'Would you like to replace it with the new plan?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Update Plan'),
            ),
          ],
        ),
      );

      if (result == true) {
        await _schedulePlanChange(planId);
      }
    } else {
      // Show confirmation dialog for new plan change
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Schedule Plan Change'),
          content: Text(
            'Your plan will automatically change after your current billing period ends on ${_formatDate(subscription.currentPeriodEnd)}. '
            'You will continue to have access with your current plan until then.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Schedule Change'),
            ),
          ],
        ),
      );

      if (result == true) {
        await _schedulePlanChange(planId);
      }
    }
  }

  Future<void> _schedulePlanChange(String planId) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final subscriptionService = Provider.of<SubscriptionService>(
        context,
        listen: false,
      );
      final success = await subscriptionService.schedulePlanChange(planId);

      if (!mounted) return;

      if (success) {
        ShowToast().showNormalToast(msg: 'Plan change scheduled successfully!');
      } else {
        ShowToast().showNormalToast(
          msg: 'Failed to schedule plan change. Please try again.',
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
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _cancelScheduledPlanChange() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Scheduled Change'),
        content: const Text(
          'Are you sure you want to cancel the scheduled plan change? '
          'Your current plan will continue to renew as normal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Scheduled Change'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel Change'),
          ),
        ],
      ),
    );

    if (result == true) {
      if (!mounted) return;

      setState(() {
        _isLoading = true;
      });

      try {
        final subscriptionService = Provider.of<SubscriptionService>(
          context,
          listen: false,
        );
        final success = await subscriptionService.cancelScheduledPlanChange();

        if (!mounted) return;

        if (success) {
          ShowToast().showNormalToast(msg: 'Scheduled plan change cancelled.');
        } else {
          ShowToast().showNormalToast(
            msg: 'Failed to cancel scheduled change. Please try again.',
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
            _isLoading = false;
          });
        }
      }
    }
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark
        ? Color.alphaBlend(
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            theme.colorScheme.surface,
          )
        : theme.colorScheme.surface;
    final borderColor = theme.colorScheme.outline.withValues(
      alpha: isDark ? 0.2 : 0.08,
    );

    return Card(
      elevation: isDark ? 1 : 3,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({required String label, required String value}) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryChip({required IconData icon, required String label}) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.onPrimaryContainer.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.2 : 0.12,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return const Color(0xFF667EEA);
      case 'cancelled':
        return Colors.orange;
      case 'past_due':
        return Colors.red;
      case 'incomplete':
        return Colors.yellow;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'active':
        return Icons.verified;
      case 'cancelled':
        return Icons.cancel;
      case 'past_due':
        return Icons.warning;
      case 'incomplete':
        return Icons.hourglass_empty;
      default:
        return Icons.help;
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('MM/dd/yyyy').format(date);
  }

  String _getPlanDuration(String planDisplayName) {
    // Extract duration from plan name (e.g., "Premium Monthly" -> "Monthly")
    final parts = planDisplayName.split(' ');
    if (parts.length > 1) {
      // Return everything after "Premium"
      return parts.sublist(1).join(' ');
    }
    return 'Monthly'; // Default fallback
  }

  /// Get the display price based on the subscription plan
  String _getDisplayPrice(dynamic subscription) {
    switch (subscription.planId) {
      case 'premium_monthly':
        return '\$20.00';
      case 'premium_6month':
        return '\$100.00';
      case 'premium_yearly':
        return '\$175.00';
      default:
        return subscription.formattedPrice;
    }
  }

  /// Get the display interval based on the subscription plan
  String _getDisplayInterval(dynamic subscription) {
    switch (subscription.planId) {
      case 'premium_monthly':
        return 'per month';
      case 'premium_6month':
        return 'every 6 months';
      case 'premium_yearly':
        return 'per year';
      default:
        return 'per ${subscription.intervalDisplayText}';
    }
  }
}
