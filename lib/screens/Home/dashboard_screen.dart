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

  // Track which screens have been visited to preserve their state
  final Map<int, Widget> _screenCache = {};
  final Set<int> _visitedScreens = {};

  @override
  void initState() {
    super.initState();
    Logger.debug('📱 DashboardScreen: initState started');
    _selectedIndex = widget.initialIndex;
    // Mark the initial screen as visited
    _visitedScreens.add(_selectedIndex);
    Logger.debug('📱 DashboardScreen: initState finished - lazy loading enabled');
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
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
            // Mark screen as visited when user navigates to it
            _visitedScreens.add(index);
          });
        },
        hasScrolledContent: _hasScrolledContent,
      ),
    );
  }

  Widget _bodyView() {
    // PERFORMANCE FIX: Use lazy loading instead of IndexedStack
    // Only build screens that have been visited to prevent all tabs from
    // loading simultaneously and blocking the main thread
    // This fixes the "Skipped 418 frames" issue
    return IndexedStack(
      index: _selectedIndex,
      sizing: StackFit.expand,
      children: List.generate(6, (index) {
        // Only build the screen if it has been visited
        if (_visitedScreens.contains(index)) {
          // Cache the screen widget to preserve its state
          return _screenCache.putIfAbsent(index, () => _buildScreen(index));
        }
        // Return a placeholder for unvisited screens
        return const SizedBox.shrink();
      }),
    );
  }

  Widget _buildScreen(int index) {
    Logger.debug('📱 DashboardScreen: Building screen $index');
    switch (index) {
      case 0:
        return const HomeHubScreen();
      case 1:
        return const GroupsScreen();
      case 2:
        return const MessagingScreen();
      case 3:
        return const MyProfileScreen(showBackButton: false);
      case 4:
        return const NotificationsScreen();
      case 5:
        return const AccountScreen();
      default:
        return const SizedBox.shrink();
    }
  }
}
