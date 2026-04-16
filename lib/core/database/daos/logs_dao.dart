// lib/core/database/daos/logs_dao.dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/logs_table.dart';
import '../tables/users_table.dart';

part 'logs_dao.g.dart';

@DriftAccessor(tables: [LogsTable, UsersTable])
class LogsDao extends DatabaseAccessor<AppDatabase> with _$LogsDaoMixin {
  LogsDao(super.db);

  Future<int> insertLog({required int? userId, required String actionType, String? details}) {
    return into(logsTable).insert(LogsTableCompanion.insert(
      userId: Value(userId),
      actionType: actionType,
      details: Value(details),
    ));
  }

  Stream<List<LogEntry>> watchRecentLogs({int limit = 50}) {
    return (select(logsTable)
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(limit))
        .watch();
  }

  Future<void> clearLogs() => delete(logsTable).go();
}
