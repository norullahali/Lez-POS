import 'package:drift/drift.dart';

@DataClassName('Permission')
class Permissions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get permissionKey => text().withLength(min: 2, max: 50).unique()();
  TextColumn get description => text()();
}
