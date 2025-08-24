import 'package:flutter/material.dart';
import 'package:orgami/screens/Home/home_hub_screen.dart';
import 'package:orgami/screens/MyProfile/my_profile_screen.dart';
import 'package:orgami/screens/Home/notifications_screen.dart';
import 'package:orgami/screens/Messaging/messaging_screen.dart';
import 'package:orgami/screens/Organizations/groups_screen.dart';
import 'package:orgami/screens/Home/account_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  int _selectedIndex = 0;
  bool _hasScrolledContent = false;

  final List<Widget> _dashBoardScreens = const [
    HomeHubScreen(),
    GroupsScreen(),
    MessagingScreen(),
    MyProfileScreen(showBackButton: false),
    NotificationsScreen(),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // Track if any vertical scrollable in the subtree has scrolled from top
          final bool isVertical = notification.metrics.axis == Axis.vertical;
          if (isVertical) {
            final bool scrolled = notification.metrics.pixels > 0.0;
            if (scrolled != _hasScrolledContent) {
              setState(() => _hasScrolledContent = scrolled);
            }
          }
          return false;
        },
        child: SafeArea(child: _bodyView()),
      ),
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
            boxShadow: _hasScrolledContent
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
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
