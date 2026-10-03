// lib/core/database/daos/supplier_payment_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/supplier_payment_idempotency_table.dart';

part 'supplier_payment_idempotency_dao.g.dart';

@DriftAccessor(tables: [SupplierPaymentIdempotency])
class SupplierPaymentIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$SupplierPaymentIdempotencyDaoMixin {
  SupplierPaymentIdempotencyDao(super.db);

  /// Read-only lookup by operation key. Must run inside caller's transaction.
  Future<SupplierPaymentIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(supplierPaymentIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  /// Inserts a completed idempotency record. Must run inside caller's transaction.
  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required String fingerprintHash,
    required int supplierId,
    required double amount,
    required String note,
    required int supplierTransactionId,
  }) =>
      into(supplierPaymentIdempotency).insert(
        SupplierPaymentIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          fingerprintHash: fingerprintHash,
          supplierId: supplierId,
          amount: amount,
          note: Value(note),
          supplierTransactionId: supplierTransactionId,
        ),
      );
}
