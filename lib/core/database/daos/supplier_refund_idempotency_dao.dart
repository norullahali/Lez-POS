// lib/core/database/daos/supplier_refund_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/supplier_refund_idempotency_table.dart';

part 'supplier_refund_idempotency_dao.g.dart';

@DriftAccessor(tables: [SupplierRefundIdempotency])
class SupplierRefundIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$SupplierRefundIdempotencyDaoMixin {
  SupplierRefundIdempotencyDao(super.db);

  /// Read-only lookup by operation key. Must run inside caller's transaction.
  Future<SupplierRefundIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(supplierRefundIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  /// Inserts a completed idempotency record. Must run inside caller's transaction.
  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required int supplierId,
    required double amount,
    int? returnId,
    required String note,
    required int supplierTransactionId,
  }) =>
      into(supplierRefundIdempotency).insert(
        SupplierRefundIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          supplierId: supplierId,
          amount: amount,
          returnId: Value(returnId),
          note: Value(note),
          supplierTransactionId: supplierTransactionId,
        ),
      );
}
