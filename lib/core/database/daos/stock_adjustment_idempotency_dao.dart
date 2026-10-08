// lib/core/database/daos/stock_adjustment_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/stock_adjustment_idempotency_table.dart';

part 'stock_adjustment_idempotency_dao.g.dart';

@DriftAccessor(tables: [StockAdjustmentIdempotency])
class StockAdjustmentIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$StockAdjustmentIdempotencyDaoMixin {
  StockAdjustmentIdempotencyDao(super.db);

  Future<StockAdjustmentIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(stockAdjustmentIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required String fingerprintHash,
    required int stockAdjustmentId,
  }) =>
      into(stockAdjustmentIdempotency).insert(
        StockAdjustmentIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          fingerprintHash: fingerprintHash,
          stockAdjustmentId: stockAdjustmentId,
        ),
      );
}
