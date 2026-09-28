import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/features/auth/permissions/permission_keys.dart';
import 'package:lez_pos/features/auth/permissions/route_permissions.dart';

void main() {
  group('Backup permission route alignment (B1)', () {
    test('backup route requires backup_database not settings.edit', () {
      expect(permissionForRoute('/backup'), PermissionKeys.backupDatabase);
      expect(permissionForRoute('/backup'), isNot(PermissionKeys.settingsEdit));
    });

    test('settings route still requires settings.edit', () {
      expect(permissionForRoute('/settings'), PermissionKeys.settingsEdit);
    });
  });
}
