// lib/core/database/tables/pos_sessions_table.dart
import 'package:drift/drift.dart';

class PosSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  /// Denormalized display name (pre-filled from user.fullName at open time).
  TextColumn get cashierName => text().withDefault(const Constant('كاشير'))();
  /// User who opened this session.
  IntColumn get createdByUserId =>
      integer().nullable().customConstraint('NULL REFERENCES users(id)')();
  DateTimeColumn get openedAt => dateTime().withDefault(currentDateAndTime)();
  RealColumn get openingCash => real().withDefault(const Constant(0.0))();

  // -- Close fields (all nullable until session is closed) ------------------
  IntColumn get closedByUserId =>
      integer().nullable().customConstraint('NULL REFERENCES users(id)')();
  DateTimeColumn get closedAt => dateTime().nullable()();
  RealColumn get closingCash => real().nullable()();
  /// Cash expected at close: openingCash + sum(cash_paid) for this session.
  RealColumn get expectedCashAmount => real().nullable()();
  /// closingCash - expectedCashAmount (negative = shortage, positive = overage).
  RealColumn get cashDifference => real().nullable()();

  // -- Meta -----------------------------------------------------------------
  TextColumn get notes => text().nullable()();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();

  List<Index> get indexes => [
        Index('ps_status_idx',
            'CREATE INDEX IF NOT EXISTS ps_status_idx ON pos_sessions (is_closed)'),
        Index('ps_user_idx',
            'CREATE INDEX IF NOT EXISTS ps_user_idx ON pos_sessions (created_by_user_id)'),
      ];
}