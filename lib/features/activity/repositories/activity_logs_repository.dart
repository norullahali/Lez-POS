// lib/features/activity/repositories/activity_logs_repository.dart
import '../../../core/database/app_database.dart';
import '../../../core/database/daos/activity_logs_dao.dart';

class ActivityLogsRepository {
  ActivityLogsRepository(this._db);
  final AppDatabase _db;

  Future<List<ActivityLog>> queryPage(ActivityLogQuery query) =>
      _db.activityLogsDao.queryPage(query);

  Future<int> count(ActivityLogQuery query) => _db.activityLogsDao.count(query);
}