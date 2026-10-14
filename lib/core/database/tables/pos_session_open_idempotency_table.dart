// lib/core/database/tables/pos_session_open_idempotency_table.dart

import 'package:drift/drift.dart';

import 'pos_sessions_table.dart';

/// Persistent idempotency record for POS session open (B25).
class PosSessionOpenIdempotency extends Table {
  TextColumn get idempotencyKey => text()();
  TextColumn get fingerprintHash => text()();
  IntColumn get posSessionId =>
      integer().references(PosSessions, #id)();
  IntColumn get createdByUserId => integer().nullable()();
  RealColumn get openingCash => real()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};

  List<Index> get indexes => [
        Index(
          'psoi_pos_session_idx',
          'CREATE INDEX IF NOT EXISTS psoi_pos_session_idx '
              'ON pos_session_open_idempotency (pos_session_id)',
        ),
      ];
}
