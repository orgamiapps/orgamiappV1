import 'package:flutter/material.dart';
import 'package:attendus/screens/Home/dashboard_screen.dart';
import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/screens/Authentication/login_screen.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/Utils/route_names.dart';
import 'package:attendus/Utils/router.dart';

class AppBottomNavigation extends StatefulWidget {
  final int? selectedIndex;
  final Function(int)? onDestinationSelected;
  final bool hasScrolledContent;

  const AppBottomNavigation({
    super.key,
    this.selectedIndex,
    this.onDestinationSelected,
    this.hasScrolledContent = false,
  });

  @override
  State<AppBottomNavigation> createState() => _AppBottomNavigationState();
}

class _AppBottomNavigationState extends State<AppBottomNavigation> {
  // Cache navigation destinations to avoid rebuilding
  static const List<NavigationDestination> _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.apartment_outlined),
      selectedIcon: Icon(Icons.apartment),
      label: 'Groups',
    ),
    NavigationDestination(
      icon: Icon(Icons.forum_outlined),
      selectedIcon: Icon(Icons.forum),
      label: 'Messages',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: 'Profile',
    ),
    NavigationDestination(
      icon: Icon(Icons.menu),
      selectedIcon: Icon(Icons.menu),
      label: 'Account',
    ),
  ];

  int _normalizeIndex(int index) {
    return RouteNames.normalizeDashboardTabIndex(index);
  }

  void _navigateToTab(int index) {
    final normalizedIndex = _normalizeIndex(index);
    if (widget.onDestinationSelected != null) {
      widget.onDestinationSelected!(normalizedIndex);
    } else {
      // Default behavior: navigate to dashboard with selected tab
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => DashboardScreen(initialIndex: normalizedIndex),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuestMode = GuestModeService().isGuestMode;
    // OPTIMIZATION: Cache theme values to avoid repeated lookups
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // For guest mode, show custom simplified navigation
    if (isGuestMode) {
      return _buildGuestModeNavigation(context, colorScheme);
    }

    // For logged-in users, show full navigation
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        boxShadow: widget.hasScrolledContent
            ? AttendUsTokens.softShadow(
                dark: theme.brightness == Brightness.dark,
              )
            : const [],
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: colorScheme.surface,
          indicatorColor: colorScheme.primaryContainer,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w600,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              size: 24,
            );
          }),
        ),
        child: NavigationBar(
          height: 68,
          selectedIndex: _normalizeIndex(widget.selectedIndex ?? 0),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: _navigateToTab,
          destinations: _destinations,
        ),
      ),
    );
  }

  Widget _buildGuestModeNavigation(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: SizedBox(
        height: 68,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildGuestNavButton(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                label: 'Home',
                isSelected: true,
                colorScheme: colorScheme,
                onTap: () {},
              ),
              _buildLoginButton(colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuestNavButton({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool isSelected,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    final primary = colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              color: isSelected ? primary : colorScheme.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected ? primary : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginButton(ColorScheme colorScheme) {
    return InkWell(
      onTap: () {
        RouterClass.nextScreenNormal(context, const LoginScreen());
      },
      borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.login, color: Colors.white, size: 24),
            SizedBox(height: 4),
            Text(
              'Login',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
