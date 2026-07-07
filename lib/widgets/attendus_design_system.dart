import 'package:flutter/material.dart';
import 'package:attendus/Utils/attendus_theme.dart';

class AttendUsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  const AttendUsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: AttendUsTokens.softShadow(
          dark: theme.brightness == Brightness.dark,
        ),
      ),
      child: child,
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

class AttendUsButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondary;
  final bool destructive;
  final bool loading;

  const AttendUsButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  })  : secondary = false,
        destructive = false;

  const AttendUsButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  })  : secondary = true,
        destructive = false;

  const AttendUsButton.destructive({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  })  : secondary = false,
        destructive = true;

  @override
  Widget build(BuildContext context) {
    final child = _ButtonLabel(label: label, icon: icon, loading: loading);
    if (secondary) {
      return OutlinedButton(onPressed: loading ? null : onPressed, child: child);
    }

    final style = destructive
        ? ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          )
        : null;
    return ElevatedButton(
      style: style,
      onPressed: loading ? null : onPressed,
      child: child,
    );
  }
}

class _ButtonLabel extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool loading;

  const _ButtonLabel({required this.label, this.icon, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: 8),
        ],
        Text(label),
      ],
    );
  }
}

class AttendUsTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final String? labelText;
  final IconData? prefixIcon;
  final ValueChanged<String>? onChanged;

  const AttendUsTextField({
    super.key,
    this.controller,
    required this.hintText,
    this.labelText,
    this.prefixIcon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      ),
    );
  }
}

class AttendUsTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const AttendUsTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.94),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class AttendUsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const AttendUsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AttendUsCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 28),
              ),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[
                const SizedBox(height: 20),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AttendUsLoadingState extends StatelessWidget {
  final String? label;

  const AttendUsLoadingState({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

enum AttendUsStatusTone { neutral, info, success, warning, danger }

class AttendUsStatusBadge extends StatelessWidget {
  final String label;
  final AttendUsStatusTone tone;
  final IconData? icon;

  const AttendUsStatusBadge({
    super.key,
    required this.label,
    this.tone = AttendUsStatusTone.neutral,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.$2.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.$2),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: colors.$2,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _colors(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (tone) {
      AttendUsStatusTone.info => (scheme.primaryContainer, scheme.primary),
      AttendUsStatusTone.success => (
          scheme.secondaryContainer,
          scheme.secondary
        ),
      AttendUsStatusTone.warning => (
          scheme.tertiaryContainer,
          scheme.tertiary
        ),
      AttendUsStatusTone.danger => (scheme.errorContainer, scheme.error),
      AttendUsStatusTone.neutral => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant
        ),
    };
  }
}

class AttendUsMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final AttendUsStatusTone tone;

  const AttendUsMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = AttendUsStatusTone.info,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AttendUsCard(
      child: Row(
        children: [
          AttendUsStatusBadge(label: '', icon: icon, tone: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: theme.textTheme.headlineSmall),
                Text(label, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AttendUsEventSummaryCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String dateLabel;
  final String locationLabel;
  final String? statusLabel;
  final VoidCallback? onTap;

  const AttendUsEventSummaryCard({
    super.key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    required this.dateLabel,
    required this.locationLabel,
    this.statusLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AttendUsCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 8,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AttendUsTokens.radiusMd),
              ),
              child: imageUrl == null || imageUrl!.isEmpty
                  ? Container(
                      color: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.event,
                        color: theme.colorScheme.primary,
                        size: 40,
                      ),
                    )
                  : Image.network(imageUrl!, fit: BoxFit.cover),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (statusLabel != null) ...[
                      const SizedBox(width: 8),
                      AttendUsStatusBadge(
                        label: statusLabel!,
                        tone: AttendUsStatusTone.info,
                      ),
                    ],
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _Meta(icon: Icons.schedule, label: dateLabel),
                    _Meta(icon: Icons.place_outlined, label: locationLabel),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AttendUsTicketPassCard extends StatelessWidget {
  final String eventTitle;
  final String dateLabel;
  final String ticketLabel;
  final Widget? qrPreview;
  final VoidCallback? onTap;

  const AttendUsTicketPassCard({
    super.key,
    required this.eventTitle,
    required this.dateLabel,
    required this.ticketLabel,
    this.qrPreview,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AttendUsCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
            ),
            child: qrPreview ??
                Icon(Icons.qr_code_2, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventTitle,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                _Meta(icon: Icons.schedule, label: dateLabel),
                const SizedBox(height: 6),
                AttendUsStatusBadge(
                  label: ticketLabel,
                  tone: AttendUsStatusTone.success,
                  icon: Icons.confirmation_number_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Meta({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.bodySmall,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
