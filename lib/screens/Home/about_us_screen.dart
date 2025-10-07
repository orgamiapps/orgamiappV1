import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            AppAppBarView.modernHeader(
              context: context,
              title: 'About Us',
              subtitle: 'Your all-in-one events platform',
            ),
            Expanded(
              child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Intro(textColor: Theme.of(context).textTheme.titleLarge?.color),
              const SizedBox(height: 16),
              _FeatureGrid(),
              const SizedBox(height: 24),
              _FooterNote(),
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
}

class _Intro extends StatelessWidget {
  const _Intro({this.textColor});

  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your all‑in‑one events platform',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: textColor,
            fontFamily: 'Roboto',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Discover, promote, and manage events—from signups to on‑site check‑in—'
          'with real‑time insights that help you grow your community.',
          style: TextStyle(
            fontSize: 15,
            height: 1.35,
            color: Theme.of(context).textTheme.bodyMedium?.color,
            fontFamily: 'Roboto',
          ),
        ),
      ],
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final List<_Feature> features = [
      _Feature(
        icon: Icons.explore,
        title: 'Explore events',
        description: 'Find nearby and trending events tailored to your interests.',
      ),
      _Feature(
        icon: Icons.campaign,
        title: 'Promote events',
        description: 'Boost reach with shareable links, QR codes, and smart reminders.',
      ),
      _Feature(
        icon: Icons.event_note,
        title: 'Manage with ease',
        description: 'Create listings, set tickets, and handle RSVPs in minutes.',
      ),
      _Feature(
        icon: Icons.qr_code_scanner,
        title: 'Track attendance',
        description: 'Fast check‑in with QR/NFC and live capacity tracking.',
      ),
      _Feature(
        icon: Icons.insights,
        title: 'Actionable insights',
        description: 'Understand turnout, revenue, and engagement at a glance.',
      ),
      _Feature(
        icon: CupertinoIcons.chat_bubble_2_fill,
        title: 'Engage attendees',
        description: 'Send updates, notifications, and offers to your audience.',
      ),
      _Feature(
        icon: Icons.lock_outline,
        title: 'Secure & seamless',
        description: 'Reliable auth, payments, and data protection built‑in.',
      ),
      _Feature(
        icon: Icons.devices,
        title: 'Works everywhere',
        description: 'Optimized for mobile and desktop so your team stays in sync.',
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: features
          .map((f) => _FeatureCard(feature: f))
          .toList(growable: false),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature});

  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = Theme.of(context).dividerColor;
    final Color iconBg = Theme.of(context).colorScheme.primary.withValues(alpha: 0.1);
    final Color iconColor = Theme.of(context).colorScheme.primary;

    return Container(
      width: (MediaQuery.of(context).size.width - 20 - 20 - 12) / 2,
      // padding: 16 on small tiles for compactness
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(feature.icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            feature.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).textTheme.titleMedium?.color,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            feature.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: Theme.of(context).textTheme.bodyMedium?.color,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature {
  const _Feature({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

class _FooterNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'Orgami helps organizers deliver great experiences and attendees find the right events—'
      'all in one place.',
      textAlign: TextAlign.left,
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        fontFamily: 'Roboto',
      ),
    );
  }
}


