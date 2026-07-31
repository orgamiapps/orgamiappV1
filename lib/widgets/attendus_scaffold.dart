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
  final VoidCallback? onNotificationsPressed;
  final VoidCallback? onProfilePressed;
  final String? profileName;
  final String? profileImageUrl;
  final int notificationCount;

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
    this.onNotificationsPressed,
    this.onProfilePressed,
    this.profileName,
    this.profileImageUrl,
    this.notificationCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useSideNavigation = width >= 720;
    final useExpandedSidebar = width >= 1100;
    final shellActions = [
      ...actions,
      if (onNotificationsPressed != null)
        _NotificationButton(
          onPressed: onNotificationsPressed!,
          count: notificationCount,
        ),
      if (onProfilePressed != null)
        _ProfileButton(
          name: profileName,
          imageUrl: profileImageUrl,
          onPressed: onProfilePressed!,
          expanded: width >= 900,
        ),
    ];
    final constrainedBody = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AttendUsTokens.pageMaxWidth,
        ),
        child: body,
      ),
    );

    if (useSideNavigation) {
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
                expanded: useExpandedSidebar,
              ),
              Expanded(
                child: Column(
                  children: [
                    AttendUsTopBar(
                      title: title,
                      subtitle: subtitle,
                      actions: shellActions,
                    ),
                    Expanded(child: constrainedBody),
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
            AttendUsTopBar(
              title: title,
              subtitle: subtitle,
              actions: shellActions,
            ),
            Expanded(child: constrainedBody),
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
  final bool expanded;

  const _AttendUsSidebar({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: expanded ? AttendUsTokens.sidebarWidth : 88,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 20, expanded ? 20 : 16, 16),
            child: Row(
              mainAxisAlignment: expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
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
                if (expanded) ...[
                  const SizedBox(width: 12),
                  Text('Attendus', style: theme.textTheme.titleLarge),
                ],
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
                    borderRadius: BorderRadius.circular(
                      AttendUsTokens.radiusMd,
                    ),
                    onTap: () => onDestinationSelected(index),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisAlignment: expanded
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.center,
                        children: [
                          Icon(
                            selected
                                ? destination.selectedIcon
                                : destination.icon,
                            color: selected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          if (expanded) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                destination.label,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: selected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (expanded)
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

class _NotificationButton extends StatelessWidget {
  final VoidCallback onPressed;
  final int count;

  const _NotificationButton({required this.onPressed, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Notifications',
          onPressed: onPressed,
          icon: const Icon(Icons.notifications_none),
        ),
        if (count > 0)
          Positioned(
            right: 7,
            top: 7,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                count > 99 ? '99+' : count.toString(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onError,
                  fontSize: 10,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProfileButton extends StatelessWidget {
  final String? name;
  final String? imageUrl;
  final VoidCallback onPressed;
  final bool expanded;

  const _ProfileButton({
    required this.name,
    required this.imageUrl,
    required this.onPressed,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = (name == null || name!.trim().isEmpty)
        ? 'Account'
        : name!.trim();
    return Tooltip(
      message: displayName,
      child: InkWell(
        borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
        onTap: onPressed,
        child: Container(
          height: 40,
          padding: EdgeInsets.only(
            left: 6,
            right: expanded ? 10 : 6,
            top: 4,
            bottom: 4,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AttendUsAvatar(imageUrl: imageUrl, name: displayName, size: 30),
              if (expanded) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    displayName,
                    style: theme.textTheme.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
