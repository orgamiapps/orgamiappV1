import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/models/organization_model.dart';
import 'package:attendus/models/organization_membership_model.dart';

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
      if (snap.docs.isEmpty) return <Map<String, String>>[];
      // Resolve organization IDs from the membership docs. Prefer the stored
      // field if present, but fall back to the parent path for legacy docs
      // that may not have `organizationId` saved.
      final Set<String> orgIds = <String>{};
      for (final d in snap.docs) {
        final String? fromField = d.data()['organizationId']?.toString();
        final String? fromPath = d.reference.parent.parent?.id;
        final String? resolved = (fromField != null && fromField.isNotEmpty)
            ? fromField
            : fromPath;
        if (resolved != null && resolved.isNotEmpty) {
          orgIds.add(resolved);
        }
      }
      orgIds.removeWhere((e) => e.isEmpty);
      if (orgIds.isEmpty) return <Map<String, String>>[];

      final futures = orgIds.map(
        (id) => _firestore.collection('Organizations').doc(id).get(),
      );
      final docs = await Future.wait(futures);
      final List<Map<String, String>> list = [];
      for (final doc in docs) {
        if (!doc.exists) continue;
        final data = doc.data()!;
        final String name = (data['name'] ?? data['title'] ?? '').toString();
        list.add({'id': doc.id, 'name': name});
      }
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
          .get()
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              Logger.warning('getUserOrganizationsLite timeout');
              throw Exception('Query timeout');
            },
          );

      // Collect all org IDs first
      final Set<String> orgIds = {};
      for (final doc in query.docs) {
        final String? orgId =
            (doc.data()['organizationId'] as String?) ??
            doc.reference.parent.parent?.id;
        if (orgId != null && orgId.isNotEmpty) {
          orgIds.add(orgId);
        }
      }

      if (orgIds.isEmpty) return [];

      // Fetch all organizations in parallel
      final futures = orgIds.map((id) => 
        _firestore
          .collection('Organizations')
          .doc(id)
          .get()
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              Logger.warning('Organization fetch timeout for $id');
              throw Exception('Fetch timeout');
            },
          )
      ).toList();

      // Wait for all with error handling
      final List<Map<String, String>> result = [];
      try {
        final orgDocs = await Future.wait(
          futures,
          eagerError: false, // Don't fail all if one fails
        );
        
        for (final orgSnap in orgDocs) {
          if (orgSnap.exists) {
            final name = orgSnap.data()!['name']?.toString() ?? '';
            result.add({'id': orgSnap.id, 'name': name});
          }
        }
      } catch (e) {
        Logger.error('Error fetching organizations in parallel: $e');
        // Still return what we could fetch
      }

      // Sort by name
      result.sort((a, b) => 
        (a['name'] ?? '').toLowerCase().compareTo(
          (b['name'] ?? '').toLowerCase()
        )
      );
      
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
