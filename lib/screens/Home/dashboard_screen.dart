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

  @override
  void initState() {
    super.initState();
    Logger.debug('📱 DashboardScreen: initState started');
    _selectedIndex = widget.initialIndex;
    Logger.debug('📱 DashboardScreen: initState finished - rendering immediately');
  }

  // Lazy initialization of screens to prevent all screens from building at once
  Widget _getScreen(int index) {
    Logger.debug('📱 DashboardScreen: Building screen for index $index');
    switch (index) {
      case 0:
        Logger.debug('📱 DashboardScreen: Creating HomeHubScreen');
        return const HomeHubScreen();
      case 1:
        Logger.debug('📱 DashboardScreen: Creating GroupsScreen');
        return const GroupsScreen();
      case 2:
        Logger.debug('📱 DashboardScreen: Creating MessagingScreen');
        return const MessagingScreen();
      case 3:
        Logger.debug('📱 DashboardScreen: Creating MyProfileScreen');
        return const MyProfileScreen(showBackButton: false);
      case 4:
        Logger.debug('📱 DashboardScreen: Creating NotificationsScreen');
        return const NotificationsScreen();
      case 5:
        Logger.debug('📱 DashboardScreen: Creating AccountScreen');
        return const AccountScreen();
      default:
        Logger.debug('📱 DashboardScreen: Creating default HomeHubScreen');
        return const HomeHubScreen();
    }
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
    
    // Always render the content immediately - no loading state
    return SizedBox(
      height: size.height,
      width: size.width,
      child: Column(
        children: [Expanded(child: _getScreen(_selectedIndex))],
      ),
    );
  }
}
