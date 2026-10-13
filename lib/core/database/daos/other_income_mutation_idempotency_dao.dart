// lib/core/database/daos/other_income_mutation_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/other_income_mutation_idempotency_table.dart';

part 'other_income_mutation_idempotency_dao.g.dart';

@DriftAccessor(tables: [OtherIncomeMutationIdempotency])
class OtherIncomeMutationIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$OtherIncomeMutationIdempotencyDaoMixin {
  OtherIncomeMutationIdempotencyDao(super.db);

  Future<OtherIncomeMutationIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(otherIncomeMutationIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required String operationType,
    required String fingerprintHash,
    required int otherIncomeRecordId,
  }) =>
      into(otherIncomeMutationIdempotency).insert(
        OtherIncomeMutationIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          operationType: operationType,
          fingerprintHash: fingerprintHash,
          otherIncomeRecordId: otherIncomeRecordId,
        ),
      );
}
