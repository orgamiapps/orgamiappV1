import 'package:flutter/material.dart';
import 'package:attendus/screens/Home/home_hub_screen.dart';
import 'package:attendus/screens/MyProfile/my_profile_screen.dart';
import 'package:attendus/screens/Home/notifications_screen.dart';
import 'package:attendus/screens/Messaging/messaging_screen.dart';
import 'package:attendus/screens/Groups/groups_screen.dart';
import 'package:attendus/screens/Home/account_screen.dart';
import 'package:attendus/widgets/app_bottom_navigation.dart';
import 'package:attendus/Utils/logger.dart';

class DashboardScreen extends StatefulWidget {
  final int initialIndex;

  const DashboardScreen({super.key, this.initialIndex = 0});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late int _selectedIndex;
  bool _hasScrolledContent = false;

  // Pre-built screens list - IndexedStack keeps widget state and improves performance
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    Logger.debug('📱 DashboardScreen: initState started');
    _selectedIndex = widget.initialIndex;
    
    // Initialize screens list once - IndexedStack will handle caching
    _screens = const [
      HomeHubScreen(),
      GroupsScreen(),
      MessagingScreen(),
      MyProfileScreen(showBackButton: false),
      NotificationsScreen(),
      AccountScreen(),
    ];
    
    Logger.debug('📱 DashboardScreen: initState finished - rendering immediately');
  }

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
    final size = MediaQuery.of(context).size;
    
    // Use IndexedStack for better performance - keeps widget state and avoids rebuilding
    return SizedBox(
      height: size.height,
      width: size.width,
      child: IndexedStack(
        index: _selectedIndex,
        sizing: StackFit.expand,
        children: _screens,
      ),
    );
  }
}
