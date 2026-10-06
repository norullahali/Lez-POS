// lib/core/database/daos/other_income_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/other_income_idempotency_table.dart';

part 'other_income_idempotency_dao.g.dart';

@DriftAccessor(tables: [OtherIncomeIdempotency])
class OtherIncomeIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$OtherIncomeIdempotencyDaoMixin {
  OtherIncomeIdempotencyDao(super.db);

  /// Read-only lookup by operation key. Must run inside caller's transaction.
  Future<OtherIncomeIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(otherIncomeIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  /// Inserts a completed idempotency record. Must run inside caller's transaction.
  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required String fingerprintHash,
    required int otherIncomeRecordId,
  }) =>
      into(otherIncomeIdempotency).insert(
        OtherIncomeIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          fingerprintHash: fingerprintHash,
          otherIncomeRecordId: otherIncomeRecordId,
        ),
      );
}