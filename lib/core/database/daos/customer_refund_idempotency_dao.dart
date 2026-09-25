// lib/core/database/daos/customer_refund_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/customer_refund_idempotency_table.dart';

part 'customer_refund_idempotency_dao.g.dart';

@DriftAccessor(tables: [CustomerRefundIdempotency])
class CustomerRefundIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$CustomerRefundIdempotencyDaoMixin {
  CustomerRefundIdempotencyDao(super.db);

  /// Read-only lookup by operation key. Must run inside caller's transaction.
  Future<CustomerRefundIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(customerRefundIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  /// Inserts a completed idempotency record. Must run inside caller's transaction.
  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required int customerId,
    required double amount,
    int? returnId,
    required String note,
    required int customerTransactionId,
  }) =>
      into(customerRefundIdempotency).insert(
        CustomerRefundIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          customerId: customerId,
          amount: amount,
          returnId: Value(returnId),
          note: Value(note),
          customerTransactionId: customerTransactionId,
        ),
      );
}
