// lib/features/auth/permissions/permission_rules.dart
import 'role_identity.dart';

/// Pure permission evaluation rules (no I/O).
class PermissionRules {
  PermissionRules._();

  static bool isOwnerRole(int? roleId) => RoleIdentity.isOwnerRole(roleId);

  static bool isSuperAdmin(int? roleId) => RoleIdentity.isSuperAdmin(roleId);

  static bool hasPermission({
    required int? roleId,
    required List<String> permissions,
    required String key,
  }) {
    if (isSuperAdmin(roleId)) return true;
    return permissions.contains(key);
  }

  static bool hasAny({
    required int? roleId,
    required List<String> permissions,
    required List<String> keys,
  }) =>
      keys.any((key) => hasPermission(roleId: roleId, permissions: permissions, key: key));

  static bool hasAll({
    required int? roleId,
    required List<String> permissions,
    required List<String> keys,
  }) =>
      keys.every((key) => hasPermission(roleId: roleId, permissions: permissions, key: key));
}