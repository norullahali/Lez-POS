import 'package:drift/drift.dart';

@DataClassName('User')
class UsersTable extends Table {
  @override
  String get tableName => 'users';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get fullName => text().withLength(min: 2, max: 100)();
  TextColumn get username => text().withLength(min: 3, max: 50).unique()();
  TextColumn get passwordHash => text()();
  IntColumn get roleId => integer().customConstraint('NOT NULL REFERENCES roles(id)')();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  RealColumn get refundLimit => real().withDefault(const Constant(0.0))();
  TextColumn get pinCode => text().nullable().withLength(min: 4, max: 8)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get createdByUserId => integer().nullable().customConstraint('NULL REFERENCES users(id)')();
}
