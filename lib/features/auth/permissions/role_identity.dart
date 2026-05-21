// lib/features/auth/permissions/role_identity.dart
import 'package:flutter/foundation.dart';
import '../../../core/database/daos/users_dao.dart';
import 'system_roles.dart';

/// Resolves and caches the owner system role from the database.
/// Uses stable [SystemRoles.ownerKey], not localized role names.
class RoleIdentity {
  RoleIdentity._();

  static int? _ownerRoleId;

  static int? get ownerRoleId => _ownerRoleId;
  static bool get isInitialized => _ownerRoleId != null;

  static Future<void> initialize(UsersDao usersDao) async {
    final owner = await usersDao.getSystemOwnerRole();
    _ownerRoleId = owner?.id;
    if (_ownerRoleId == null) {
      debugPrint(
        '[RoleIdentity] Owner role (system_key="${SystemRoles.ownerKey}") not found; '
        'owner bypass disabled until role exists.',
      );
    } else {
      debugPrint(
        '[RoleIdentity] Owner role resolved (id=$_ownerRoleId, key=${SystemRoles.ownerKey}).',
      );
    }
  }

  static bool isOwnerRole(int? roleId) {
    if (roleId == null || _ownerRoleId == null) return false;
    return roleId == _ownerRoleId;
  }

  /// Alias for owner bypass (full permission grant).
  static bool isSuperAdmin(int? roleId) => isOwnerRole(roleId);
}