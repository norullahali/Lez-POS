// lib/core/database/tables/supplier_return_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency record for purchase-linked supplier returns (B15).
class SupplierReturnIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  TextColumn get fingerprintHash => text()();
  IntColumn get supplierId => integer()();
  IntColumn get purchaseInvoiceId => integer()();
  IntColumn get supplierReturnId => integer()();
  IntColumn get supplierTransactionId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'sri_supplier_created_idx',
          'CREATE INDEX IF NOT EXISTS sri_supplier_created_idx '
              'ON supplier_return_idempotency (supplier_id, created_at)',
        ),
      ];
}
