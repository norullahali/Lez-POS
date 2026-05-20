// lib/features/auth/services/permission_service.dart
import '../../../core/database/app_database.dart';
import '../permissions/permission_rules.dart';
import '../providers/auth_provider.dart';

class PermissionService {
  final User? user;
  final List<String> permissions;

  PermissionService({this.user, this.permissions = const []});

  factory PermissionService.fromAuthState(AuthState? state) {
    return PermissionService(
      user: state?.user,
      permissions: state?.permissions ?? const [],
    );
  }

  int? get roleId => user?.roleId;
  bool get isAuthenticated => user != null;
  bool get isSuperAdmin => PermissionRules.isSuperAdmin(roleId);

  Future<bool> hasPermission(String key) async => hasPermissionSync(key);

  bool hasPermissionSync(String key) => PermissionRules.hasPermission(
        roleId: roleId,
        permissions: permissions,
        key: key,
      );

  bool hasAny(List<String> keys) => PermissionRules.hasAny(
        roleId: roleId,
        permissions: permissions,
        keys: keys,
      );

  bool hasAll(List<String> keys) => PermissionRules.hasAll(
        roleId: roleId,
        permissions: permissions,
        keys: keys,
      );
}