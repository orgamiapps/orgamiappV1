import 'package:flutter/material.dart';
import 'package:attendus/Services/creation_limit_service.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/widgets/limit_reached_dialog.dart';

/// Wrapper widget for create buttons that shows remaining creation count
/// Displays a badge with the number of remaining creations for free users
class CreateButtonWithLimit extends StatelessWidget {
  final VoidCallback onPressed;
  final String type; // 'event' or 'group'
  final Widget child;
  final bool compact;

  const CreateButtonWithLimit({
    super.key,
    required this.onPressed,
    required this.type,
    required this.child,
    this.compact = true,
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
          // Premium users - no badge needed
          return GestureDetector(
            onTap: onPressed,
            child: child,
          );
        }

        final isEvent = type.toLowerCase() == 'event';
        final remaining = isEvent
            ? limitService.eventsRemaining
            : limitService.groupsRemaining;
        final canCreate = isEvent
            ? limitService.canCreateEvent
            : limitService.canCreateGroup;
        final limit = isEvent
            ? CreationLimitService.FREE_EVENT_LIMIT
            : CreationLimitService.FREE_GROUP_LIMIT;

        return GestureDetector(
          onTap: canCreate
              ? onPressed
              : () {
                  LimitReachedDialog.show(
                    context,
                    type: type,
                    limit: limit,
                  );
                },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              child,
              if (remaining <= 3) // Only show badge when getting low
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: remaining == 0
                            ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                            : remaining <= 1
                                ? [const Color(0xFFF59E0B), const Color(0xFFD97706)]
                                : [const Color(0xFF6366F1), const Color(0xFF4F46E5)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      remaining.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

