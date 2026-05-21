// lib/features/auth/services/system_role_sync_service.dart
import 'package:flutter/foundation.dart';
import '../../../core/database/app_database.dart';
import '../permissions/system_roles.dart';

/// Ensures built-in system roles have stable [system_key] values in the database.
class SystemRoleSyncService {
  SystemRoleSyncService(this._db);

  final AppDatabase _db;

  /// Idempotent: assigns owner system_key to the legacy owner role if missing.
  Future<void> syncSystemRoleKeys() async {
    final assigned = await _db.usersDao.ensureOwnerSystemKey();
    if (assigned) {
      debugPrint(
        '[SystemRoleSync] Assigned system_key "${SystemRoles.ownerKey}" to owner role.',
      );
    } else {
      debugPrint('[SystemRoleSync] Owner system_key already configured.');
    }
  }
}