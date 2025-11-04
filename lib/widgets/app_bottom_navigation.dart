import 'package:flutter/material.dart';
import 'package:attendus/screens/Home/dashboard_screen.dart';
import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/screens/Authentication/login_screen.dart';
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
      label: 'Orgs',
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
      icon: Icon(Icons.notifications_none),
      selectedIcon: Icon(Icons.notifications),
      label: 'Alerts',
    ),
    NavigationDestination(
      icon: Icon(Icons.menu),
      selectedIcon: Icon(Icons.menu),
      label: 'Account',
    ),
  ];

  void _navigateToTab(int index) {
    if (widget.onDestinationSelected != null) {
      widget.onDestinationSelected!(index);
    } else {
      // Default behavior: navigate to dashboard with selected tab
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => DashboardScreen(initialIndex: index),
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
    final primary = colorScheme.primary;
    final barColor = theme.cardColor;
    final shadowColor = theme.shadowColor;

    // For guest mode, show custom simplified navigation
    if (isGuestMode) {
      return _buildGuestModeNavigation(
        context,
        theme,
        colorScheme,
        primary,
        barColor,
        shadowColor,
      );
    }

    // For logged-in users, show full navigation
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: widget.hasScrolledContent
                ? [
                    BoxShadow(
                      color: shadowColor.withValues(alpha: 0.08),
                      blurRadius: 16,
                      spreadRadius: 0,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: barColor,
              indicatorColor: primary.withValues(alpha: 0.12),
              labelTextStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final bool selected = states.contains(WidgetState.selected);
                return IconThemeData(
                  color: selected ? primary : colorScheme.onSurfaceVariant,
                  size: 24,
                );
              }),
            ),
            child: NavigationBar(
              height: 64,
              selectedIndex: widget.selectedIndex ?? 0,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              onDestinationSelected: _navigateToTab,
              destinations: _destinations,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuestModeNavigation(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    Color primary,
    Color barColor,
    Color shadowColor,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: widget.hasScrolledContent
                ? [
                    BoxShadow(
                      color: shadowColor.withValues(alpha: 0.08),
                      blurRadius: 16,
                      spreadRadius: 0,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Home button on the left
                _buildGuestNavButton(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  label: 'Home',
                  isSelected: true,
                  primary: primary,
                  colorScheme: colorScheme,
                  onTap: () {
                    // Already on home, no action needed
                  },
                ),
                // Login button on the right
                _buildLoginButton(primary),
              ],
            ),
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
    required Color primary,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
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

  Widget _buildLoginButton(Color primary) {
    return InkWell(
      onTap: () {
        RouterClass.nextScreenNormal(context, const LoginScreen());
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primary, primary.withValues(alpha: 0.8)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
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
