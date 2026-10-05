// lib/core/database/tables/customer_invoice_return_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency record for invoice-linked customer returns (B16).
class CustomerInvoiceReturnIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  TextColumn get fingerprintHash => text()();
  IntColumn get customerId => integer().nullable()();
  IntColumn get saleInvoiceId => integer()();
  TextColumn get returnType => text()();
  IntColumn get customerReturnId => integer().nullable()();
  IntColumn get primaryReferenceId => integer().nullable()();
  TextColumn get executionPath => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'cir_customer_created_idx',
          'CREATE INDEX IF NOT EXISTS cir_customer_created_idx '
              'ON customer_invoice_return_idempotency (customer_id, created_at)',
        ),
        Index(
          'cir_invoice_idx',
          'CREATE INDEX IF NOT EXISTS cir_invoice_idx '
              'ON customer_invoice_return_idempotency (sale_invoice_id, created_at)',
        ),
      ];
}