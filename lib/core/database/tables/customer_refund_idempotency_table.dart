// lib/core/database/tables/customer_refund_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency record for customer REFUND settlement (Phase C Step 3.0).
class CustomerRefundIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  IntColumn get customerId => integer()();
  RealColumn get amount => real()();
  IntColumn get returnId => integer().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get customerTransactionId => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'cri_customer_created_idx',
          'CREATE INDEX IF NOT EXISTS cri_customer_created_idx '
              'ON customer_refund_idempotency (customer_id, created_at)',
        ),
      ];
}
