import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  }) : secondary = false,
       destructive = false;

  const AttendUsButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  }) : secondary = true,
       destructive = false;

  const AttendUsButton.destructive({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  }) : secondary = false,
       destructive = true;

  @override
  Widget build(BuildContext context) {
    final child = _ButtonLabel(label: label, icon: icon, loading: loading);
    if (secondary) {
      return OutlinedButton(
        onPressed: loading ? null : onPressed,
        child: child,
      );
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
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
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
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final bool enabled;
  final int maxLines;

  const AttendUsTextField({
    super.key,
    this.controller,
    required this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      enabled: enabled,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class AttendUsFormTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final String? labelText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final String? helperText;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final bool enabled;
  final int maxLines;

  const AttendUsFormTextField({
    super.key,
    this.controller,
    required this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.helperText,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      enabled: enabled,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hintText,
        labelText: labelText,
        helperText: helperText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class AttendUsSearchField extends StatefulWidget {
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool autofocus;

  const AttendUsSearchField({
    super.key,
    this.controller,
    this.hintText = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
  });

  @override
  State<AttendUsSearchField> createState() => _AttendUsSearchFieldState();
}

class _AttendUsSearchFieldState extends State<AttendUsSearchField> {
  late final TextEditingController _fallbackController;

  TextEditingController get _controller =>
      widget.controller ?? _fallbackController;

  @override
  void initState() {
    super.initState();
    _fallbackController = TextEditingController();
  }

  @override
  void dispose() {
    _fallbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        return TextField(
          controller: _controller,
          autofocus: widget.autofocus,
          textInputAction: TextInputAction.search,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      widget.onChanged?.call('');
                      widget.onClear?.call();
                    },
                  ),
          ),
        );
      },
    );
  }
}

class AttendUsPageSection extends StatelessWidget {
  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;
  final bool framed;

  const AttendUsPageSection({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    this.padding = const EdgeInsets.all(20),
    this.framed = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          AttendUsSectionHeader(
            title: title!,
            subtitle: subtitle,
            icon: icon,
            actions: actions,
          ),
          const SizedBox(height: 14),
        ],
        child,
      ],
    );

    if (framed) {
      return AttendUsCard(padding: padding, child: content);
    }

    return Padding(padding: padding, child: content);
  }
}

class AttendUsSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;

  const AttendUsSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          _IconBadge(icon: icon!, tone: AttendUsStatusTone.info),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 12),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ],
    );
  }
}

class AttendUsListTile extends StatelessWidget {
  final Widget? leading;
  final IconData? leadingIcon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;
  final bool selected;

  const AttendUsListTile({
    super.key,
    this.leading,
    this.leadingIcon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.dense = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = selected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surface;
    final foreground = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: dense ? 52 : 64),
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 12 : 14,
            vertical: dense ? 8 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 12),
              ] else if (leadingIcon != null) ...[
                _IconBadge(
                  icon: leadingIcon!,
                  tone: selected
                      ? AttendUsStatusTone.info
                      : AttendUsStatusTone.neutral,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: foreground,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall,
                        maxLines: dense ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ] else if (onTap != null) ...[
                const SizedBox(width: 12),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AttendUsActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final AttendUsStatusTone tone;
  final VoidCallback? onTap;

  const AttendUsActionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.tone = AttendUsStatusTone.info,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AttendUsCard(
      onTap: onTap,
      child: Row(
        children: [
          _IconBadge(icon: icon, tone: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 12),
            TextButton(onPressed: onTap, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class AttendUsFilterOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const AttendUsFilterOption({
    required this.value,
    required this.label,
    this.icon,
  });
}

class AttendUsFilterChipGroup<T> extends StatelessWidget {
  final List<AttendUsFilterOption<T>> options;
  final Set<T> selectedValues;
  final ValueChanged<Set<T>> onChanged;
  final bool multiSelect;

  const AttendUsFilterChipGroup({
    super.key,
    required this.options,
    required this.selectedValues,
    required this.onChanged,
    this.multiSelect = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          FilterChip(
            avatar: option.icon == null ? null : Icon(option.icon, size: 16),
            label: Text(option.label),
            selected: selectedValues.contains(option.value),
            onSelected: (selected) {
              final next = Set<T>.from(selectedValues);
              if (multiSelect) {
                selected ? next.add(option.value) : next.remove(option.value);
              } else {
                next
                  ..clear()
                  ..add(option.value);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class AttendUsBottomSheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final bool scrollable;

  const AttendUsBottomSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions = const [],
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheet = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
          top: 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            AttendUsSectionHeader(
              title: title,
              subtitle: subtitle,
              actions: actions,
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: scrollable ? SingleChildScrollView(child: sheet) : sheet,
      ),
    );
  }
}

Future<T?> showAttendUsBottomSheet<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required Widget child,
  List<Widget> actions = const [],
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AttendUsTokens.radiusLg),
      ),
    ),
    builder: (_) => AttendUsBottomSheet(
      title: title,
      subtitle: subtitle,
      actions: actions,
      child: child,
    ),
  );
}

class AttendUsDialog extends StatelessWidget {
  final String title;
  final String? message;
  final Widget? child;
  final List<Widget> actions;

  const AttendUsDialog({
    super.key,
    required this.title,
    this.message,
    this.child,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AttendUsTokens.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (message != null && message!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(message!, style: Theme.of(context).textTheme.bodyMedium),
              ],
              if (child != null) ...[const SizedBox(height: 16), child!],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(spacing: 8, runSpacing: 8, children: actions),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> showAttendUsDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  Widget? child,
  List<Widget> actions = const [],
}) {
  return showDialog<T>(
    context: context,
    builder: (_) => AttendUsDialog(
      title: title,
      message: message,
      actions: actions,
      child: child,
    ),
  );
}

class AttendUsDataTable extends StatelessWidget {
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final String? emptyTitle;
  final String? emptyMessage;

  const AttendUsDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyTitle,
    this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return AttendUsEmptyState(
        icon: Icons.table_rows_outlined,
        title: emptyTitle ?? 'No records',
        message: emptyMessage ?? 'Records will appear here when available.',
      );
    }

    final theme = Theme.of(context);
    return AttendUsCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          dataTextStyle: theme.textTheme.bodyMedium,
          headingRowColor: WidgetStatePropertyAll(
            theme.colorScheme.surfaceContainerHighest,
          ),
          columns: columns,
          rows: rows,
        ),
      ),
    );
  }
}

class AttendUsAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? name;
  final IconData fallbackIcon;
  final double size;
  final AttendUsStatusTone tone;

  const AttendUsAvatar({
    super.key,
    this.imageUrl,
    this.name,
    this.fallbackIcon = Icons.person_outline,
    this.size = 44,
    this.tone = AttendUsStatusTone.info,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(context, tone);
    final initials = _initials(name);
    final fallback = Container(
      width: size,
      height: size,
      color: colors.$1,
      alignment: Alignment.center,
      child: initials == null
          ? Icon(fallbackIcon, color: colors.$2, size: size * 0.48)
          : Text(
              initials,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.$2,
                fontSize: size * 0.32,
              ),
            ),
    );

    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: imageUrl == null || imageUrl!.isEmpty
            ? fallback
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }

  String? _initials(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class AttendUsGroupCard extends StatelessWidget {
  final String name;
  final String? description;
  final String? imageUrl;
  final String? memberCountLabel;
  final String? eventCountLabel;
  final String? statusLabel;
  final VoidCallback? onTap;

  const AttendUsGroupCard({
    super.key,
    required this.name,
    this.description,
    this.imageUrl,
    this.memberCountLabel,
    this.eventCountLabel,
    this.statusLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AttendUsCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AttendUsAvatar(
            imageUrl: imageUrl,
            name: name,
            fallbackIcon: Icons.groups_outlined,
            size: 56,
            tone: AttendUsStatusTone.success,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (statusLabel != null) ...[
                      const SizedBox(width: 8),
                      AttendUsStatusBadge(
                        label: statusLabel!,
                        tone: AttendUsStatusTone.success,
                      ),
                    ],
                  ],
                ),
                if (description != null && description!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description!,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (memberCountLabel != null)
                      _Meta(
                        icon: Icons.people_outline,
                        label: memberCountLabel!,
                      ),
                    if (eventCountLabel != null)
                      _Meta(
                        icon: Icons.event_available_outlined,
                        label: eventCountLabel!,
                      ),
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

class AttendUsUserRow extends StatelessWidget {
  final String name;
  final String? subtitle;
  final String? imageUrl;
  final String? statusLabel;
  final Widget? action;
  final VoidCallback? onTap;

  const AttendUsUserRow({
    super.key,
    required this.name,
    this.subtitle,
    this.imageUrl,
    this.statusLabel,
    this.action,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AttendUsListTile(
      leading: AttendUsAvatar(imageUrl: imageUrl, name: name),
      title: name,
      subtitle: subtitle,
      trailing:
          action ??
          (statusLabel == null
              ? null
              : AttendUsStatusBadge(
                  label: statusLabel!,
                  tone: AttendUsStatusTone.neutral,
                )),
      onTap: onTap,
    );
  }
}

class AttendUsNotificationRow extends StatelessWidget {
  final String title;
  final String message;
  final String? timeLabel;
  final IconData icon;
  final bool unread;
  final VoidCallback? onTap;

  const AttendUsNotificationRow({
    super.key,
    required this.title,
    required this.message,
    this.timeLabel,
    this.icon = Icons.notifications_none,
    this.unread = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AttendUsListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          _IconBadge(
            icon: icon,
            tone: unread ? AttendUsStatusTone.info : AttendUsStatusTone.neutral,
          ),
          if (unread)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.surface),
                ),
              ),
            ),
        ],
      ),
      title: title,
      subtitle: timeLabel == null ? message : '$message - $timeLabel',
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
      selected: unread,
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final AttendUsStatusTone tone;

  const _IconBadge({required this.icon, required this.tone});

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(context, tone);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
      ),
      child: Icon(icon, color: colors.$2, size: 20),
    );
  }
}

(Color, Color) _toneColors(BuildContext context, AttendUsStatusTone tone) {
  final scheme = Theme.of(context).colorScheme;
  return switch (tone) {
    AttendUsStatusTone.info => (scheme.primaryContainer, scheme.primary),
    AttendUsStatusTone.success => (scheme.secondaryContainer, scheme.secondary),
    AttendUsStatusTone.warning => (scheme.tertiaryContainer, scheme.tertiary),
    AttendUsStatusTone.danger => (scheme.errorContainer, scheme.error),
    AttendUsStatusTone.neutral => (
      scheme.surfaceContainerHighest,
      scheme.onSurfaceVariant,
    ),
  };
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
              if (action != null) ...[const SizedBox(height: 20), action!],
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
        scheme.secondary,
      ),
      AttendUsStatusTone.warning => (scheme.tertiaryContainer, scheme.tertiary),
      AttendUsStatusTone.danger => (scheme.errorContainer, scheme.error),
      AttendUsStatusTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
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

class AttendUsCameraOverlayPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final AttendUsStatusTone tone;
  final List<Widget> actions;
  final bool elevated;

  const AttendUsCameraOverlayPanel({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.tone = AttendUsStatusTone.info,
    this.actions = const [],
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _toneColors(context, tone);
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AttendUsTokens.radiusLg),
        border: Border.all(color: colors.$2.withValues(alpha: 0.22)),
        boxShadow: elevated
            ? AttendUsTokens.softShadow(
                dark: theme.brightness == Brightness.dark,
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBadge(icon: icon, tone: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (message != null && message!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    message!,
                    style: theme.textTheme.bodySmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AttendUsMapControlPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> controls;
  final Widget? primaryAction;

  const AttendUsMapControlPanel({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.map_outlined,
    this.controls = const [],
    this.primaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return AttendUsCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AttendUsSectionHeader(title: title, subtitle: subtitle, icon: icon),
          if (controls.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (var i = 0; i < controls.length; i++) ...[
              controls[i],
              if (i != controls.length - 1) const SizedBox(height: 12),
            ],
          ],
          if (primaryAction != null) ...[
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: primaryAction!),
          ],
        ],
      ),
    );
  }
}

class AttendUsQuizPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final List<Widget> actions;

  const AttendUsQuizPanel({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.quiz_outlined,
    required this.child,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return AttendUsPageSection(
      title: title,
      subtitle: subtitle,
      icon: icon,
      actions: actions,
      framed: true,
      child: child,
    );
  }
}

class AttendUsQuizActionBar extends StatelessWidget {
  final List<Widget> children;

  const AttendUsQuizActionBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return AttendUsCard(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.end,
        children: children,
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
            child:
                qrPreview ??
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
