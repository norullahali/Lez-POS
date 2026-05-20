// lib/features/auth/permissions/permission_rules.dart
class PermissionRules {
  PermissionRules._();
  static const int ownerRoleId = 1;
  static bool isSuperAdmin(int? roleId) => roleId == ownerRoleId;
  static bool hasPermission({required int? roleId, required List<String> permissions, required String key}) {
    if (isSuperAdmin(roleId)) return true;
    return permissions.contains(key);
  }
  static bool hasAny({required int? roleId, required List<String> permissions, required List<String> keys}) =>
      keys.any((key) => hasPermission(roleId: roleId, permissions: permissions, key: key));
  static bool hasAll({required int? roleId, required List<String> permissions, required List<String> keys}) =>
      keys.every((key) => hasPermission(roleId: roleId, permissions: permissions, key: key));
}