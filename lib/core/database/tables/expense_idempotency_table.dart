// lib/core/database/tables/expense_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency record for expense creation (B18).
class ExpenseIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  TextColumn get fingerprintHash => text()();
  IntColumn get expenseRecordId => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'ei_expense_record_idx',
          'CREATE INDEX IF NOT EXISTS ei_expense_record_idx '
              'ON expense_idempotency (expense_record_id)',
        ),
      ];
}