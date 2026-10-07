// lib/core/database/daos/opening_stock_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/opening_stock_idempotency_table.dart';

part 'opening_stock_idempotency_dao.g.dart';

@DriftAccessor(tables: [OpeningStockIdempotency])
class OpeningStockIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$OpeningStockIdempotencyDaoMixin {
  OpeningStockIdempotencyDao(super.db);

  Future<OpeningStockIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(openingStockIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required String fingerprintHash,
  }) =>
      into(openingStockIdempotency).insert(
        OpeningStockIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          fingerprintHash: fingerprintHash,
        ),
      );
}
