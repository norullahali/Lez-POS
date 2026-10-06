// lib/core/database/daos/expense_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/expense_idempotency_table.dart';

part 'expense_idempotency_dao.g.dart';

@DriftAccessor(tables: [ExpenseIdempotency])
class ExpenseIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$ExpenseIdempotencyDaoMixin {
  ExpenseIdempotencyDao(super.db);

  /// Read-only lookup by operation key. Must run inside caller's transaction.
  Future<ExpenseIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(expenseIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  /// Inserts a completed idempotency record. Must run inside caller's transaction.
  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required String fingerprintHash,
    required int expenseRecordId,
  }) =>
      into(expenseIdempotency).insert(
        ExpenseIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          fingerprintHash: fingerprintHash,
          expenseRecordId: expenseRecordId,
        ),
      );
}