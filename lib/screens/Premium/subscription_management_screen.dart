import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';
import 'package:attendus/Utils/toast.dart';

class SubscriptionManagementScreen extends StatefulWidget {
  const SubscriptionManagementScreen({super.key});

  @override
  State<SubscriptionManagementScreen> createState() =>
      _SubscriptionManagementScreenState();
}

class _SubscriptionManagementScreenState
    extends State<SubscriptionManagementScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                AppAppBarView.appBarView(
                  context: context,
                  title: 'Manage Subscription',
                ),
                Expanded(child: _buildBody()),
              ],
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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSubscriptionOverview(subscription, subscriptionService),
              const SizedBox(height: 24),
              _buildSubscriptionDetails(subscription),
              const SizedBox(height: 24),
              _buildManagementActions(subscription, subscriptionService),
              const SizedBox(height: 24),
              _buildBillingHistory(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoSubscription() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.card_membership,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No Active Subscription',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'You don\'t have an active subscription.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to Premium'),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionOverview(
    subscription,
    SubscriptionService subscriptionService,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 10,
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
                  color: _getStatusColor(
                    subscription.status,
                  ).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getStatusIcon(subscription.status),
                  color: _getStatusColor(subscription.status),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subscriptionService.getSubscriptionStatusText(),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subscription.planDisplayName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                subscription.formattedPrice,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (subscription.isTrial && subscription.trialEndsAt != null)
            _buildInfoRow(
              'Trial Ends',
              _formatDate(subscription.trialEndsAt!),
              Icons.schedule,
            )
          else
            _buildInfoRow(
              'Next Billing',
              subscriptionService.getNextBillingDate() ?? 'N/A',
              Icons.calendar_today,
            ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionDetails(subscription) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Subscription Details',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildDetailRow('Plan', subscription.planDisplayName),
          _buildDetailRow('Status', _capitalizeFirst(subscription.status)),
          _buildDetailRow(
            'Price',
            '${subscription.formattedPrice}/${subscription.interval}',
          ),
          _buildDetailRow('Started', _formatDate(subscription.createdAt)),
          _buildDetailRow(
            'Current Period',
            '${_formatDate(subscription.currentPeriodStart)} - ${_formatDate(subscription.currentPeriodEnd)}',
          ),
          if (subscription.cancelledAt != null)
            _buildDetailRow(
              'Cancelled',
              _formatDate(subscription.cancelledAt!),
            ),
        ],
      ),
    );
  }

  Widget _buildManagementActions(
    subscription,
    SubscriptionService subscriptionService,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Manage Your Subscription',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (subscription.status == 'active') ...[
            _buildActionButton(
              'Cancel Subscription',
              'Your subscription will remain active until the end of the current billing period',
              Icons.cancel,
              Colors.orange,
              () => _showCancelConfirmation(subscriptionService),
            ),
          ] else if (subscription.status == 'cancelled') ...[
            _buildActionButton(
              'Reactivate Subscription',
              'Resume your premium subscription',
              Icons.restart_alt,
              Theme.of(context).colorScheme.primary,
              () => _reactivateSubscription(subscriptionService),
            ),
          ],
          const SizedBox(height: 12),
          _buildActionButton(
            'Update Payment Method',
            'Change your payment information (Coming Soon)',
            Icons.payment,
            Theme.of(context).colorScheme.primary,
            () => _showComingSoon('Payment method updates'),
            enabled: false,
          ),
        ],
      ),
    );
  }

  Widget _buildBillingHistory() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Billing History',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            'No billing history available yet. This feature will be added when payment processing is implemented.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    bool enabled = true,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: enabled
              ? color.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: enabled ? color : Colors.grey, size: 20),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: enabled ? null : Colors.grey,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: enabled
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : Colors.grey,
        ),
      ),
      trailing: enabled ? const Icon(Icons.arrow_forward_ios, size: 16) : null,
      onTap: enabled ? onTap : null,
      contentPadding: EdgeInsets.zero,
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
    setState(() {
      _isLoading = true;
    });

    try {
      final success = await subscriptionService.cancelSubscription();

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
      ShowToast().showNormalToast(
        msg: 'An error occurred. Please try again later.',
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _reactivateSubscription(
    SubscriptionService subscriptionService,
  ) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final success = await subscriptionService.reactivateSubscription();

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
      ShowToast().showNormalToast(
        msg: 'An error occurred. Please try again later.',
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showComingSoon(String feature) {
    ShowToast().showNormalToast(msg: '$feature will be available soon!');
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
    return '${date.day}/${date.month}/${date.year}';
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}
