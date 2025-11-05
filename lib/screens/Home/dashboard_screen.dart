import 'package:flutter/material.dart';
import 'package:attendus/screens/Home/home_hub_screen.dart';
import 'package:attendus/screens/MyProfile/my_profile_screen.dart';
import 'package:attendus/screens/Home/notifications_screen.dart';
import 'package:attendus/screens/Messaging/messaging_screen.dart';
import 'package:attendus/screens/Groups/groups_screen.dart';
import 'package:attendus/screens/Home/account_screen.dart';
import 'package:attendus/widgets/app_bottom_navigation.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Services/navigation_state_service.dart';
import 'package:attendus/Utils/route_names.dart';

class DashboardScreen extends StatefulWidget {
  final int initialIndex;

  const DashboardScreen({super.key, this.initialIndex = 0});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late int _selectedIndex;
  bool _hasScrolledContent = false;
  final NavigationStateService _navStateService = NavigationStateService();

  // Track which screens have been visited to preserve their state
  final Map<int, Widget> _screenCache = {};
  final Set<int> _visitedScreens = {};

  @override
  void initState() {
    super.initState();
    Logger.debug('📱 DashboardScreen: initState started');
    
    // Initialize navigation state service
    _navStateService.initialize();
    
    // Initialize selected index synchronously with default or provided value
    _selectedIndex = widget.initialIndex;
    
    // Try to restore tab index from saved state asynchronously
    _restoreTabIndexIfNeeded();
    
    // Mark the initial screen as visited
    _visitedScreens.add(_selectedIndex);
    Logger.debug('📱 DashboardScreen: initState finished - lazy loading enabled');
  }

  /// Restore tab index from saved state if no explicit initial index was provided
  Future<void> _restoreTabIndexIfNeeded() async {
    // Only restore if using default index (0)
    if (widget.initialIndex != 0) {
      Logger.debug('📱 DashboardScreen: Using provided initialIndex: $_selectedIndex');
      return;
    }

    // Try to restore from saved state
    try {
      final savedTabIndex = await _navStateService.restoreTabIndex();
      if (savedTabIndex != null && savedTabIndex != _selectedIndex) {
        setState(() {
          _selectedIndex = savedTabIndex;
          _visitedScreens.add(_selectedIndex);
        });
        Logger.debug('📱 DashboardScreen: Restored tab index: $_selectedIndex');
      }
    } catch (e) {
      Logger.warning('Failed to restore tab index: $e');
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
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
            // Mark screen as visited when user navigates to it
            _visitedScreens.add(index);
          });
          
          // Save tab index to navigation state
          _saveTabChange(index);
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

  /// Save tab change to navigation state service
  void _saveTabChange(int index) {
    try {
      // Save just the tab index
      _navStateService.saveTabIndex(index);
      
      // Also save with route name for the tab
      String routeName = _getRouteNameForTab(index);
      _navStateService.saveNavigationState(
        routeName: routeName,
        tabIndex: index,
      );
      
      Logger.debug('📱 DashboardScreen: Saved tab change to index $index');
    } catch (e) {
      Logger.error('Failed to save tab change: $e');
    }
  }

  /// Get route name for tab index
  String _getRouteNameForTab(int index) {
    switch (index) {
      case 0:
        return RouteNames.homeHub;
      case 1:
        return RouteNames.groups;
      case 2:
        return RouteNames.messaging;
      case 3:
        return RouteNames.myProfile;
      case 4:
        return RouteNames.notifications;
      case 5:
        return RouteNames.account;
      default:
        return RouteNames.dashboard;
    }
  }
}
