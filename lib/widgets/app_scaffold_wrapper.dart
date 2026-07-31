import 'package:flutter/material.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/Utils/route_names.dart';
import 'package:attendus/screens/Home/dashboard_screen.dart';
import 'package:attendus/widgets/app_bottom_navigation.dart';
import 'package:attendus/widgets/attendus_scaffold.dart';

class AppScaffoldWrapper extends StatefulWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;
  final bool showBottomNavigation;
  final int? selectedBottomNavIndex;
  final bool? resizeToAvoidBottomInset;
  final Widget? drawer;
  final Widget? endDrawer;

  const AppScaffoldWrapper({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.showBottomNavigation = true,
    this.selectedBottomNavIndex,
    this.resizeToAvoidBottomInset,
    this.drawer,
    this.endDrawer,
  });

  @override
  State<AppScaffoldWrapper> createState() => _AppScaffoldWrapperState();
}

class _AppScaffoldWrapperState extends State<AppScaffoldWrapper> {
  bool _hasScrolledContent = false;

  static const List<AttendUsNavDestination> _destinations = [
    AttendUsNavDestination(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    AttendUsNavDestination(
      label: 'Groups',
      icon: Icons.apartment_outlined,
      selectedIcon: Icons.apartment,
    ),
    AttendUsNavDestination(
      label: 'Messages',
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum,
    ),
    AttendUsNavDestination(
      label: 'Profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
    AttendUsNavDestination(
      label: 'Account',
      icon: Icons.menu_outlined,
      selectedIcon: Icons.menu,
    ),
  ];

  int get _selectedIndex => RouteNames.normalizeDashboardTabIndex(
    widget.selectedBottomNavIndex ?? RouteNames.homeTab,
  );

  @override
  Widget build(BuildContext context) {
    final useSideNavigation = MediaQuery.sizeOf(context).width >= 720;
    final body = widget.showBottomNavigation
        ? NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // Track if any vertical scrollable in the subtree has scrolled from top.
              try {
                final isVertical = notification.metrics.axis == Axis.vertical;
                if (isVertical && mounted) {
                  final scrolled = notification.metrics.pixels > 0.0;
                  if (scrolled != _hasScrolledContent) {
                    setState(() => _hasScrolledContent = scrolled);
                  }
                }
              } catch (e) {
                debugPrint('Error in scroll notification: $e');
              }
              return false;
            },
            child: widget.body,
          )
        : widget.body;

    if (widget.showBottomNavigation && useSideNavigation) {
      return Scaffold(
        backgroundColor:
            widget.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
        floatingActionButton: widget.floatingActionButton,
        floatingActionButtonLocation: widget.floatingActionButtonLocation,
        resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
        drawer: widget.drawer,
        endDrawer: widget.endDrawer,
        body: SafeArea(
          child: Row(
            children: [
              _CompatibilitySideNav(
                destinations: _destinations,
                selectedIndex: _selectedIndex,
                onDestinationSelected: _navigateToDashboardTab,
              ),
              Expanded(
                child: Column(
                  children: [
                    if (widget.appBar != null) widget.appBar!,
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
      appBar: widget.appBar,
      backgroundColor: widget.backgroundColor,
      floatingActionButton: widget.floatingActionButton,
      floatingActionButtonLocation: widget.floatingActionButtonLocation,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      drawer: widget.drawer,
      endDrawer: widget.endDrawer,
      body: body,
      bottomNavigationBar: widget.showBottomNavigation
          ? AppBottomNavigation(
              selectedIndex: _selectedIndex,
              hasScrolledContent: _hasScrolledContent,
            )
          : null,
    );
  }

  void _navigateToDashboardTab(int index) {
    final normalizedIndex = RouteNames.normalizeDashboardTabIndex(index);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => DashboardScreen(initialIndex: normalizedIndex),
      ),
      (route) => false,
    );
  }
}

class _CompatibilitySideNav extends StatelessWidget {
  final List<AttendUsNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _CompatibilitySideNav({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expanded = MediaQuery.sizeOf(context).width >= 1100;
    return Container(
      width: expanded ? AttendUsTokens.sidebarWidth : 88,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
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
                return Tooltip(
                  message: destination.label,
                  child: Material(
                    color: selected
                        ? theme.colorScheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(
                      AttendUsTokens.radiusMd,
                    ),
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
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
