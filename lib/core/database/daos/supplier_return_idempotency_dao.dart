// lib/core/database/daos/supplier_return_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/supplier_return_idempotency_table.dart';

part 'supplier_return_idempotency_dao.g.dart';

@DriftAccessor(tables: [SupplierReturnIdempotency])
class SupplierReturnIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$SupplierReturnIdempotencyDaoMixin {
  SupplierReturnIdempotencyDao(super.db);

  /// Read-only lookup by operation key. Must run inside caller's transaction.
  Future<SupplierReturnIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(supplierReturnIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  /// Inserts a completed idempotency record. Must run inside caller's transaction.
  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required String fingerprintHash,
    required int supplierId,
    required int purchaseInvoiceId,
    required int supplierReturnId,
    int? supplierTransactionId,
  }) =>
      into(supplierReturnIdempotency).insert(
        SupplierReturnIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          fingerprintHash: fingerprintHash,
          supplierId: supplierId,
          purchaseInvoiceId: purchaseInvoiceId,
          supplierReturnId: supplierReturnId,
          supplierTransactionId: Value(supplierTransactionId),
        ),
      );
}
