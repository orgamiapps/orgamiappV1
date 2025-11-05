import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendus/models/route_config.dart';
import 'package:attendus/Utils/route_names.dart';
import 'package:attendus/Utils/logger.dart';

/// Service for persisting and restoring navigation state
class NavigationStateService {
  static final NavigationStateService _instance = NavigationStateService._internal();
  factory NavigationStateService() => _instance;
  NavigationStateService._internal();

  // Storage keys
  static const String _keyNavigationState = 'navigation_state';
  static const String _keyLastRoute = 'last_route';
  static const String _keyLastTabIndex = 'last_tab_index';

  // Current state tracking
  RouteConfig? _lastRoute;
  int? _lastTabIndex;

  // Cache SharedPreferences instance
  SharedPreferences? _prefs;

  /// Initialize the service
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      Logger.info('NavigationStateService initialized');
    } catch (e) {
      Logger.error('Failed to initialize NavigationStateService: $e');
    }
  }

  /// Ensure SharedPreferences is loaded
  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Save the current navigation state
  Future<void> saveNavigationState({
    required String routeName,
    Map<String, dynamic>? parameters,
    int? tabIndex,
  }) async {
    try {
      // Don't save if route shouldn't be persisted
      if (!RouteNames.shouldPersistRoute(routeName)) {
        Logger.debug('Skipping save for non-persistable route: $routeName');
        return;
      }

      final prefs = await _getPrefs();
      
      // Create route config
      final routeConfig = RouteConfig(
        routeName: routeName,
        parameters: parameters ?? {},
        tabIndex: tabIndex,
      );

      // Save last route
      _lastRoute = routeConfig;
      await prefs.setString(_keyLastRoute, routeConfig.toJsonString());

      // Save tab index if provided
      if (tabIndex != null) {
        _lastTabIndex = tabIndex;
        await prefs.setInt(_keyLastTabIndex, tabIndex);
      }

      Logger.debug('Saved navigation state: $routeName (tab: $tabIndex)');
    } catch (e) {
      Logger.error('Failed to save navigation state: $e');
    }
  }

  /// Save just the tab index (for quick tab switches)
  Future<void> saveTabIndex(int tabIndex) async {
    try {
      final prefs = await _getPrefs();
      _lastTabIndex = tabIndex;
      await prefs.setInt(_keyLastTabIndex, tabIndex);
      Logger.debug('Saved tab index: $tabIndex');
    } catch (e) {
      Logger.error('Failed to save tab index: $e');
    }
  }

  /// Restore the last navigation state
  Future<RouteConfig?> restoreNavigationState() async {
    try {
      final prefs = await _getPrefs();
      
      // Try to restore last route
      final routeJson = prefs.getString(_keyLastRoute);
      if (routeJson != null) {
        final route = RouteConfig.fromJsonString(routeJson);
        
        // Check if route is still valid (not too old)
        if (route.isValid()) {
          _lastRoute = route;
          Logger.info('Restored navigation state: ${route.routeName}');
          return route;
        } else {
          Logger.info('Saved route is too old, ignoring: ${route.routeName}');
          // Clear old state
          await clearNavigationState();
        }
      }
    } catch (e) {
      Logger.error('Failed to restore navigation state: $e');
    }
    return null;
  }

  /// Restore just the tab index
  Future<int?> restoreTabIndex() async {
    try {
      final prefs = await _getPrefs();
      final tabIndex = prefs.getInt(_keyLastTabIndex);
      if (tabIndex != null) {
        _lastTabIndex = tabIndex;
        Logger.debug('Restored tab index: $tabIndex');
        return tabIndex;
      }
    } catch (e) {
      Logger.error('Failed to restore tab index: $e');
    }
    return null;
  }

  /// Check if we should restore navigation state
  Future<bool> shouldRestore() async {
    try {
      final route = await restoreNavigationState();
      return route != null && route.isValid();
    } catch (e) {
      Logger.error('Error checking if should restore: $e');
      return false;
    }
  }

  /// Clear all saved navigation state
  Future<void> clearNavigationState() async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove(_keyNavigationState);
      await prefs.remove(_keyLastRoute);
      await prefs.remove(_keyLastTabIndex);
      
      _lastRoute = null;
      _lastTabIndex = null;
      
      Logger.info('Cleared navigation state');
    } catch (e) {
      Logger.error('Failed to clear navigation state: $e');
    }
  }

  /// Save a full navigation stack (for future enhancement)
  Future<void> saveNavigationStack(NavigationState state) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_keyNavigationState, state.toJsonString());
      Logger.debug('Saved full navigation stack: ${state.stack.length} routes');
    } catch (e) {
      Logger.error('Failed to save navigation stack: $e');
    }
  }

  /// Restore the full navigation stack (for future enhancement)
  Future<NavigationState?> restoreNavigationStack() async {
    try {
      final prefs = await _getPrefs();
      final stateJson = prefs.getString(_keyNavigationState);
      if (stateJson != null) {
        final state = NavigationState.fromJsonString(stateJson);
        if (state.isValid()) {
          Logger.info('Restored navigation stack: ${state.stack.length} routes');
          return state;
        } else {
          Logger.info('Saved navigation stack is too old, ignoring');
          await clearNavigationState();
        }
      }
    } catch (e) {
      Logger.error('Failed to restore navigation stack: $e');
    }
    return null;
  }

  /// Get the last saved route (cached)
  RouteConfig? get lastRoute => _lastRoute;

  /// Get the last saved tab index (cached)
  int? get lastTabIndex => _lastTabIndex;

  /// Track route from Navigator observer
  void trackRoute(Route<dynamic> route, {int? tabIndex}) {
    try {
      // Extract route name and settings
      final routeName = route.settings.name;
      final arguments = route.settings.arguments;

      if (routeName != null) {
        // Convert arguments to map if possible
        Map<String, dynamic>? parameters;
        if (arguments is Map<String, dynamic>) {
          parameters = arguments;
        } else if (arguments != null) {
          // Try to extract basic info from arguments
          parameters = {'arguments': arguments.toString()};
        }

        // Save the route
        saveNavigationState(
          routeName: routeName,
          parameters: parameters,
          tabIndex: tabIndex ?? _lastTabIndex,
        );
      } else {
        Logger.debug('Route has no name, cannot track');
      }
    } catch (e) {
      Logger.error('Error tracking route: $e');
    }
  }

  /// Clear state on logout
  Future<void> onLogout() async {
    await clearNavigationState();
    Logger.info('Navigation state cleared on logout');
  }
}

