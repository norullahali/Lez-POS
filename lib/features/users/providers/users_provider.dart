import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';

final usersListProvider = StreamProvider<List<User>>((ref) {
  debugPrint('[usersListProvider] subscribing to watchAllUsers stream...');
  return AppDatabase.instance.usersDao.watchAllUsers();
});

final rolesProvider = FutureProvider<List<Role>>((ref) async {
  try {
    debugPrint('[rolesProvider] loading roles...');
    final result = await AppDatabase.instance.usersDao.getAllRoles();
    debugPrint('[rolesProvider] loaded ${result.length} roles.');
    return result;
  } catch (e, st) {
    debugPrint('[rolesProvider] error: $e\n$st');
    rethrow;
  }
});

final permissionsProvider = FutureProvider<List<Permission>>((ref) async {
  return AppDatabase.instance.usersDao.getAllPermissions();
});

final rolePermissionsProvider = FutureProvider.family<List<String>, int>((ref, roleId) {
  return AppDatabase.instance.usersDao.getRolePermissionsKeys(roleId);
});

final usersProvider = Provider<UsersNotifier>((ref) => UsersNotifier());

class UsersNotifier {
  final AppDatabase _db = AppDatabase.instance;

  Future<void> createUser(UsersTableCompanion user) async {
    try {
      debugPrint('[UsersNotifier] createUser: ${user.username.value}');
      await _db.usersDao.createUser(user);
    } catch (e, st) {
      debugPrint('[UsersNotifier] createUser error: $e\n$st');
      rethrow;
    }
  }

  Future<void> updateUser(User user) async {
    try {
      debugPrint('[UsersNotifier] updateUser: ${user.username}');
      await _db.usersDao.updateUser(user);
    } catch (e, st) {
      debugPrint('[UsersNotifier] updateUser error: $e\n$st');
      rethrow;
    }
  }

  Future<void> saveRole(RolesCompanion role, List<int> permissionIds) async {
    try {
      int roleId;
      if (role.id.present) {
        roleId = role.id.value;
        await _db.usersDao.updateRole(Role(
          id: role.id.value,
          roleName: role.roleName.value,
          description: role.description.value,
          isSystem: role.isSystem.value,
        ));
      } else {
        roleId = await _db.usersDao.createRole(role);
      }
      await _db.usersDao.updateRolePermissions(roleId, permissionIds);
    } catch (e, st) {
      debugPrint('[UsersNotifier] saveRole error: $e\n$st');
      rethrow;
    }
  }
}
