import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/models/route_config.dart';
import 'package:attendus/Utils/route_names.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/screens/Home/dashboard_screen.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/models/customer_model.dart';

// Event screens
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/screens/Events/edit_event_screen.dart';
import 'package:attendus/screens/Events/ticket_management_screen.dart';
import 'package:attendus/screens/Events/event_analytics_screen.dart';

// Group screens
import 'package:attendus/screens/Groups/group_profile_screen_v2.dart';
import 'package:attendus/screens/Groups/group_analytics_dashboard_screen.dart';
import 'package:attendus/screens/Groups/manage_groups_screen.dart';
import 'package:attendus/screens/Groups/group_admin_settings_screen.dart';
import 'package:attendus/screens/Groups/manage_members_screen.dart';
import 'package:attendus/screens/Groups/manage_feed_posts_screen.dart';
import 'package:attendus/screens/Groups/pending_events_screen.dart';

// Messaging screens
import 'package:attendus/screens/Messaging/chat_screen.dart';
import 'package:attendus/screens/Messaging/new_message_screen.dart';

// Profile screens
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';
import 'package:attendus/screens/MyProfile/my_tickets_screen.dart';

// Quiz screens
import 'package:attendus/screens/LiveQuiz/quiz_builder_screen.dart';
import 'package:attendus/screens/LiveQuiz/quiz_host_screen.dart';
import 'package:attendus/screens/LiveQuiz/quiz_participant_screen.dart';

// Premium screens
import 'package:attendus/screens/Premium/premium_features_screen.dart';
import 'package:attendus/screens/Premium/premium_upgrade_screen_v2.dart';

// Other screens
import 'package:attendus/screens/Home/search_screen.dart';
import 'package:attendus/screens/Home/analytics_dashboard_screen.dart';

/// Helper class to rebuild routes from saved configuration
class RouteBuilder {
  /// Build a widget from a route configuration
  /// Returns DashboardScreen as fallback if route cannot be built
  static Future<Widget> buildRouteFromConfig(RouteConfig config) async {
    try {
      Logger.info('Building route from config: ${config.routeName}');
      
      switch (config.routeName) {
        // Dashboard and main tabs
        case RouteNames.dashboard:
          final tabIndex = config.parameters['initialIndex'] as int? ?? 
                          config.tabIndex ?? 0;
          return DashboardScreen(initialIndex: tabIndex);

        // Event screens
        case RouteNames.singleEvent:
          return await _buildSingleEventScreen(config);

        case RouteNames.createEvent:
          return await _buildCreateEventScreen(config);

        case RouteNames.editEvent:
          return await _buildEditEventScreen(config);

        case RouteNames.ticketManagement:
          return await _buildTicketManagementScreen(config);

        case RouteNames.eventAnalytics:
          return await _buildEventAnalyticsScreen(config);

        // Group screens
        case RouteNames.groupProfile:
          return await _buildGroupProfileScreen(config);

        case RouteNames.groupAnalytics:
          return await _buildGroupAnalyticsScreen(config);

        case RouteNames.manageGroups:
          return await _buildManageGroupsScreen(config);

        case RouteNames.groupAdminSettings:
          return await _buildGroupAdminSettingsScreen(config);

        case RouteNames.manageMembers:
          return await _buildManageMembersScreen(config);

        case RouteNames.manageFeedPosts:
          return await _buildManageFeedPostsScreen(config);

        case RouteNames.pendingEvents:
          return await _buildPendingEventsScreen(config);

        // Messaging screens
        case RouteNames.chatScreen:
          return await _buildChatScreen(config);

        case RouteNames.newMessage:
          return await _buildNewMessageScreen(config);

        // Profile screens
        case RouteNames.userProfile:
          return await _buildUserProfileScreen(config);

        case RouteNames.myTickets:
          return await _buildMyTicketsScreen(config);

        // Quiz screens
        case RouteNames.quizBuilder:
          return await _buildQuizBuilderScreen(config);

        case RouteNames.quizHost:
          return await _buildQuizHostScreen(config);

        case RouteNames.quizParticipant:
          return await _buildQuizParticipantScreen(config);

        // Premium screens
        case RouteNames.premiumFeatures:
          return await _buildPremiumFeaturesScreen(config);

        case RouteNames.premiumUpgrade:
          return await _buildPremiumUpgradeScreen(config);

        // Other screens
        case RouteNames.search:
          return await _buildSearchScreen(config);

        case RouteNames.analyticsDashboard:
          return await _buildAnalyticsDashboardScreen(config);

        default:
          Logger.warning('Unknown route: ${config.routeName}, using fallback');
          return _getFallbackScreen(config);
      }
    } catch (e, stackTrace) {
      Logger.error('Error building route ${config.routeName}: $e');
      Logger.error('Stack trace: $stackTrace');
      return _getFallbackScreen(config);
    }
  }

  /// Get fallback screen based on tab index or default to home
  static Widget _getFallbackScreen(RouteConfig config) {
    final tabIndex = config.tabIndex ?? 
                     RouteNames.getDashboardTabForRoute(config.routeName) ?? 
                     0;
    return DashboardScreen(initialIndex: tabIndex);
  }

  // Event screen builders
  static Future<Widget> _buildSingleEventScreen(RouteConfig config) async {
    final eventId = config.parameters['eventId'] as String?;
    
    if (eventId != null) {
      try {
        // Fetch event from Firestore
        final doc = await FirebaseFirestore.instance
            .collection(EventModel.firebaseKey)
            .doc(eventId)
            .get();
        
        if (doc.exists) {
          final event = EventModel.fromJson(doc);
          return SingleEventScreen(eventModel: event);
        }
      } catch (e) {
        Logger.error('Error fetching event $eventId: $e');
      }
    }
    
    return _getFallbackScreen(config);
  }

  static Future<Widget> _buildCreateEventScreen(RouteConfig config) async {
    // CreateEventScreen requires selectedLocation and radius, which we can't restore
    // Return to appropriate tab instead
    Logger.warning('CreateEventScreen cannot be restored, returning to Groups tab');
    return _getFallbackScreen(config);
  }

  static Future<Widget> _buildEditEventScreen(RouteConfig config) async {
    final eventId = config.parameters['eventId'] as String?;
    
    if (eventId != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(EventModel.firebaseKey)
            .doc(eventId)
            .get();
        
        if (doc.exists) {
          final event = EventModel.fromJson(doc);
          return EditEventScreen(eventModel: event);
        }
      } catch (e) {
        Logger.error('Error fetching event for edit $eventId: $e');
      }
    }
    
    return _getFallbackScreen(config);
  }

  static Future<Widget> _buildTicketManagementScreen(RouteConfig config) async {
    final eventId = config.parameters['eventId'] as String?;
    
    if (eventId != null) {
      try {
        // Fetch event from Firestore
        final doc = await FirebaseFirestore.instance
            .collection(EventModel.firebaseKey)
            .doc(eventId)
            .get();
        
        if (doc.exists) {
          final event = EventModel.fromJson(doc);
          return TicketManagementScreen(eventModel: event);
        }
      } catch (e) {
        Logger.error('Error fetching event for ticket management $eventId: $e');
      }
    }
    
    return _getFallbackScreen(config);
  }

  static Future<Widget> _buildEventAnalyticsScreen(RouteConfig config) async {
    final eventId = config.parameters['eventId'] as String?;
    
    if (eventId != null) {
      return EventAnalyticsScreen(eventId: eventId);
    }
    
    return _getFallbackScreen(config);
  }

  // Group screen builders
  static Future<Widget> _buildGroupProfileScreen(RouteConfig config) async {
    final organizationId = config.parameters['organizationId'] as String?;
    
    if (organizationId != null) {
      return GroupProfileScreenV2(organizationId: organizationId);
    }
    
    return _getFallbackScreen(config);
  }

  static Future<Widget> _buildGroupAnalyticsScreen(RouteConfig config) async {
    final organizationId = config.parameters['organizationId'] as String?;
    
    if (organizationId != null) {
      return GroupAnalyticsDashboardScreen(organizationId: organizationId);
    }
    
    return _getFallbackScreen(config);
  }

  static Future<Widget> _buildManageGroupsScreen(RouteConfig config) async {
    return const ManageGroupsScreen();
  }

  static Future<Widget> _buildGroupAdminSettingsScreen(RouteConfig config) async {
    final organizationId = config.parameters['organizationId'] as String?;
    
    if (organizationId != null) {
      return GroupAdminSettingsScreen(organizationId: organizationId);
    }
    
    return _getFallbackScreen(config);
  }

  static Future<Widget> _buildManageMembersScreen(RouteConfig config) async {
    final organizationId = config.parameters['organizationId'] as String?;
    
    if (organizationId != null) {
      return ManageMembersScreen(organizationId: organizationId);
    }
    
    return _getFallbackScreen(config);
  }

  static Future<Widget> _buildManageFeedPostsScreen(RouteConfig config) async {
    final organizationId = config.parameters['organizationId'] as String?;
    
    if (organizationId != null) {
      return ManageFeedPostsScreen(organizationId: organizationId);
    }
    
    return _getFallbackScreen(config);
  }

  static Future<Widget> _buildPendingEventsScreen(RouteConfig config) async {
    final organizationId = config.parameters['organizationId'] as String?;
    
    if (organizationId != null) {
      return PendingEventsScreen(organizationId: organizationId);
    }
    
    return _getFallbackScreen(config);
  }

  // Messaging screen builders
  static Future<Widget> _buildChatScreen(RouteConfig config) async {
    final conversationId = config.parameters['conversationId'] as String?;
    
    if (conversationId != null) {
      return ChatScreen(conversationId: conversationId);
    }
    
    return _getFallbackScreen(config);
  }

  static Future<Widget> _buildNewMessageScreen(RouteConfig config) async {
    return const NewMessageScreen();
  }

  // Profile screen builders
  static Future<Widget> _buildUserProfileScreen(RouteConfig config) async {
    final userId = config.parameters['userId'] as String?;
    
    if (userId != null) {
      try {
        // Fetch user from Firestore
        final doc = await FirebaseFirestore.instance
            .collection('Customers')
            .doc(userId)
            .get();
        
        if (doc.exists) {
          final user = CustomerModel.fromFirestore(doc);
          return UserProfileScreen(user: user);
        }
      } catch (e) {
        Logger.error('Error fetching user profile $userId: $e');
      }
    }
    
    return _getFallbackScreen(config);
  }

  static Future<Widget> _buildMyTicketsScreen(RouteConfig config) async {
    return const MyTicketsScreen();
  }

  // Quiz screen builders
  static Future<Widget> _buildQuizBuilderScreen(RouteConfig config) async {
    final eventId = config.parameters['eventId'] as String?;
    
    if (eventId != null) {
      return QuizBuilderScreen(eventId: eventId);
    }
    
    return _getFallbackScreen(config);
  }

  static Future<Widget> _buildQuizHostScreen(RouteConfig config) async {
    final quizId = config.parameters['quizId'] as String?;
    
    if (quizId != null) {
      return QuizHostScreen(quizId: quizId);
    }
    
    return _getFallbackScreen(config);
  }

  static Future<Widget> _buildQuizParticipantScreen(RouteConfig config) async {
    final quizId = config.parameters['quizId'] as String?;
    
    if (quizId != null) {
      final isAnonymous = config.parameters['isAnonymous'] as bool? ?? false;
      final displayName = config.parameters['displayName'] as String?;
      return QuizParticipantScreen(
        quizId: quizId,
        isAnonymous: isAnonymous,
        displayName: displayName,
      );
    }
    
    return _getFallbackScreen(config);
  }

  // Premium screen builders
  static Future<Widget> _buildPremiumFeaturesScreen(RouteConfig config) async {
    return const PremiumFeaturesScreen();
  }

  static Future<Widget> _buildPremiumUpgradeScreen(RouteConfig config) async {
    return const PremiumUpgradeScreenV2();
  }

  // Other screen builders
  static Future<Widget> _buildSearchScreen(RouteConfig config) async {
    return const SearchScreen();
  }

  static Future<Widget> _buildAnalyticsDashboardScreen(RouteConfig config) async {
    return const AnalyticsDashboardScreen();
  }
}

