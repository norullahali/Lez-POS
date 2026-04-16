import 'package:drift/drift.dart';

@DataClassName('Role')
class Roles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get roleName => text().withLength(min: 2, max: 50).unique()();
  TextColumn get description => text().nullable()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
}
