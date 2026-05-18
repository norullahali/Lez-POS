import 'package:drift/drift.dart';
import 'products_table.dart';

class StockMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get movementType => text()();
  RealColumn get quantityChange => real()();
  RealColumn get stockBefore => real()();
  RealColumn get stockAfter => real()();
  IntColumn get referenceId => integer().nullable()();
  TextColumn get referenceType => text().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get createdByUserId =>
      integer().nullable().customConstraint('NULL REFERENCES users(id)')();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  List<Index> get indexes => [
        Index(
          'smov_product_idx',
          'CREATE INDEX IF NOT EXISTS smov_product_idx ON stock_movements (product_id)',
        ),
        Index(
          'smov_type_idx',
          'CREATE INDEX IF NOT EXISTS smov_type_idx ON stock_movements (movement_type)',
        ),
        Index(
          'smov_date_idx',
          'CREATE INDEX IF NOT EXISTS smov_date_idx ON stock_movements (created_at)',
        ),
        Index(
          'smov_ref_idx',
          'CREATE INDEX IF NOT EXISTS smov_ref_idx ON stock_movements (reference_id, reference_type)',
        ),
      ];
}