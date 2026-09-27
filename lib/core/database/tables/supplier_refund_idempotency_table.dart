// lib/core/database/tables/supplier_refund_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency record for supplier REFUND settlement (SR Step 2.1).
class SupplierRefundIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  IntColumn get supplierId => integer()();
  RealColumn get amount => real()();
  IntColumn get returnId => integer().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get supplierTransactionId => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'sri_supplier_created_idx',
          'CREATE INDEX IF NOT EXISTS sri_supplier_created_idx '
              'ON supplier_refund_idempotency (supplier_id, created_at)',
        ),
      ];
}
