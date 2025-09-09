import 'package:flutter/material.dart';
import 'package:attendus/screens/Home/dashboard_screen.dart';

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
    final Color primary = const Color(0xFF667EEA);
    final Color barColor = Colors.white;

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
                      color: Colors.black.withValues(alpha: 0.08),
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
                  color: selected ? primary : const Color(0xFF9CA3AF),
                  size: 24,
                );
              }),
            ),
            child: NavigationBar(
              height: 64,
              selectedIndex: widget.selectedIndex ?? 0,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              onDestinationSelected: _navigateToTab,
              destinations: const [
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
