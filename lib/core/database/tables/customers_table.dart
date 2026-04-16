import 'package:drift/drift.dart';

class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 2, max: 100)();
  TextColumn get phone => text().nullable().withLength(max: 20)();
  TextColumn get email => text().nullable().withLength(max: 100)();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  /// 0 means no limit. Positive = max credit amount allowed.
  RealColumn get creditLimit => real().withDefault(const Constant(0.0))();
  /// Accumulated loyalty / reward points balance.
  RealColumn get loyaltyPoints => real().withDefault(const Constant(0.0))();
}
