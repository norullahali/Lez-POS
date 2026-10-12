// lib/core/database/tables/expense_mutation_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency for expense UPDATE and VOID (B22). B18 CREATE unchanged.
class ExpenseMutationIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  TextColumn get operationType => text()();
  TextColumn get fingerprintHash => text()();
  IntColumn get expenseRecordId => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'emi_expense_record_idx',
          'CREATE INDEX IF NOT EXISTS emi_expense_record_idx '
              'ON expense_mutation_idempotency (expense_record_id)',
        ),
      ];
}
