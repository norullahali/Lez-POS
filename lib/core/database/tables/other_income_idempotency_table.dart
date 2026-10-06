// lib/core/database/tables/other_income_idempotency_table.dart

import 'package:drift/drift.dart';

/// Persistent idempotency record for other income creation (B19).
class OtherIncomeIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  TextColumn get fingerprintHash => text()();
  IntColumn get otherIncomeRecordId => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'oii_other_income_record_idx',
          'CREATE INDEX IF NOT EXISTS oii_other_income_record_idx '
              'ON other_income_idempotency (other_income_record_id)',
        ),
      ];
}