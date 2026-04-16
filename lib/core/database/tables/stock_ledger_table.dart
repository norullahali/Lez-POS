// lib/core/database/tables/stock_ledger_table.dart
import 'package:drift/drift.dart';
import 'products_table.dart';

/// The central inventory ledger. Every stock change must go through this table.
/// Stock on hand = SUM(quantity_change) WHERE product_id = ?
class StockLedger extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get movementType => text()(); // StockMovementType.code
  IntColumn get referenceId => integer().nullable()(); // FK to the source record
  TextColumn get referenceType => text().withDefault(const Constant(''))(); // table name
  RealColumn get quantityChange => real()(); // positive=in, negative=out
  RealColumn get unitCost => real().withDefault(const Constant(0.0))();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  List<Index> get indexes => [
        Index('ledger_product_idx', 'CREATE INDEX IF NOT EXISTS ledger_product_idx ON stock_ledger (product_id)'),
        Index('ledger_type_idx', 'CREATE INDEX IF NOT EXISTS ledger_type_idx ON stock_ledger (movement_type)'),
        Index('ledger_date_idx', 'CREATE INDEX IF NOT EXISTS ledger_date_idx ON stock_ledger (created_at)'),
      ];
}
