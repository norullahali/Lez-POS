// lib/core/database/tables/pos_sale_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency record for POS checkout (B5-F1).
class PosSaleIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  IntColumn get sessionId => integer().nullable()();
  TextColumn get fingerprintHash => text()();
  IntColumn get salesInvoiceId => integer()();
  TextColumn get invoiceNumber => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'psi_sales_invoice_idx',
          'CREATE INDEX IF NOT EXISTS psi_sales_invoice_idx '
              'ON pos_sale_idempotency (sales_invoice_id)',
        ),
      ];
}
