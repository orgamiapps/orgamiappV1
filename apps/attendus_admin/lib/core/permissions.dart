enum AdminRole { superAdmin, support, billingAdmin, analyst, moderator }

extension AdminRoleWire on AdminRole {
  String get wire => switch (this) {
    AdminRole.superAdmin => 'super_admin',
    AdminRole.support => 'support',
    AdminRole.billingAdmin => 'billing_admin',
    AdminRole.analyst => 'analyst',
    AdminRole.moderator => 'moderator',
  };
}

class AdminPermissions {
  const AdminPermissions(this.roles);
  final Set<AdminRole> roles;
  bool get isSuperAdmin => roles.contains(AdminRole.superAdmin);
  bool get accountsRead =>
      isSuperAdmin ||
      roles.any(
        {AdminRole.support, AdminRole.billingAdmin, AdminRole.analyst}.contains,
      );
  bool get accountsMutate => isSuperAdmin || roles.contains(AdminRole.support);
  bool get subscriptionsRead =>
      isSuperAdmin ||
      roles.any({AdminRole.billingAdmin, AdminRole.analyst}.contains);
  bool get subscriptionsMutate =>
      isSuperAdmin || roles.contains(AdminRole.billingAdmin);
  bool get analyticsRead => isSuperAdmin || roles.contains(AdminRole.analyst);
  bool get moderation => isSuperAdmin || roles.contains(AdminRole.moderator);
  bool get roleManagement => isSuperAdmin;
  static AdminPermissions fromWire(Iterable<dynamic> values) =>
      AdminPermissions(
        AdminRole.values.where((role) => values.contains(role.wire)).toSet(),
      );
}
