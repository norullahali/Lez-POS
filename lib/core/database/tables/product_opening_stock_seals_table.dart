// lib/core/database/tables/product_opening_stock_seals_table.dart

import 'package:drift/drift.dart';

/// Immutable per-product opening stock commit record (B20).
class ProductOpeningStockSeals extends Table {
  IntColumn get productId => integer()();
  RealColumn get quantity => real()();
  RealColumn get unitCost => real()();
  TextColumn get idempotencyKey => text()();
  IntColumn get createdBy => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {productId};
}
