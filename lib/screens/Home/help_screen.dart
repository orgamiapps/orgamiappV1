import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
// Removed unused web help center imports after UI simplification

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const String supportPhoneDisplay = '(239) 480-7082';
  static const String supportPhoneRaw = '+12394807082';
  static const String supportEmail = 'Attendus.app@gmail.com';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Help & Support'), elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(),
              const SizedBox(height: 16),
              _QuickActions(),
              const SizedBox(height: 16),
              _MetaInfo(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How can we help?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).textTheme.titleLarge?.color,
            fontFamily: 'Roboto',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Get instant help or contact us directly. We typically respond within one business day.',
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

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: _ActionCard.call()),
        SizedBox(width: 12),
        Expanded(child: _ActionCard.email()),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard._({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  const _ActionCard.call()
    : this._(
        icon: Icons.call,
        title: 'Call us',
        subtitle: HelpScreen.supportPhoneDisplay,
        onTap: _launchPhone,
      );
  const _ActionCard.email()
    : this._(
        icon: Icons.email_outlined,
        title: 'Email us',
        subtitle: HelpScreen.supportEmail,
        onTap: _launchEmail,
      );

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  static Future<void> _launchPhone() async {
    final Uri uri = Uri(scheme: 'tel', path: HelpScreen.supportPhoneRaw);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // In case call cannot be initiated, fall back to copy
    }
  }

  static Future<void> _launchEmail() async {
    final Uri uri = Uri(
      scheme: 'mailto',
      path: HelpScreen.supportEmail,
      queryParameters: {'subject': 'Support Request - Orgami'},
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // No-op fallback if mail client unavailable
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color borderColor = Theme.of(context).dividerColor;
    final Color iconBg = Theme.of(
      context,
    ).colorScheme.primary.withValues(alpha: 0.1);
    final Color iconColor = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).textTheme.titleMedium?.color,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// Removed _SupportShortcuts widget as the Popular help section was deprecated

// Removed Popular help shortcuts and Visit Help Center CTA

class _MetaInfo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Contact',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontFamily: 'Roboto',
          ),
        ),
        const SizedBox(height: 8),
        _ContactRow(
          icon: Icons.call,
          label: HelpScreen.supportPhoneDisplay,
          onTap: _ActionCard._launchPhone,
        ),
        const SizedBox(height: 8),
        _ContactRow(
          icon: Icons.email_outlined,
          label: HelpScreen.supportEmail,
          onTap: _ActionCard._launchEmail,
        ),
        const SizedBox(height: 16),
        Text(
          'Hours',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontFamily: 'Roboto',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Mon–Sun, 9:00am–6:00pm (ET)',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).textTheme.bodyMedium?.color,
            fontFamily: 'Roboto',
          ),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).textTheme.bodyMedium?.color,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }
}
