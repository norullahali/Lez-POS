// lib/core/database/tables/supplier_payment_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency record for supplier PAYMENT (B8).
class SupplierPaymentIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  TextColumn get fingerprintHash => text()();
  IntColumn get supplierId => integer()();
  RealColumn get amount => real()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get supplierTransactionId => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};
}
