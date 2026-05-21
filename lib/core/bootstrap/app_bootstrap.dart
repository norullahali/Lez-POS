// lib/core/bootstrap/app_bootstrap.dart
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import '../../features/auth/permissions/role_identity.dart';
import '../../features/auth/services/permission_sync_service.dart';
import '../../features/auth/services/system_role_sync_service.dart';

/// Runs non-UI startup tasks before the widget tree is built.
class AppBootstrap {
  AppBootstrap._();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      final db = AppDatabase.instance;
      await SystemRoleSyncService(db).syncSystemRoleKeys();
      await RoleIdentity.initialize(db.usersDao);
      await PermissionSyncService(db).syncPermissions();
      _initialized = true;
      debugPrint('[AppBootstrap] Startup sync completed.');
    } catch (e, st) {
      debugPrint('[AppBootstrap] Startup sync failed: $e\n$st');
      rethrow;
    }
  }
}