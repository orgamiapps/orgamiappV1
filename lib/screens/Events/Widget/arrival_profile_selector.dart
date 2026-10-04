import 'package:flutter/material.dart';
import 'package:attendus/models/check_in_policy.dart';

class ArrivalProfileSelector extends StatelessWidget {
  const ArrivalProfileSelector({
    super.key,
    required this.policy,
    required this.onChanged,
  });

  final CheckInPolicy policy;
  final ValueChanged<CheckInPolicy> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How should arrivals work?',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose the experience guests see at the door. Hybrid works best '
              'for most events.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            ...CheckInProfile.values.map(
              (profile) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ProfileTile(
                  profile: profile,
                  selected: policy.profile == profile,
                  onTap: () => onChanged(
                    policy.copyWith(
                      profile: profile,
                      needsOrganizerReview: false,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 30),
            Text(
              'Who may check in?',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<CheckInEligibility>(
              initialValue: policy.eligibility,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: CheckInEligibility.open,
                  child: Text('Anyone — guests may use their name'),
                ),
                DropdownMenuItem(
                  value: CheckInEligibility.registeredOnly,
                  child: Text('Registered attendees only'),
                ),
                DropdownMenuItem(
                  value: CheckInEligibility.ticketRequired,
                  child: Text('A valid ticket is required'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onChanged(policy.copyWith(eligibility: value));
                }
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _WindowField(
                    label: 'Opens before',
                    value: policy.opensBeforeMinutes,
                    onChanged: (value) =>
                        onChanged(policy.copyWith(opensBeforeMinutes: value)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _WindowField(
                    label: 'Closes after',
                    value: policy.closesAfterMinutes,
                    onChanged: (value) =>
                        onChanged(policy.copyWith(closesAfterMinutes: value)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: policy.checkoutEnabled,
              title: const Text('Enable explicit checkout'),
              subtitle: const Text(
                'Attendee, scan-out, or organizer checkout—no background tracking.',
              ),
              onChanged: (value) =>
                  onChanged(policy.copyWith(checkoutEnabled: value)),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: policy.allowReentry,
              title: const Text('Allow re-entry'),
              subtitle: const Text(
                'Repeat arrivals are recorded in the audit trail.',
              ),
              onChanged: (value) =>
                  onChanged(policy.copyWith(allowReentry: value)),
            ),
            if (policy.staffEntryEnabled)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: policy.passLockEnabled,
                title: const Text('Pass Lock'),
                subtitle: const Text(
                  'Ask attendees to unlock a short-lived pass with device security.',
                ),
                onChanged: (value) =>
                    onChanged(policy.copyWith(passLockEnabled: value)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final CheckInProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (title, description, icon, recommended) = switch (profile) {
      CheckInProfile.selfCheckIn => (
        'Self Check-in',
        'Guests scan the rotating venue QR or enter its short code.',
        Icons.qr_code_2,
        false,
      ),
      CheckInProfile.staffEntry => (
        'Staff Entry',
        'Staff scan personal passes or select people from the roster.',
        Icons.badge_outlined,
        false,
      ),
      CheckInProfile.hybrid => (
        'Hybrid',
        'Both paths are available, with staff help as the fallback.',
        Icons.sync_alt,
        true,
      ),
    };
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: selected ? primary.withValues(alpha: 0.08) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? primary : null),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (recommended)
                          const Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('Recommended'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? primary : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowField extends StatelessWidget {
  const _WindowField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const values = [0, 15, 30, 60, 90, 120, 180];
    final selected = values.contains(value) ? value : 60;
    return DropdownButtonFormField<int>(
      initialValue: selected,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: values
          .map(
            (minutes) => DropdownMenuItem(
              value: minutes,
              child: Text(minutes == 0 ? 'At event time' : '$minutes min'),
            ),
          )
          .toList(),
      onChanged: (minutes) {
        if (minutes != null) onChanged(minutes);
      },
    );
  }
}
