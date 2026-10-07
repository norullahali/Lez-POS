// lib/core/database/tables/opening_stock_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency record for bulk opening stock save (B20).
class OpeningStockIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  TextColumn get fingerprintHash => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};
}
