// lib/core/database/daos/pos_session_open_idempotency_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/pos_session_open_idempotency_table.dart';

part 'pos_session_open_idempotency_dao.g.dart';

@DriftAccessor(tables: [PosSessionOpenIdempotency])
class PosSessionOpenIdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$PosSessionOpenIdempotencyDaoMixin {
  PosSessionOpenIdempotencyDao(super.db);

  Future<PosSessionOpenIdempotencyData?> findByIdempotencyKey(
    String idempotencyKey,
  ) =>
      (select(posSessionOpenIdempotency)
            ..where((r) => r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

  Future<void> insertCompletedRecord({
    required String idempotencyKey,
    required String fingerprintHash,
    required int posSessionId,
    required double openingCash,
    int? createdByUserId,
  }) =>
      into(posSessionOpenIdempotency).insert(
        PosSessionOpenIdempotencyCompanion.insert(
          idempotencyKey: idempotencyKey,
          fingerprintHash: fingerprintHash,
          posSessionId: posSessionId,
          openingCash: openingCash,
          createdByUserId: Value(createdByUserId),
        ),
      );
}
