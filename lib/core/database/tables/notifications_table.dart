import 'package:drift/drift.dart';
import 'users_table.dart';

@DataClassName('NotificationEntry')
class NotificationsTable extends Table {
  @override
  String get tableName => 'notifications';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(max: 100)();
  TextColumn get message => text()();
  TextColumn get actionType => text().nullable()();
  IntColumn get userId => integer().nullable().references(UsersTable, #id)();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
