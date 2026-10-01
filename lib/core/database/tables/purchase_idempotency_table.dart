// lib/core/database/tables/purchase_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency record for purchase save (B7).
class PurchaseIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  IntColumn get supplierId => integer().nullable()();
  TextColumn get fingerprintHash => text()();
  IntColumn get purchaseInvoiceId => integer()();
  TextColumn get invoiceNumber => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'pi_purchase_invoice_idx',
          'CREATE INDEX IF NOT EXISTS pi_purchase_invoice_idx '
              'ON purchase_idempotency (purchase_invoice_id)',
        ),
      ];
}
