import 'package:flutter/material.dart';
import 'package:attendus/models/subscription_model.dart';
import 'package:attendus/screens/Premium/premium_upgrade_screen_v2.dart';

class UpgradePromptDialog {
  /// Show analytics upgrade prompt
  static Future<void> showAnalyticsUpgrade(BuildContext context) async {
    return _showUpgradeDialog(
      context: context,
      title: 'Analytics Requires Premium',
      description:
          'Get detailed insights about your events with Premium. Track attendance trends, view demographics, and optimize your events.',
      icon: Icons.analytics,
      features: [
        'Detailed attendance analytics',
        'Demographic insights',
        'Engagement metrics',
        'Export reports',
        'Trend analysis',
      ],
    );
  }

  /// Show groups upgrade prompt
  static Future<void> showGroupsUpgrade(BuildContext context) async {
    return _showUpgradeDialog(
      context: context,
      title: 'Group Creation Requires Premium',
      description:
          'Create and manage unlimited groups with Premium. Organize your community, manage members, and host exclusive events.',
      icon: Icons.group,
      features: [
        'Create unlimited groups',
        'Member management',
        'Group analytics',
        'Private group events',
        'Admin controls',
      ],
    );
  }

  /// Show unlimited events upgrade prompt
  static Future<void> showUnlimitedEventsUpgrade(
    BuildContext context, {
    required SubscriptionTier currentTier,
  }) async {
    final isBasic = currentTier == SubscriptionTier.basic;
    
    return _showUpgradeDialog(
      context: context,
      title: isBasic ? 'Unlimited Events with Premium' : 'Upgrade to Create More Events',
      description: isBasic
          ? 'Remove the monthly limit and create unlimited events with Premium.'
          : 'Choose a plan to start creating events and building your community.',
      icon: Icons.event,
      features: isBasic
          ? [
              'Unlimited event creation',
              'Full event analytics',
              'Create groups',
              'Priority support',
            ]
          : [
              'Basic: 5 events per month',
              'Premium: Unlimited events',
              'Event analytics (Premium)',
              'Group creation (Premium)',
            ],
    );
  }

  /// Show generic upgrade dialog
  static Future<void> _showUpgradeDialog({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required List<String> features,
  }) async {
    final theme = Theme.of(context);

    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with gradient
                Container(
                  padding: const EdgeInsets.all(24),
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
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                // Content
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Premium Features:',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...features.map((feature) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.check,
                                    size: 14,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    feature,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          )),
                      const SizedBox(height: 24),

                      // Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: BorderSide(
                                  color: theme.colorScheme.outline,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Maybe Later'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const PremiumUpgradeScreenV2(),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Upgrade Now',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

