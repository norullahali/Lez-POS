// lib/core/database/daos/expense_mutation_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/expense_mutation_idempotency_table.dart';

part 'expense_mutation_idempotency_dao.g.dart';

@DriftAccessor(tables: [ExpenseMutationIdempotency])
class ExpenseMutationIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$ExpenseMutationIdempotencyDaoMixin {
  ExpenseMutationIdempotencyDao(super.db);

  Future<ExpenseMutationIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(expenseMutationIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required String operationType,
    required String fingerprintHash,
    required int expenseRecordId,
  }) =>
      into(expenseMutationIdempotency).insert(
        ExpenseMutationIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          operationType: operationType,
          fingerprintHash: fingerprintHash,
          expenseRecordId: expenseRecordId,
        ),
      );
}
