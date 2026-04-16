import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/users_table.dart';
import '../tables/roles_table.dart';
import '../tables/permissions_table.dart';
import '../tables/role_permissions_table.dart';

part 'users_dao.g.dart';

@DriftAccessor(tables: [UsersTable, Roles, Permissions, RolePermissions])
class UsersDao extends DatabaseAccessor<AppDatabase> with _$UsersDaoMixin {
  UsersDao(super.db);

  // --- Authentication ---

  Future<User?> getUserByUsername(String username) =>
      (select(usersTable)..where((u) => u.username.equals(username))).getSingleOrNull();

  Future<User?> getUserById(int id) =>
      (select(usersTable)..where((u) => u.id.equals(id))).getSingleOrNull();

  Future<List<String>> getRolePermissionsKeys(int roleId) async {
    final query = select(permissions).join([
      innerJoin(rolePermissions, rolePermissions.permissionId.equalsExp(permissions.id))
    ])..where(rolePermissions.roleId.equals(roleId));

    final result = await query.get();
    return result.map((row) => row.readTable(permissions).permissionKey).toList();
  }

  Future<User?> getUserByPin(String pin) =>
      (select(usersTable)..where((u) => u.pinCode.equals(pin) & u.isActive.equals(true))).getSingleOrNull();

  // --- Users Management ---

  Stream<List<User>> watchAllUsers() {
    return (select(usersTable)..orderBy([(u) => OrderingTerm.asc(u.fullName)])).watch();
  }

  Future<List<User>> getAllUsers() => select(usersTable).get();

  Future<int> createUser(UsersTableCompanion user) => into(usersTable).insert(user);

  Future<bool> updateUser(User user) => update(usersTable).replace(user);

  // --- Roles and Permissions ---

  Future<List<Role>> getAllRoles() => select(roles).get();
  
  Future<Role?> getRoleById(int id) => (select(roles)..where((r) => r.id.equals(id))).getSingleOrNull();
  Future<int> createRole(RolesCompanion role) => into(roles).insert(role);
  Future<bool> updateRole(Role role) => update(roles).replace(role);

  Future<void> updateRolePermissions(int roleId, List<int> permissionIds) async {
    return transaction(() async {
      // Delete old mappings
      await (delete(rolePermissions)..where((rp) => rp.roleId.equals(roleId))).go();
      
      // Insert new ones
      for (final pid in permissionIds) {
        await into(rolePermissions).insert(
          RolePermissionsCompanion.insert(roleId: roleId, permissionId: pid),
        );
      }
    });
  }

  Future<List<Permission>> getAllPermissions() => select(permissions).get();
}
