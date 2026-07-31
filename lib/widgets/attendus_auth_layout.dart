import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/Utils/images.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:flutter/material.dart';

class AttendUsAuthLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? leading;
  final Widget? footer;
  final String eyebrow;

  const AttendUsAuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.leading,
    this.footer,
    this.eyebrow = 'Attendus',
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useTwoColumn = width >= 900;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            if (leading != null) Positioned(top: 12, left: 12, child: leading!),
            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  useTwoColumn ? 40 : 20,
                  leading == null ? 24 : 72,
                  useTwoColumn ? 40 : 20,
                  24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: useTwoColumn
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Expanded(child: _AuthBrandPanel()),
                            const SizedBox(width: 40),
                            Expanded(
                              child: _AuthContentPanel(
                                eyebrow: eyebrow,
                                title: title,
                                subtitle: subtitle,
                                footer: footer,
                                child: child,
                              ),
                            ),
                          ],
                        )
                      : _AuthContentPanel(
                          eyebrow: eyebrow,
                          title: title,
                          subtitle: subtitle,
                          footer: footer,
                          child: child,
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

class AttendUsBackButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const AttendUsBackButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: 'Back',
      onPressed: onPressed ?? () => Navigator.maybePop(context),
      icon: const Icon(Icons.arrow_back),
    );
  }
}

class AttendUsSocialButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const AttendUsSocialButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : icon,
        label: Text(label),
      ),
    );
  }
}

class _AuthContentPanel extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;

  const _AuthContentPanel({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: _BrandMark(compact: MediaQuery.sizeOf(context).width < 900),
          ),
          const SizedBox(height: 24),
          Text(
            eyebrow,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          AttendUsCard(padding: const EdgeInsets.all(24), child: child),
          if (footer != null) ...[const SizedBox(height: 16), footer!],
        ],
      ),
    );
  }
}

class _AuthBrandPanel extends StatelessWidget {
  const _AuthBrandPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _BrandMark(compact: false),
          const SizedBox(height: 28),
          Text(
            'Run dependable event operations from first invite to final check-in.',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'Discover events, manage attendance, and check in securely with tools built for organizers and attendees.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AttendUsStatusBadge(
                label: 'Event discovery',
                icon: Icons.search,
                tone: AttendUsStatusTone.info,
              ),
              AttendUsStatusBadge(
                label: 'Secure check-in',
                icon: Icons.verified_user_outlined,
                tone: AttendUsStatusTone.success,
              ),
              AttendUsStatusBadge(
                label: 'Attendance tools',
                icon: Icons.fact_check_outlined,
                tone: AttendUsStatusTone.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  final bool compact;

  const _BrandMark({required this.compact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: compact ? 96 : 118,
      height: compact ? 72 : 88,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AttendUsTokens.radiusLg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: AttendUsTokens.softShadow(
          dark: theme.brightness == Brightness.dark,
        ),
      ),
      child: Image.asset(
        Images.inAppLogo,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Icon(
          Icons.event_available,
          color: theme.colorScheme.primary,
          size: compact ? 36 : 44,
        ),
      ),
    );
  }
}
