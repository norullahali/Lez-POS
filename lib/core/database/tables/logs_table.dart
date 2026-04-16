// lib/core/database/tables/logs_table.dart
import 'package:drift/drift.dart';
import 'users_table.dart';

@DataClassName('LogEntry')
class LogsTable extends Table {
  @override
  String get tableName => 'logs';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().nullable().references(UsersTable, #id)();
  TextColumn get actionType => text().withLength(max: 100)();
  RealColumn get amount => real().nullable()();
  IntColumn get approvedByUserId => integer().nullable().references(UsersTable, #id)();
  TextColumn get details => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}
