import 'package:flutter/material.dart';
import 'package:orgami/Screens/Home/home_hub_screen.dart';
import 'package:orgami/Screens/Home/account_screen.dart';
import 'package:orgami/Screens/Home/notifications_screen.dart';
import 'package:orgami/Screens/Messaging/messaging_screen.dart';
import 'package:orgami/screens/Organizations/organizations_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  int _selectedIndex = 0;

  final List<Widget> _dashBoardScreens = const [
    HomeHubScreen(),
    OrganizationsScreen(),
    MessagingScreen(),
    NotificationsScreen(),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _bodyView()),
      bottomNavigationBar: _buildModernBottomBar(),
    );
  }

  Widget _bodyView() {
    return SizedBox(
      height: _screenHeight,
      width: _screenWidth,
      child: Column(
        children: [Expanded(child: _dashBoardScreens[_selectedIndex])],
      ),
    );
  }

  Widget _buildModernBottomBar() {
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: barColor,
              indicatorColor: primary.withOpacity(0.12),
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
              selectedIndex: _selectedIndex,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              onDestinationSelected: (index) => setState(() {
                _selectedIndex = index;
              }),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.event_outlined),
                  selectedIcon: Icon(Icons.event),
                  label: 'Events',
                ),
                NavigationDestination(
                  icon: Icon(Icons.apartment_outlined),
                  selectedIcon: Icon(Icons.apartment),
                  label: 'Orgs',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  selectedIcon: Icon(Icons.chat_bubble),
                  label: 'Messages',
                ),
                NavigationDestination(
                  icon: Icon(Icons.notifications_none),
                  selectedIcon: Icon(Icons.notifications),
                  label: 'Alerts',
                ),
                NavigationDestination(
                  icon: Icon(Icons.menu),
                  selectedIcon: Icon(Icons.menu),
                  label: 'Menu',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
