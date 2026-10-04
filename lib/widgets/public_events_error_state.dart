import 'package:flutter/material.dart';

import 'package:attendus/Services/public_events_repository.dart';

class PublicEventsLastKnownNotice extends StatelessWidget {
  const PublicEventsLastKnownNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('public-events-last-known-notice'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD48A)),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 20, color: Color(0xFF8A5A00)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Showing recently loaded events while we reconnect.',
              style: TextStyle(color: Color(0xFF6B4600)),
            ),
          ),
        ],
      ),
    );
  }
}

class PublicEventsErrorState extends StatelessWidget {
  const PublicEventsErrorState({
    required this.failure,
    required this.onRetry,
    super.key,
  });

  final PublicEventsFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('public-events-error'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: Color(0xFFE5484D),
            ),
            const SizedBox(height: 16),
            const Text(
              'Events temporarily unavailable',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              failure.userMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
