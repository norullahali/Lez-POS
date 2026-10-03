// lib/core/database/tables/customer_manual_return_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency record for manual customer return (B10).
class CustomerManualReturnIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  TextColumn get fingerprintHash => text()();
  IntColumn get productId => integer()();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  TextColumn get reason => text()();
  IntColumn get userId => integer().nullable()();
  IntColumn get approvedByUserId => integer().nullable()();
  IntColumn get customerReturnId => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'cmri_product_created_idx',
          'CREATE INDEX IF NOT EXISTS cmri_product_created_idx '
              'ON customer_manual_return_idempotency (product_id, created_at)',
        ),
      ];
}
