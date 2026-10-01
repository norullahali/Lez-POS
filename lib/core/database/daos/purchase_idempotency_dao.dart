// lib/core/database/daos/purchase_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/purchase_idempotency_table.dart';

part 'purchase_idempotency_dao.g.dart';

@DriftAccessor(tables: [PurchaseIdempotency])
class PurchaseIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$PurchaseIdempotencyDaoMixin {
  PurchaseIdempotencyDao(super.db);

  /// Read-only lookup by operation key. Must run inside caller's transaction.
  Future<PurchaseIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(purchaseIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  /// Inserts a completed idempotency record. Must run inside caller's transaction.
  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    int? supplierId,
    required String fingerprintHash,
    required int purchaseInvoiceId,
    required String invoiceNumber,
  }) =>
      into(purchaseIdempotency).insert(
        PurchaseIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          supplierId: Value(supplierId),
          fingerprintHash: fingerprintHash,
          purchaseInvoiceId: purchaseInvoiceId,
          invoiceNumber: invoiceNumber,
        ),
      );
}
