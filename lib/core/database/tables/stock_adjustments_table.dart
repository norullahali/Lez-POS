// lib/core/database/tables/stock_adjustments_table.dart
import 'package:drift/drift.dart';
import 'products_table.dart';

class StockAdjustments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get adjustmentType => text()(); // DAMAGE, LOSS, CORRECTION
  RealColumn get quantityChange => real()(); // positive or negative
  TextColumn get reason => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get createdByUserId => integer().nullable().customConstraint('NULL REFERENCES users(id)')();
}
