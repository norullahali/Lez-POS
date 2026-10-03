// lib/core/database/daos/customer_manual_return_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/customer_manual_return_idempotency_table.dart';

part 'customer_manual_return_idempotency_dao.g.dart';

@DriftAccessor(tables: [CustomerManualReturnIdempotency])
class CustomerManualReturnIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$CustomerManualReturnIdempotencyDaoMixin {
  CustomerManualReturnIdempotencyDao(super.db);

  /// Read-only lookup by operation key. Must run inside caller's transaction.
  Future<CustomerManualReturnIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(customerManualReturnIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  /// Inserts a completed idempotency record. Must run inside caller's transaction.
  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required String fingerprintHash,
    required int productId,
    required double quantity,
    required double unitPrice,
    required String reason,
    int? userId,
    int? approvedByUserId,
    required int customerReturnId,
  }) =>
      into(customerManualReturnIdempotency).insert(
        CustomerManualReturnIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          fingerprintHash: fingerprintHash,
          productId: productId,
          quantity: quantity,
          unitPrice: unitPrice,
          reason: reason,
          userId: Value(userId),
          approvedByUserId: Value(approvedByUserId),
          customerReturnId: customerReturnId,
        ),
      );
}
