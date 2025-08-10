import 'package:cloud_firestore/cloud_firestore.dart';

class OrganizationMembership {
  final String organizationId;
  final String userId;
  final String role; // e.g., Admin, Member, custom roles
  final List<String> permissions; // CreateEditEvents, ApproveJoinRequests, ManageMembersRoles, ViewAnalytics
  final String status; // pending, approved, declined
  final DateTime joinedAt;

  OrganizationMembership({
    required this.organizationId,
    required this.userId,
    required this.role,
    required this.permissions,
    required this.status,
    required this.joinedAt,
  });

  factory OrganizationMembership.fromJson(Map<String, dynamic> data) {
    return OrganizationMembership(
      organizationId: data['organizationId'],
      userId: data['userId'],
      role: data['role'] ?? 'Member',
      permissions: (data['permissions'] as List<dynamic>? ?? []).cast<String>(),
      status: data['status'] ?? 'approved',
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'organizationId': organizationId,
      'userId': userId,
      'role': role,
      'permissions': permissions,
      'status': status,
      'joinedAt': joinedAt,
    };
  }
}