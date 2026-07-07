import 'package:flutter/material.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/widgets/attendus_design_system.dart';

class AttendUsNavDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const AttendUsNavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class AttendUsScaffold extends StatelessWidget {
  final Widget body;
  final String title;
  final String? subtitle;
  final int selectedIndex;
  final List<AttendUsNavDestination> destinations;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  const AttendUsScaffold({
    super.key,
    required this.body,
    required this.title,
    this.subtitle,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    this.actions = const [],
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 900;

    if (useRail) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        floatingActionButton: floatingActionButton,
        body: SafeArea(
          child: Row(
            children: [
              _AttendUsSidebar(
                destinations: destinations,
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
              ),
              Expanded(
                child: Column(
                  children: [
                    AttendUsTopBar(
                      title: title,
                      subtitle: subtitle,
                      actions: actions,
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AttendUsTokens.pageMaxWidth,
                          ),
                          child: body,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Column(
          children: [
            AttendUsTopBar(title: title, subtitle: subtitle, actions: actions),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex.clamp(0, destinations.length - 1),
        onDestinationSelected: onDestinationSelected,
        destinations: [
          for (final destination in destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}

class _AttendUsSidebar extends StatelessWidget {
  final int selectedIndex;
  final List<AttendUsNavDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  const _AttendUsSidebar({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: AttendUsTokens.sidebarWidth,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.event_available,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Text('AttendUs', style: theme.textTheme.titleLarge),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: destinations.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final destination = destinations[index];
                final selected = index == selectedIndex;
                return Material(
                  color: selected
                      ? theme.colorScheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(AttendUsTokens.radiusMd),
                    onTap: () => onDestinationSelected(index),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? destination.selectedIcon
                                : destination.icon,
                            color: selected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            destination.label,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: selected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Professional event operations for organizers and attendees.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
