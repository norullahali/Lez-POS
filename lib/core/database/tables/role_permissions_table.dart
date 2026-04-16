import 'package:drift/drift.dart';

@DataClassName('RolePermission')
class RolePermissions extends Table {
  IntColumn get roleId => integer().customConstraint('NOT NULL REFERENCES roles(id)')();
  IntColumn get permissionId => integer().customConstraint('NOT NULL REFERENCES permissions(id)')();

  @override
  Set<Column> get primaryKey => {roleId, permissionId};
}
