// lib/core/database/daos/customer_quick_return_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/customer_quick_return_idempotency_table.dart';

part 'customer_quick_return_idempotency_dao.g.dart';

@DriftAccessor(tables: [CustomerQuickReturnIdempotency])
class CustomerQuickReturnIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$CustomerQuickReturnIdempotencyDaoMixin {
  CustomerQuickReturnIdempotencyDao(super.db);

  /// Read-only lookup by operation key. Must run inside caller's transaction.
  Future<CustomerQuickReturnIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(customerQuickReturnIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  /// Inserts a completed idempotency record. Must run inside caller's transaction.
  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required String fingerprintHash,
    required int productId,
    required double quantity,
    required double refundAmount,
    required int userId,
    int? approvedByUserId,
    required int customerReturnId,
  }) =>
      into(customerQuickReturnIdempotency).insert(
        CustomerQuickReturnIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          fingerprintHash: fingerprintHash,
          productId: productId,
          quantity: quantity,
          refundAmount: refundAmount,
          userId: userId,
          approvedByUserId: Value(approvedByUserId),
          customerReturnId: customerReturnId,
        ),
      );
}
