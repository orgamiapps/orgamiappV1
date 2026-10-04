import 'dart:convert';

import 'package:attendus/Services/account_access_service.dart';
import 'package:attendus/Utils/route_names.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PendingAuthAction {
  dashboardTab,
  createEvent,
  sharedEvent,
  saveEvent,
  sharedConversation,
  sharedCommunity,
}

class PendingAuthIntent {
  final PendingAuthAction action;
  final int? dashboardTab;
  final String? eventId;
  final String? eventAction;
  final String? conversationId;
  final String? communityId;
  final AccountFeature sourceFeature;
  final DateTime expiresAt;

  const PendingAuthIntent({
    required this.action,
    required this.sourceFeature,
    required this.expiresAt,
    this.dashboardTab,
    this.eventId,
    this.eventAction,
    this.conversationId,
    this.communityId,
  });

  Map<String, dynamic> toJson() => {
    'action': action.name,
    'dashboardTab': dashboardTab,
    'eventId': eventId,
    'eventAction': eventAction,
    'conversationId': conversationId,
    'communityId': communityId,
    'sourceFeature': sourceFeature.name,
    'expiresAt': expiresAt.toIso8601String(),
  };

  static PendingAuthIntent? fromJson(Map<String, dynamic> json) {
    final actionName = json['action']?.toString();
    final featureName = json['sourceFeature']?.toString();
    final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    final action = PendingAuthAction.values
        .where((value) => value.name == actionName)
        .firstOrNull;
    final feature = AccountFeature.values
        .where((value) => value.name == featureName)
        .firstOrNull;
    if (action == null || feature == null || expiresAt == null) return null;
    final storedTab = json['dashboardTab'] as int?;
    if (action == PendingAuthAction.dashboardTab &&
        (storedTab == null || storedTab < RouteNames.homeTab)) {
      return null;
    }
    final tab = storedTab == null
        ? null
        : RouteNames.normalizeDashboardTabIndex(storedTab);
    final eventId = json['eventId']?.toString().trim();
    if (action == PendingAuthAction.sharedEvent &&
        (eventId == null || eventId.isEmpty)) {
      return null;
    }
    if (action == PendingAuthAction.saveEvent &&
        (eventId == null || eventId.isEmpty)) {
      return null;
    }
    final conversationId = json['conversationId']?.toString().trim();
    if (action == PendingAuthAction.sharedConversation &&
        !PendingAuthIntentService.validConversationId(conversationId)) {
      return null;
    }
    final communityId = json['communityId']?.toString().trim();
    if (action == PendingAuthAction.sharedCommunity &&
        (communityId == null || communityId.isEmpty)) {
      return null;
    }
    return PendingAuthIntent(
      communityId: communityId,
      conversationId: conversationId,
      action: action,
      dashboardTab: tab,
      eventId: eventId,
      eventAction:
          const ['rsvp', 'ticket', 'check_in'].contains(json['eventAction'])
          ? json['eventAction'] as String
          : null,
      sourceFeature: feature,
      expiresAt: expiresAt,
    );
  }
}

class PendingAuthIntentService {
  static const String _storageKey = 'pending_auth_intent_v1';
  static const Duration _lifetime = Duration(days: 7);

  static Future<void> rememberCommunity(
    String communityId, {
    AccountFeature feature = AccountFeature.groups,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final intent = PendingAuthIntent(
      action: PendingAuthAction.sharedCommunity,
      sourceFeature: feature,
      communityId: communityId,
      expiresAt: DateTime.now().add(_lifetime),
    );
    await prefs.setString(_storageKey, jsonEncode(intent.toJson()));
  }

  static Future<void> rememberHome() async {
    final prefs = await SharedPreferences.getInstance();
    if (_hasConversation(prefs)) return;
    final intent = _tabIntent(AccountFeature.account, RouteNames.homeTab);
    await prefs.setString(_storageKey, jsonEncode(intent.toJson()));
  }

  static Future<void> rememberFeature(AccountFeature feature) async {
    final intent = switch (feature) {
      AccountFeature.createEvent => PendingAuthIntent(
        action: PendingAuthAction.createEvent,
        sourceFeature: feature,
        expiresAt: DateTime.now().add(_lifetime),
      ),
      AccountFeature.groups ||
      AccountFeature.createGroup ||
      AccountFeature.joinGroup => _tabIntent(feature, RouteNames.groupsTab),
      AccountFeature.messages => _tabIntent(feature, RouteNames.messagesTab),
      AccountFeature.profile || AccountFeature.attendeeProfiles => _tabIntent(
        feature,
        RouteNames.profileTab,
      ),
      _ => _tabIntent(feature, RouteNames.profileTab),
    };
    final prefs = await SharedPreferences.getInstance();
    if (_hasConversation(prefs)) return;
    await prefs.setString(_storageKey, jsonEncode(intent.toJson()));
  }

  static bool validConversationId(String? id) =>
      id != null &&
      id.trim().isNotEmpty &&
      id.length <= 300 &&
      !id.contains('/');

  static bool _hasConversation(SharedPreferences prefs) {
    try {
      final intent = PendingAuthIntent.fromJson(
        jsonDecode(prefs.getString(_storageKey) ?? '{}')
            as Map<String, dynamic>,
      );
      return intent?.action == PendingAuthAction.sharedConversation &&
          intent!.expiresAt.isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  static Future<void> rememberConversation(String? conversationId) async {
    if (!validConversationId(conversationId)) return;
    final intent = PendingAuthIntent(
      action: PendingAuthAction.sharedConversation,
      sourceFeature: AccountFeature.messages,
      dashboardTab: RouteNames.messagesTab,
      conversationId: conversationId!.trim(),
      expiresAt: DateTime.now().add(_lifetime),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(intent.toJson()));
  }

  static Future<void> rememberSharedEvent(
    String eventId, {
    String? action,
  }) async {
    final normalizedId = eventId.trim();
    if (normalizedId.isEmpty) return;
    final intent = PendingAuthIntent(
      action: PendingAuthAction.sharedEvent,
      eventAction: action,
      sourceFeature: AccountFeature.accessRequest,
      eventId: normalizedId,
      expiresAt: DateTime.now().add(_lifetime),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(intent.toJson()));
  }

  static Future<void> rememberSaveEvent(String eventId) async {
    final normalizedId = eventId.trim();
    if (normalizedId.isEmpty) return;
    final intent = PendingAuthIntent(
      action: PendingAuthAction.saveEvent,
      sourceFeature: AccountFeature.favorites,
      eventId: normalizedId,
      expiresAt: DateTime.now().add(_lifetime),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(intent.toJson()));
  }

  static PendingAuthIntent _tabIntent(AccountFeature feature, int tab) =>
      PendingAuthIntent(
        action: PendingAuthAction.dashboardTab,
        dashboardTab: tab,
        sourceFeature: feature,
        expiresAt: DateTime.now().add(_lifetime),
      );

  static Future<PendingAuthIntent?> consume() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    await prefs.remove(_storageKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final intent = PendingAuthIntent.fromJson(decoded);
      if (intent == null || intent.expiresAt.isBefore(DateTime.now())) {
        return null;
      }
      return intent;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
