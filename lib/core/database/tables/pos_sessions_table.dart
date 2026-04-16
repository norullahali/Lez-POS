// lib/core/database/tables/pos_sessions_table.dart
import 'package:drift/drift.dart';

class PosSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get cashierName => text().withDefault(const Constant('كاشير'))();
  DateTimeColumn get openedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get closedAt => dateTime().nullable()();
  IntColumn get createdByUserId => integer().nullable().customConstraint('NULL REFERENCES users(id)')();
  RealColumn get openingCash => real().withDefault(const Constant(0.0))();
  RealColumn get closingCash => real().nullable()();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();
}
