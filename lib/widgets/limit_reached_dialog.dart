import 'package:flutter/material.dart';
import 'package:attendus/screens/Premium/premium_upgrade_screen_v2.dart';
import 'package:attendus/Utils/router.dart';

/// Beautiful dialog shown when user reaches creation limit
/// Encourages upgrade to premium with modern UI/UX
class LimitReachedDialog extends StatelessWidget {
  final String type; // 'event' or 'group'
  final int limit;

  const LimitReachedDialog({
    super.key,
    required this.type,
    required this.limit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEvent = type.toLowerCase() == 'event';
    final typeName = isEvent ? 'Events' : 'Groups';
    final icon = isEvent ? Icons.event_rounded : Icons.group_rounded;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
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
                    theme.colorScheme.primary.withValues(alpha: 0.82),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
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
                    child: Icon(icon, size: 40, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Creation Limit Reached',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You\'ve created $limit $typeName',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w500,
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
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Free Plan Limit',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$limit',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              typeName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Upgrade to Premium for:',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem(
                    icon: Icons.all_inclusive_rounded,
                    text: 'Unlimited $typeName',
                    color: const Color(0xFF6366F1),
                  ),
                  const SizedBox(height: 8),
                  _buildFeatureItem(
                    icon: Icons.analytics_outlined,
                    text: 'Advanced Analytics',
                    color: const Color(0xFF8B5CF6),
                  ),
                  const SizedBox(height: 8),
                  _buildFeatureItem(
                    icon: Icons.support_agent_rounded,
                    text: 'Priority Support',
                    color: const Color(0xFFEC4899),
                  ),
                  const SizedBox(height: 8),
                  _buildFeatureItem(
                    icon: Icons.star_rounded,
                    text: 'Exclusive Features',
                    color: const Color(0xFFF59E0B),
                  ),
                ],
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
              child: Column(
                children: [
                  // Upgrade button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        RouterClass.nextScreenNormal(
                          context,
                          const PremiumUpgradeScreenV2(),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.star_rounded, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Upgrade to Premium',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Cancel button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Maybe Later',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF374151),
          ),
        ),
      ],
    );
  }

  /// Static method to show the dialog
  static Future<void> show(
    BuildContext context, {
    required String type,
    required int limit,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => LimitReachedDialog(type: type, limit: limit),
    );
  }
}
