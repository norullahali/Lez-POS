// lib/core/database/tables/other_income_mutation_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency for other income UPDATE and VOID (B23). B19 CREATE unchanged.
class OtherIncomeMutationIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  TextColumn get operationType => text()();
  TextColumn get fingerprintHash => text()();
  IntColumn get otherIncomeRecordId => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'oimi_other_income_record_idx',
          'CREATE INDEX IF NOT EXISTS oimi_other_income_record_idx '
              'ON other_income_mutation_idempotency (other_income_record_id)',
        ),
      ];
}
