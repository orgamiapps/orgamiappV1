import 'dart:convert';

import 'package:attendus/models/discovery_marketplace.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DiscoveryMarketplaceService {
  DiscoveryMarketplaceService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _functionsOverride = functions,
       _firestoreOverride = firestore,
       _authOverride = auth;

  final FirebaseFunctions? _functionsOverride;
  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'us-central1');
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  User get _accountUser {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('A full account is required.');
    }
    return user;
  }

  Future<DiscoveryHomeResult> home({
    required double latitude,
    required double longitude,
    int radiusMiles = 25,
    bool nationwide = false,
    List<String> preferredCategories = const [],
    String regionCode = '',
    int experienceVersion = 1,
    String? selectedCategoryId,
    String? datePreset,
    bool freeOnly = false,
    bool onlineOnly = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = [
      'discovery_home_v$experienceVersion',
      nationwide
          ? 'us'
          : '${latitude.toStringAsFixed(2)}_${longitude.toStringAsFixed(2)}',
      selectedCategoryId ?? 'all',
      datePreset ?? 'any',
      freeOnly ? 'free' : 'paid',
      onlineOnly ? 'online' : 'all-modes',
      preferredCategories.join(','),
    ].join('_');
    final cachedRaw = prefs.getString(cacheKey);
    Map<String, dynamic>? cached;
    if (cachedRaw != null) {
      try {
        cached = Map<String, dynamic>.from(jsonDecode(cachedRaw) as Map);
      } catch (_) {}
    }
    final cachedAt = DateTime.tryParse(cached?['_cachedAt']?.toString() ?? '');
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 10)) {
      cached['_cacheState'] = 'warm';
      return DiscoveryHomeResult.fromMap(cached);
    }
    try {
      Future<Map<String, dynamic>> requestVersion(int version) async {
        final response = await _functions
            .httpsCallable('getDiscoveryHomeV$version')
            .call({
              'latitude': latitude,
              'longitude': longitude,
              'radiusMiles': radiusMiles,
              'timeZone': DateTime.now().timeZoneName,
              'nationwide': nationwide,
              'preferredCategories': preferredCategories,
              'regionCode': regionCode,
              'selectedCategoryId': ?selectedCategoryId,
              'datePreset': ?datePreset,
              'freeOnly': freeOnly,
              'onlineOnly': onlineOnly,
            });
        return Map<String, dynamic>.from(response.data as Map);
      }

      late Map<String, dynamic> data;
      try {
        data = await requestVersion(experienceVersion);
      } catch (_) {
        if (experienceVersion != 2) rethrow;
        data = await requestVersion(1);
        data['_experienceFallback'] = 'v1';
      }
      data['_cachedAt'] = DateTime.now().toIso8601String();
      await prefs.setString(cacheKey, jsonEncode(data));
      return DiscoveryHomeResult.fromMap(data);
    } catch (_) {
      if (cached != null) {
        cached['_cacheState'] = 'stale';
        return DiscoveryHomeResult.fromMap(cached);
      }
      rethrow;
    }
  }

  Future<DiscoverySearchResult> search({
    required double latitude,
    required double longitude,
    required int radiusMiles,
    String query = '',
    String? datePreset,
    String? category,
    bool onlineOnly = false,
    bool freeOnly = false,
    bool nationwide = false,
    String? cursor,
    int limit = 24,
    int experienceVersion = 1,
  }) async {
    Future<DiscoverySearchResult> requestVersion(int version) async {
      final response = await _functions
          .httpsCallable('searchDiscoveryEventsV$version')
          .call({
            'latitude': latitude,
            'longitude': longitude,
            'radiusMiles': radiusMiles,
            'query': query,
            'datePreset': ?datePreset,
            if (version == 1) 'category': ?category,
            if (version == 2) 'categoryId': ?category,
            'onlineOnly': onlineOnly,
            'freeOnly': freeOnly,
            'nationwide': nationwide,
            'cursor': ?cursor,
            'limit': limit,
          });
      return DiscoverySearchResult.fromMap(
        Map<String, dynamic>.from(response.data as Map),
      );
    }

    try {
      return await requestVersion(experienceVersion);
    } catch (_) {
      if (experienceVersion != 2) rethrow;
      return requestVersion(1);
    }
  }

  Future<Set<String>> savedEventIds() async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return const {};
    final results = await Future.wait([
      _firestore
          .collection('Customers')
          .doc(user.uid)
          .collection('SavedEvents')
          .get(),
      _firestore.collection('Customers').doc(user.uid).get(),
    ]);
    final saved = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final customer = results[1] as DocumentSnapshot<Map<String, dynamic>>;
    return {
      ...saved.docs.map((doc) => doc.id),
      ...List<String>.from(customer.data()?['favorites'] ?? const []),
    };
  }

  Future<void> setSaved(String eventId, bool saved) async {
    final user = _accountUser;
    final ref = _firestore
        .collection('Customers')
        .doc(user.uid)
        .collection('SavedEvents')
        .doc(eventId);
    if (saved) {
      await ref.set({
        'eventId': eventId,
        'userId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.delete();
    }
  }

  Future<void> setOrganizationFollow(
    String organizationId,
    bool following,
  ) async {
    final user = _accountUser;
    final ref = _firestore
        .collection('Organizations')
        .doc(organizationId)
        .collection('Followers')
        .doc(user.uid);
    if (following) {
      await ref.set({
        'userId': user.uid,
        'organizationId': organizationId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.delete();
    }
  }

  Future<void> savePreferences({
    required String city,
    required String regionCode,
    required double latitude,
    required double longitude,
    required String locationSource,
    List<String>? preferredCategories,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return;
    await _firestore
        .collection('Customers')
        .doc(user.uid)
        .collection('Discovery')
        .doc('preferences')
        .set({
          'chosenCity': city,
          'regionCode': regionCode,
          'countryCode': 'US',
          'latitude': latitude,
          'longitude': longitude,
          'locationSource': locationSource,
          'preferredCategories': ?preferredCategories,
          'notificationRadius': 25,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> recordBehavior({
    required List<String> categories,
    required String organizerId,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return;
    await _firestore
        .collection('Customers')
        .doc(user.uid)
        .collection('Discovery')
        .doc('behavior')
        .set({
          if (categories.isNotEmpty)
            'recentCategories': FieldValue.arrayUnion(
              categories.take(5).toList(),
            ),
          if (organizerId.isNotEmpty)
            'viewedOrganizerIds': FieldValue.arrayUnion([organizerId]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }
}
