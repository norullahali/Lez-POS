// lib/core/database/tables/activity_logs_table.dart
//
// Immutable append-only operational activity ledger.
import 'package:drift/drift.dart';

@DataClassName('ActivityLog')
class ActivityLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  TextColumn get activityType => text().withLength(min: 2, max: 100)();
  TextColumn get category => text().withLength(min: 2, max: 50)();
  TextColumn get severity => text().withLength(min: 2, max: 20)();

  IntColumn get userId => integer().nullable().customConstraint('NULL REFERENCES users(id)')();
  TextColumn get usernameSnapshot => text().nullable()();
  TextColumn get roleSnapshot => text().nullable()();

  IntColumn get sessionId => integer().nullable().customConstraint('NULL REFERENCES pos_sessions(id)')();

  TextColumn get entityType => text().nullable().withLength(min: 2, max: 50)();
  IntColumn get entityId => integer().nullable()();

  TextColumn get action => text().withLength(min: 2, max: 50)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();

  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text().nullable()();
  TextColumn get metadataJson => text().nullable()();

  TextColumn get routeContext => text().nullable()();
  TextColumn get deviceInfo => text().nullable()();
  TextColumn get ipAddress => text().nullable()();

  List<Index> get indexes => [
        Index('idx_activity_logs_created_at', 'created_at DESC'),
        Index('idx_activity_logs_user_id', 'user_id'),
        Index('idx_activity_logs_category', 'category'),
        Index('idx_activity_logs_entity_type', 'entity_type'),
        Index('idx_activity_logs_entity_id', 'entity_id'),
        Index('idx_activity_logs_severity', 'severity'),
      ];
}