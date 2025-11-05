import 'dart:convert';

/// Model for persisting navigation route configuration
class RouteConfig {
  final String routeName;
  final Map<String, dynamic> parameters;
  final int? tabIndex;
  final DateTime timestamp;
  final List<RouteConfig>? navigationStack;

  RouteConfig({
    required this.routeName,
    this.parameters = const {},
    this.tabIndex,
    DateTime? timestamp,
    this.navigationStack,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'routeName': routeName,
      'parameters': parameters,
      'tabIndex': tabIndex,
      'timestamp': timestamp.toIso8601String(),
      'navigationStack': navigationStack?.map((r) => r.toJson()).toList(),
    };
  }

  /// Create from JSON
  factory RouteConfig.fromJson(Map<String, dynamic> json) {
    return RouteConfig(
      routeName: json['routeName'] as String,
      parameters: Map<String, dynamic>.from(json['parameters'] ?? {}),
      tabIndex: json['tabIndex'] as int?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      navigationStack: (json['navigationStack'] as List<dynamic>?)
          ?.map((item) => RouteConfig.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Convert to JSON string
  String toJsonString() {
    return jsonEncode(toJson());
  }

  /// Create from JSON string
  factory RouteConfig.fromJsonString(String jsonString) {
    return RouteConfig.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  /// Check if the route is still valid (not too old)
  bool isValid({Duration maxAge = const Duration(minutes: 30)}) {
    final age = DateTime.now().difference(timestamp);
    return age <= maxAge;
  }

  /// Create a copy with updated fields
  RouteConfig copyWith({
    String? routeName,
    Map<String, dynamic>? parameters,
    int? tabIndex,
    DateTime? timestamp,
    List<RouteConfig>? navigationStack,
  }) {
    return RouteConfig(
      routeName: routeName ?? this.routeName,
      parameters: parameters ?? this.parameters,
      tabIndex: tabIndex ?? this.tabIndex,
      timestamp: timestamp ?? this.timestamp,
      navigationStack: navigationStack ?? this.navigationStack,
    );
  }

  @override
  String toString() {
    return 'RouteConfig(routeName: $routeName, tabIndex: $tabIndex, timestamp: $timestamp, params: $parameters)';
  }
}

/// Navigation state containing the full stack and current position
class NavigationState {
  final List<RouteConfig> stack;
  final int currentIndex;
  final int? currentTabIndex;
  final DateTime timestamp;

  NavigationState({
    required this.stack,
    this.currentIndex = 0,
    this.currentTabIndex,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Get the current route
  RouteConfig? get currentRoute {
    if (stack.isEmpty || currentIndex >= stack.length) return null;
    return stack[currentIndex];
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'stack': stack.map((r) => r.toJson()).toList(),
      'currentIndex': currentIndex,
      'currentTabIndex': currentTabIndex,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Create from JSON
  factory NavigationState.fromJson(Map<String, dynamic> json) {
    return NavigationState(
      stack: (json['stack'] as List<dynamic>)
          .map((item) => RouteConfig.fromJson(item as Map<String, dynamic>))
          .toList(),
      currentIndex: json['currentIndex'] as int? ?? 0,
      currentTabIndex: json['currentTabIndex'] as int?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// Convert to JSON string
  String toJsonString() {
    return jsonEncode(toJson());
  }

  /// Create from JSON string
  factory NavigationState.fromJsonString(String jsonString) {
    return NavigationState.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  /// Check if the state is still valid
  bool isValid({Duration maxAge = const Duration(minutes: 30)}) {
    final age = DateTime.now().difference(timestamp);
    return age <= maxAge && stack.isNotEmpty;
  }

  @override
  String toString() {
    return 'NavigationState(stack: ${stack.length} routes, currentIndex: $currentIndex, tabIndex: $currentTabIndex)';
  }
}

