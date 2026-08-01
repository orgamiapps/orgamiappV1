import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/screens/Home/home_hub_screen.dart';
import 'package:attendus/screens/MyProfile/my_profile_screen.dart'
    deferred as profile;
import 'package:attendus/screens/Home/notifications_screen.dart'
    deferred as notifications;
import 'package:attendus/screens/Messaging/messaging_screen.dart'
    deferred as messaging;
import 'package:attendus/screens/Messaging/new_message_screen.dart'
    deferred as new_message;
import 'package:attendus/screens/Groups/groups_screen.dart' deferred as groups;
import 'package:attendus/screens/Home/account_screen.dart' deferred as account;
import 'package:attendus/widgets/attendus_scaffold.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Services/navigation_state_service.dart';
import 'package:attendus/Utils/route_names.dart';
import 'package:attendus/widgets/deferred_screen_loader.dart';

class DashboardScreen extends StatefulWidget {
  final int initialIndex;
  final bool restoreSavedTab;

  const DashboardScreen({
    super.key,
    this.initialIndex = 0,
    this.restoreSavedTab = true,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const List<AttendUsNavDestination> _destinations = [
    AttendUsNavDestination(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    AttendUsNavDestination(
      label: 'Groups',
      icon: Icons.apartment_outlined,
      selectedIcon: Icons.apartment,
    ),
    AttendUsNavDestination(
      label: 'Messages',
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum,
    ),
    AttendUsNavDestination(
      label: 'Profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
    AttendUsNavDestination(
      label: 'Account',
      icon: Icons.menu_outlined,
      selectedIcon: Icons.menu,
    ),
  ];

  late int _selectedIndex;
  final NavigationStateService _navStateService = NavigationStateService();

  final Map<int, Widget> _screenCache = {};
  final Set<int> _visitedScreens = {};

  @override
  void initState() {
    super.initState();
    Logger.debug('DashboardScreen: initState started');

    _navStateService.initialize();
    _selectedIndex = _normalizeIndex(widget.initialIndex);
    _restoreTabIndexIfNeeded();
    _visitedScreens.add(_selectedIndex);

    Logger.debug('DashboardScreen: initState finished');
  }

  Future<void> _restoreTabIndexIfNeeded() async {
    if (!widget.restoreSavedTab) {
      Logger.debug('DashboardScreen: Saved tab restore disabled');
      return;
    }
    if (widget.initialIndex != 0) {
      Logger.debug(
        'DashboardScreen: Using provided initialIndex: $_selectedIndex',
      );
      return;
    }

    try {
      final savedTabIndex = await _navStateService.restoreTabIndex();
      if (savedTabIndex == null) return;

      final normalizedIndex = _normalizeIndex(savedTabIndex);
      if (normalizedIndex != _selectedIndex) {
        setState(() {
          _selectedIndex = normalizedIndex;
          _visitedScreens.add(_selectedIndex);
        });
        Logger.debug('DashboardScreen: Restored tab index: $_selectedIndex');
      }
    } catch (e) {
      Logger.warning('Failed to restore tab index: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    return AttendUsScaffold(
      title: _getTitleForTab(_selectedIndex),
      subtitle: _getSubtitleForTab(_selectedIndex),
      selectedIndex: _selectedIndex,
      destinations: _destinations,
      actions: _actionsForTab(_selectedIndex),
      onNotificationsPressed: _openNotifications,
      onProfilePressed: () => _selectTab(RouteNames.accountTab),
      profileName: authUser?.displayName ?? authUser?.email,
      profileImageUrl: authUser?.photoURL,
      onDestinationSelected: (index) {
        final normalizedIndex = _normalizeIndex(index);
        _selectTab(normalizedIndex);
      },
      body: _bodyView(),
    );
  }

  int _normalizeIndex(int index) {
    return RouteNames.normalizeDashboardTabIndex(index);
  }

  void _selectTab(int index) {
    final normalizedIndex = _normalizeIndex(index);
    if (_selectedIndex == normalizedIndex) return;
    setState(() {
      _selectedIndex = normalizedIndex;
      _visitedScreens.add(normalizedIndex);
    });
    _saveTabChange(normalizedIndex);
  }

  Future<void> _openNotifications() async {
    try {
      await notifications.loadLibrary();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => notifications.NotificationsScreen()),
      );
    } catch (error) {
      _showDeferredRouteError('Notifications', _openNotifications);
    }
  }

  Future<void> _openNewMessage() async {
    try {
      await new_message.loadLibrary();
      if (!mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => new_message.NewMessageScreen()));
    } catch (error) {
      _showDeferredRouteError('New message', _openNewMessage);
    }
  }

  void _showDeferredRouteError(String label, VoidCallback retry) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label could not be loaded.'),
        action: SnackBarAction(label: 'Retry', onPressed: retry),
      ),
    );
  }

  List<Widget> _actionsForTab(int index) {
    if (index == RouteNames.messagesTab) {
      return [
        IconButton(
          tooltip: 'New message',
          onPressed: _openNewMessage,
          icon: const Icon(Icons.add_comment_outlined),
        ),
      ];
    }
    return const [];
  }

  Widget _bodyView() {
    return IndexedStack(
      index: _selectedIndex,
      sizing: StackFit.expand,
      children: List.generate(_destinations.length, (index) {
        if (_visitedScreens.contains(index)) {
          return _screenCache.putIfAbsent(index, () => _buildScreen(index));
        }
        return const SizedBox.shrink();
      }),
    );
  }

  Widget _buildScreen(int index) {
    Logger.debug('DashboardScreen: Building screen $index');
    switch (index) {
      case 0:
        return const HomeHubScreen();
      case 1:
        return DeferredScreenLoader(
          loadLibrary: groups.loadLibrary,
          loadingLabel: 'Loading groups',
          builder: () => groups.GroupsScreen(),
        );
      case 2:
        return DeferredScreenLoader(
          loadLibrary: messaging.loadLibrary,
          loadingLabel: 'Loading messages',
          builder: () => messaging.MessagingScreen(showShellHeader: false),
        );
      case 3:
        return DeferredScreenLoader(
          loadLibrary: profile.loadLibrary,
          loadingLabel: 'Loading profile',
          builder: () => profile.MyProfileScreen(showBackButton: false),
        );
      case 4:
        return DeferredScreenLoader(
          loadLibrary: account.loadLibrary,
          loadingLabel: 'Loading account',
          builder: () => account.AccountScreen(),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _saveTabChange(int index) {
    try {
      _navStateService.saveTabIndex(index);
      _navStateService.saveNavigationState(
        routeName: _getRouteNameForTab(index),
        tabIndex: index,
      );
      Logger.debug('DashboardScreen: Saved tab change to index $index');
    } catch (e) {
      Logger.error('Failed to save tab change: $e');
    }
  }

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
        return RouteNames.account;
      default:
        return RouteNames.dashboard;
    }
  }

  String _getTitleForTab(int index) {
    switch (index) {
      case 0:
        return 'Discover';
      case 1:
        return 'Groups';
      case 2:
        return 'Messages';
      case 3:
        return 'Profile';
      case 4:
        return 'Account';
      default:
        return 'Attendus';
    }
  }

  String _getSubtitleForTab(int index) {
    switch (index) {
      case 0:
        return 'Find events, check in, and manage what is next.';
      case 1:
        return 'Build communities and organize shared events.';
      case 2:
        return 'Keep conversations tied to people and events.';
      case 3:
        return 'Your identity, activity, tickets, and badges.';
      case 4:
        return 'Settings, subscriptions, analytics, and account tools.';
      default:
        return 'Professional event attendance management.';
    }
  }
}
