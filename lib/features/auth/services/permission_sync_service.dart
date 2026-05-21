// lib/features/auth/services/permission_sync_service.dart
import 'package:flutter/foundation.dart';
import '../../../core/database/app_database.dart';
import '../permissions/permission_keys.dart';
import '../permissions/role_identity.dart';

/// Synchronizes [PermissionKeys] registry with the database permissions table.
class PermissionSyncService {
  PermissionSyncService(this._db);

  final AppDatabase _db;

  /// Inserts missing permissions and grants them to the owner role only.
  /// Safe to run on every startup; never deletes or overwrites assignments.
  Future<void> syncPermissions() async {
    final dao = _db.usersDao;
    final existing = await dao.getAllPermissions();
    final existingKeys = existing.map((p) => p.permissionKey).toSet();

    final added = <String>[];

    for (final key in PermissionKeys.all) {
      if (existingKeys.contains(key)) continue;

      final id = await dao.insertPermission(
        permissionKey: key,
        description: PermissionKeys.descriptionFor(key),
      );
      existingKeys.add(key);
      added.add(key);

      final ownerRoleId = RoleIdentity.ownerRoleId;
      if (ownerRoleId != null) {
        await dao.grantPermissionToRole(ownerRoleId, id);
      }
    }

    if (added.isEmpty) {
      debugPrint('[PermissionSync] All permissions up to date.');
    } else {
      debugPrint('[PermissionSync] Added ${added.length} permission(s): $added');
    }
  }
}