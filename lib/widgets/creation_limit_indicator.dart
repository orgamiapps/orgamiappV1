import 'package:flutter/material.dart';
import 'package:attendus/Services/creation_limit_service.dart';
import 'package:attendus/Services/subscription_service.dart';

/// Modern, beautiful widget to display creation limits
/// Shows remaining events/groups for free users
/// Shows "Premium" badge for premium users
class CreationLimitIndicator extends StatelessWidget {
  final CreationType type;
  final bool compact;
  final bool showUpgradeHint;

  const CreationLimitIndicator({
    super.key,
    required this.type,
    this.compact = false,
    this.showUpgradeHint = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        CreationLimitService(),
        SubscriptionService(),
      ]),
      builder: (context, _) {
        final limitService = CreationLimitService();
        final subscriptionService = SubscriptionService();

        if (subscriptionService.hasPremium) {
          return _buildPremiumBadge(context);
        }

        return compact
            ? _buildCompactIndicator(context, limitService)
            : _buildFullIndicator(context, limitService);
      },
    );
  }

  Widget _buildPremiumBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.star_rounded,
            size: 16,
            color: Colors.white,
          ),
          SizedBox(width: 4),
          Text(
            'Premium',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactIndicator(
    BuildContext context,
    CreationLimitService limitService,
  ) {
    final remaining = type == CreationType.event
        ? limitService.eventsRemaining
        : limitService.groupsRemaining;
    
    final isLow = remaining <= 1;
    final color = isLow ? const Color(0xFFEF4444) : const Color(0xFF6366F1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLow ? Icons.warning_rounded : Icons.info_outline_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '$remaining left',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullIndicator(
    BuildContext context,
    CreationLimitService limitService,
  ) {
    final remaining = type == CreationType.event
        ? limitService.eventsRemaining
        : limitService.groupsRemaining;
    
    final progress = type == CreationType.event
        ? limitService.getEventProgress()
        : limitService.getGroupProgress();
    
    final total = type == CreationType.event
        ? CreationLimitService.freeEventLimit
        : CreationLimitService.freeGroupLimit;
    
    final created = total - remaining;
    final isLow = remaining <= 1;
    final typeName = type == CreationType.event ? 'Events' : 'Groups';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
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
                  color: isLow
                      ? const Color(0xFFFEF2F2)
                      : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  type == CreationType.event
                      ? Icons.event_rounded
                      : Icons.group_rounded,
                  size: 20,
                  color: isLow
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$typeName Created',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '$created',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        Text(
                          ' / $total',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isLow)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Low',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFF3F4F6),
              valueColor: AlwaysStoppedAnimation<Color>(
                isLow ? const Color(0xFFEF4444) : const Color(0xFF6366F1),
              ),
            ),
          ),
          if (showUpgradeHint && remaining <= 2) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 16,
                    color: Color(0xFF92400E),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Upgrade to Premium for unlimited creations',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum CreationType {
  event,
  group,
}

