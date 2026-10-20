import 'package:flutter/material.dart';

/// Keeps historical records identifiable without advertising an active event.
class CancelledEventHistory extends StatelessWidget {
  const CancelledEventHistory({
    super.key,
    required this.cancelled,
    required this.child,
  });

  final bool cancelled;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (cancelled)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(
            label: 'Cancelled event. Retained for your records.',
            child: const Chip(
              avatar: Icon(Icons.event_busy_outlined, size: 18),
              label: Text('Cancelled'),
            ),
          ),
        ),
      child,
    ],
  );
}
