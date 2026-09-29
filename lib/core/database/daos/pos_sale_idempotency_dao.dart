// lib/core/database/daos/pos_sale_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/pos_sale_idempotency_table.dart';

part 'pos_sale_idempotency_dao.g.dart';

@DriftAccessor(tables: [PosSaleIdempotency])
class PosSaleIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$PosSaleIdempotencyDaoMixin {
  PosSaleIdempotencyDao(super.db);

  /// Read-only lookup by operation key. Must run inside caller's transaction.
  Future<PosSaleIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(posSaleIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  /// Inserts a completed idempotency record. Must run inside caller's transaction.
  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    int? sessionId,
    required String fingerprintHash,
    required int salesInvoiceId,
    required String invoiceNumber,
  }) =>
      into(posSaleIdempotency).insert(
        PosSaleIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          sessionId: Value(sessionId),
          fingerprintHash: fingerprintHash,
          salesInvoiceId: salesInvoiceId,
          invoiceNumber: invoiceNumber,
        ),
      );
}
