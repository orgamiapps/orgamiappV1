import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';
import 'package:attendus/screens/Home/analytics_dashboard_screen.dart';
import 'package:attendus/screens/Home/attendee_notification_screen.dart';
import 'package:attendus/Utils/router.dart';

class PremiumFeaturesScreen extends StatefulWidget {
  const PremiumFeaturesScreen({super.key});

  @override
  State<PremiumFeaturesScreen> createState() => _PremiumFeaturesScreenState();
}

class _PremiumFeaturesScreenState extends State<PremiumFeaturesScreen> {
  bool _isLoading = true;
  bool _hasPremium = false;

  @override
  void initState() {
    super.initState();
    _checkPremiumAccess();
  }

  Future<void> _checkPremiumAccess() async {
    try {
      final subscriptionService = Provider.of<SubscriptionService>(
        context,
        listen: false,
      );

      // Initialize if not already done
      await subscriptionService.initialize();
      await subscriptionService.refresh();

      setState(() {
        _hasPremium = subscriptionService.hasPremium;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              AppAppBarView.modernHeader(
                context: context,
                title: 'Premium Features',
                subtitle: 'Unlock powerful tools and insights',
              ),
              const Expanded(child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
      );
    }

    if (!_hasPremium) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              AppAppBarView.modernHeader(
                context: context,
                title: 'Premium Features',
                subtitle: 'Unlock powerful tools and insights',
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.workspace_premium,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Premium Only',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You need an active Premium subscription to access these features.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.color,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Go Back'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppAppBarView.modernHeader(
              context: context,
              title: 'Premium Features',
              subtitle: 'Unlock powerful tools and insights',
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Analytics & Insights
                    _buildSectionHeader(
                      title: 'Analytics & Insights',
                      icon: Icons.analytics,
                      color: const Color(0xFF667EEA),
                    ),
                    const SizedBox(height: 12),
                    _buildCompactActionsGrid([
                      _PremiumFeatureAction(
                        icon: Icons.analytics_rounded,
                        title: 'Analytics Dashboard',
                        subtitle: 'Comprehensive Insights',
                        color: const Color(0xFF667EEA),
                        onTap: () => _openAnalyticsDashboard(),
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // Communication Tools
                    _buildSectionHeader(
                      title: 'Communication',
                      icon: Icons.campaign,
                      color: const Color(0xFF10B981),
                    ),
                    const SizedBox(height: 12),
                    _buildCompactActionsGrid([
                      _PremiumFeatureAction(
                        icon: Icons.sms_rounded,
                        title: 'Send Notifications',
                        subtitle: 'SMS & In-App Alerts',
                        color: const Color(0xFF10B981),
                        onTap: () => _openSendNotifications(),
                      ),
                    ]),

                    const SizedBox(height: 32), // Extra space at bottom
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            color: theme.textTheme.titleLarge?.color ?? const Color(0xFF1A1A1A),
            fontWeight: FontWeight.w700,
            fontSize: 18,
            fontFamily: 'Roboto',
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactActionsGrid(List<_PremiumFeatureAction> actions) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.15,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        return _buildCompactActionCard(action);
      },
    );
  }

  Widget _buildCompactActionCard(_PremiumFeatureAction action) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: action.color.withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.04),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: action.onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon with background
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: action.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(action.icon, color: action.color, size: 24),
                      // Premium badge overlay
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark ? theme.cardColor : Colors.white,
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.star,
                            color: Colors.white,
                            size: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Title
                Text(
                  action.title,
                  style: TextStyle(
                    color:
                        theme.textTheme.titleMedium?.color ??
                        const Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    fontFamily: 'Roboto',
                    letterSpacing: -0.1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Subtitle
                Text(
                  action.subtitle,
                  style: TextStyle(
                    color:
                        theme.textTheme.bodyMedium?.color ??
                        const Color(0xFF6B7280),
                    fontSize: 12,
                    fontFamily: 'Roboto',
                    letterSpacing: 0.1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openAnalyticsDashboard() {
    RouterClass.nextScreenNormal(context, const AnalyticsDashboardScreen());
  }

  void _openSendNotifications() {
    RouterClass.nextScreenNormal(context, const AttendeeNotificationScreen());
  }
}

/// Premium feature action class for the grid-based interface
class _PremiumFeatureAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _PremiumFeatureAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });
}
