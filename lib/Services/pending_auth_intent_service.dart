import 'dart:convert';

import 'package:attendus/Services/account_access_service.dart';
import 'package:attendus/Utils/route_names.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PendingAuthAction { dashboardTab, createEvent, sharedEvent, saveEvent }

class PendingAuthIntent {
  final PendingAuthAction action;
  final int? dashboardTab;
  final String? eventId;
  final AccountFeature sourceFeature;
  final DateTime expiresAt;

  const PendingAuthIntent({
    required this.action,
    required this.sourceFeature,
    required this.expiresAt,
    this.dashboardTab,
    this.eventId,
  });

  Map<String, dynamic> toJson() => {
    'action': action.name,
    'dashboardTab': dashboardTab,
    'eventId': eventId,
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
    return PendingAuthIntent(
      action: action,
      dashboardTab: tab,
      eventId: eventId,
      sourceFeature: feature,
      expiresAt: expiresAt,
    );
  }
}

class PendingAuthIntentService {
  static const String _storageKey = 'pending_auth_intent_v1';
  static const Duration _lifetime = Duration(minutes: 30);

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
    await prefs.setString(_storageKey, jsonEncode(intent.toJson()));
  }

  static Future<void> rememberSharedEvent(String eventId) async {
    final normalizedId = eventId.trim();
    if (normalizedId.isEmpty) return;
    final intent = PendingAuthIntent(
      action: PendingAuthAction.sharedEvent,
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
