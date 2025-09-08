import 'package:flutter/material.dart';
import 'package:attendus/screens/Home/home_hub_screen.dart';
import 'package:attendus/screens/MyProfile/my_profile_screen.dart';
import 'package:attendus/screens/Home/notifications_screen.dart';
import 'package:attendus/screens/Messaging/messaging_screen.dart';
import 'package:attendus/screens/Groups/groups_screen.dart';
import 'package:attendus/screens/Home/account_screen.dart';
import 'package:attendus/widgets/app_bottom_navigation.dart';

class DashboardScreen extends StatefulWidget {
  final int initialIndex;

  const DashboardScreen({super.key, this.initialIndex = 0});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  late int _selectedIndex;
  bool _hasScrolledContent = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

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
      bottomNavigationBar: AppBottomNavigation(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() {
          _selectedIndex = index;
        }),
        hasScrolledContent: _hasScrolledContent,
      ),
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
}
