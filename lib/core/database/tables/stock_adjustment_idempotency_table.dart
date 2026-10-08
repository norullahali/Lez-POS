// lib/core/database/tables/stock_adjustment_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency record for stock adjustment save (B21).
class StockAdjustmentIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  TextColumn get fingerprintHash => text()();
  IntColumn get stockAdjustmentId => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'sai_stock_adjustment_idx',
          'CREATE INDEX IF NOT EXISTS sai_stock_adjustment_idx '
              'ON stock_adjustment_idempotency (stock_adjustment_id)',
        ),
      ];
}
