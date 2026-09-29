// lib/core/database/tables/customer_payment_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency record for customer PAYMENT (B6).
class CustomerPaymentIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  IntColumn get customerId => integer()();
  RealColumn get amount => real()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get customerTransactionId => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'cpi_customer_created_idx',
          'CREATE INDEX IF NOT EXISTS cpi_customer_created_idx '
              'ON customer_payment_idempotency (customer_id, created_at)',
        ),
      ];
}