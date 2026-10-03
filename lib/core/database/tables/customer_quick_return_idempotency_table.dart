// lib/core/database/tables/customer_quick_return_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency record for customer quick return without invoice (B9).
class CustomerQuickReturnIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  TextColumn get fingerprintHash => text()();
  IntColumn get productId => integer()();
  RealColumn get quantity => real()();
  RealColumn get refundAmount => real()();
  IntColumn get userId => integer()();
  IntColumn get approvedByUserId => integer().nullable()();
  IntColumn get customerReturnId => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'cqri_product_created_idx',
          'CREATE INDEX IF NOT EXISTS cqri_product_created_idx '
              'ON customer_quick_return_idempotency (product_id, created_at)',
        ),
      ];
}
