import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:orgami/Utils/logger.dart';
import 'package:orgami/models/organization_model.dart';
import 'package:orgami/models/organization_membership_model.dart';

class OrganizationHelper {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

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

      final List<Map<String, String>> result = [];
      for (final doc in query.docs) {
        try {
          final orgId = doc.data()['organizationId'] as String?;
          if (orgId == null) continue;
          final orgSnap = await _firestore
              .collection('Organizations')
              .doc(orgId)
              .get();
          if (orgSnap.exists) {
            final name = orgSnap.data()!['name']?.toString() ?? '';
            result.add({'id': orgId, 'name': name});
          }
        } catch (e) {
          Logger.error('Error resolving organization from membership: $e');
        }
      }
      return result;
    } catch (e) {
      Logger.error('getUserOrganizationsLite failed: $e');
      return [];
    }
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
