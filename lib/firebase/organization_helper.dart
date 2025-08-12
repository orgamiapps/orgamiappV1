import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:orgami/Utils/logger.dart';
import 'package:orgami/models/organization_model.dart';
import 'package:orgami/models/organization_membership_model.dart';

class OrganizationHelper {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Live stream of organizations for the current user.
  /// Combines memberships in Organizations/{org}/Members where status == 'approved'.
  Stream<List<Map<String, String>>> streamUserOrganizationsLite() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(const <Map<String, String>>[]);
    }

    // Stream memberships, then resolve to org lite objects
    final membershipQuery = _firestore
        .collectionGroup('Members')
        .where('userId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'approved');

    return membershipQuery.snapshots().asyncMap((snap) async {
      if (snap.docs.isEmpty) {
        // Even if there are no membership docs, include organizations the user owns
        final owned = await _firestore
            .collection('Organizations')
            .where('createdBy', isEqualTo: user.uid)
            .get();
        final List<Map<String, String>> ownedList = owned.docs
            .map((d) => {'id': d.id, 'name': (d.data()['name'] ?? d.data()['title'] ?? '').toString()})
            .toList();
        ownedList.sort((a, b) => (a['name'] ?? '').toLowerCase().compareTo((b['name'] ?? '').toLowerCase()));
        return ownedList;
      }

      final Set<String> orgIds = {};
      for (final d in snap.docs) {
        // Prefer field, but fall back to parent path (Organizations/{orgId}/Members/{uid})
        final data = d.data();
        final String? idFromField = data['organizationId']?.toString();
        final String? idFromPath = d.reference.parent.parent?.id;
        final resolvedId = (idFromField != null && idFromField.isNotEmpty)
            ? idFromField
            : (idFromPath ?? '');
        if (resolvedId.isNotEmpty) orgIds.add(resolvedId);
      }

      // Also include orgs the user owns (creator/admin) in case membership doc is missing
      try {
        final owned = await _firestore
            .collection('Organizations')
            .where('createdBy', isEqualTo: user.uid)
            .get();
        for (final d in owned.docs) {
          orgIds.add(d.id);
        }
      } catch (_) {}

      if (orgIds.isEmpty) return <Map<String, String>>[];

      final futures = orgIds.map(
        (id) => _firestore.collection('Organizations').doc(id).get(),
      );
      final docs = await Future.wait(futures);
      final Map<String, String> idToName = {};
      for (final doc in docs) {
        if (!doc.exists) continue;
        final data = doc.data()!;
        final String name = (data['name'] ?? data['title'] ?? '').toString();
        idToName[doc.id] = name;
      }

      final list = idToName.entries
          .map((e) => {'id': e.key, 'name': e.value})
          .toList();
      list.sort(
        (a, b) => (a['name'] ?? '').toLowerCase().compareTo(
          (b['name'] ?? '').toLowerCase(),
        ),
      );
      return list;
    });
  }

  Future<List<Map<String, String>>> getUserOrganizationsLite() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      final query = await _firestore
          .collectionGroup('Members')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'approved')
          .limit(50)
          .get();

      final Map<String, String> idToName = {};

      for (final doc in query.docs) {
        try {
          final data = doc.data();
          final String? orgIdFromField = data['organizationId'] as String?;
          final String? orgIdFromPath = doc.reference.parent.parent?.id;
          final String? orgId = (orgIdFromField != null && orgIdFromField.isNotEmpty)
              ? orgIdFromField
              : orgIdFromPath;
          if (orgId == null) continue;

          final orgSnap = await _firestore
              .collection('Organizations')
              .doc(orgId)
              .get();
          if (orgSnap.exists) {
            final name = orgSnap.data()!['name']?.toString() ?? '';
            idToName[orgId] = name;
          }
        } catch (e) {
          Logger.error('Error resolving organization from membership: $e');
        }
      }

      // Also include organizations owned by the user (createdBy == uid)
      try {
        final ownedQuery = await _firestore
            .collection('Organizations')
            .where('createdBy', isEqualTo: user.uid)
            .get();
        for (final d in ownedQuery.docs) {
          final data = d.data();
          final String name = (data['name'] ?? data['title'] ?? '').toString();
          idToName[d.id] = name;
        }
      } catch (e) {
        Logger.error('Error loading owned organizations: $e');
      }

      final result = idToName.entries
          .map((e) => {'id': e.key, 'name': e.value})
          .toList();
      result.sort((a, b) => (a['name'] ?? '').toLowerCase().compareTo((b['name'] ?? '').toLowerCase()));
      return result;
    } catch (e) {
      Logger.error('getUserOrganizationsLite failed: $e');
      return [];
    }
  }

  /// Add or update a membership entry for a user in an organization.
  Future<void> addUserToOrganization({
    required String organizationId,
    required String userId,
    String role = 'Member',
  }) async {
    final memberRef = _firestore
        .collection('Organizations')
        .doc(organizationId)
        .collection('Members')
        .doc(userId);

    await memberRef.set({
      'organizationId': organizationId,
      'userId': userId,
      'role': role,
      'permissions': <String>[],
      'status': 'approved',
      'joinedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Remove a user from an organization.
  Future<void> removeUserFromOrganization({
    required String organizationId,
    required String userId,
  }) async {
    final memberRef = _firestore
        .collection('Organizations')
        .doc(organizationId)
        .collection('Members')
        .doc(userId);
    await memberRef.delete();
  }

  Future<String?> createOrganization({
    required String name,
    String? description,
    String? category,
    String? logoUrl,
    String? bannerUrl,
    String defaultEventVisibility = 'public',
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final orgRef = _firestore.collection('Organizations').doc();
      final organization = OrganizationModel(
        id: orgRef.id,
        name: name,
        description: description ?? '',
        category: category ?? 'Other',
        logoUrl: logoUrl,
        bannerUrl: bannerUrl,
        defaultEventVisibility: defaultEventVisibility,
        createdBy: user.uid,
        createdAt: DateTime.now(),
      );
      // Write org document including lowercase fields in a single set
      final data = organization.toJson();
      data['name_lowercase'] = name.toLowerCase();
      data['category_lowercase'] = (category ?? 'other').toLowerCase();
      await orgRef.set(data);

      final memberRef = orgRef.collection('Members').doc(user.uid);
      final membership = OrganizationMembership(
        organizationId: orgRef.id,
        userId: user.uid,
        role: 'Admin',
        permissions: const [
          'CreateEditEvents',
          'ApproveJoinRequests',
          'ManageMembersRoles',
          'ViewAnalytics',
        ],
        status: 'approved',
        joinedAt: DateTime.now(),
      );
      await memberRef.set(membership.toJson());

      return orgRef.id;
    } catch (e) {
      Logger.error('Failed to create organization: $e');
      return null;
    }
  }

  Future<void> requestToJoinOrganization(String organizationId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final reqRef = _firestore
          .collection('Organizations')
          .doc(organizationId)
          .collection('JoinRequests')
          .doc(user.uid);

      await reqRef.set({
        'userId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
    } catch (e) {
      Logger.error('Failed to request join: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getJoinRequests(
    String organizationId,
  ) async {
    try {
      final query = await _firestore
          .collection('Organizations')
          .doc(organizationId)
          .collection('JoinRequests')
          .orderBy('createdAt', descending: true)
          .get();
      return query.docs.map((d) => d.data()).toList();
    } catch (e) {
      Logger.error('Failed to load join requests: $e');
      return [];
    }
  }

  Future<bool> approveJoinRequest(String organizationId, String userId) async {
    try {
      final memberRef = _firestore
          .collection('Organizations')
          .doc(organizationId)
          .collection('Members')
          .doc(userId);
      await memberRef.set({
        'organizationId': organizationId,
        'userId': userId,
        'role': 'Member',
        'permissions': <String>[],
        'status': 'approved',
        'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Remove join request
      await _firestore
          .collection('Organizations')
          .doc(organizationId)
          .collection('JoinRequests')
          .doc(userId)
          .delete();
      return true;
    } catch (e) {
      Logger.error('Failed to approve join request: $e');
      return false;
    }
  }

  Future<bool> declineJoinRequest(String organizationId, String userId) async {
    try {
      await _firestore
          .collection('Organizations')
          .doc(organizationId)
          .collection('JoinRequests')
          .doc(userId)
          .update({'status': 'declined'});
      return true;
    } catch (e) {
      Logger.error('Failed to decline join request: $e');
      return false;
    }
  }

  Future<bool> updateMemberPermissions(
    String organizationId,
    String userId, {
    required List<String> permissions,
    String? role,
  }) async {
    try {
      await _firestore
          .collection('Organizations')
          .doc(organizationId)
          .collection('Members')
          .doc(userId)
          .update({if (role != null) 'role': role, 'permissions': permissions});
      return true;
    } catch (e) {
      Logger.error('Failed to update member permissions: $e');
      return false;
    }
  }

  Future<bool> isMember(String organizationId, {String? userId}) async {
    final uid = userId ?? _auth.currentUser?.uid;
    if (uid == null) return false;
    try {
      final snap = await _firestore
          .collection('Organizations')
          .doc(organizationId)
          .collection('Members')
          .doc(uid)
          .get();
      return snap.exists && (snap.data()?['status'] == 'approved');
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermission(
    String organizationId,
    String permission, {
    String? userId,
  }) async {
    final uid = userId ?? _auth.currentUser?.uid;
    if (uid == null) return false;
    try {
      final snap = await _firestore
          .collection('Organizations')
          .doc(organizationId)
          .collection('Members')
          .doc(uid)
          .get();
      if (!snap.exists) return false;
      final data = snap.data()!;
      final List<dynamic>? perms = data['permissions'] as List<dynamic>?;
      return perms?.contains(permission) ?? false;
    } catch (_) {
      return false;
    }
  }
}
