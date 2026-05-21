// lib/core/database/daos/activity_logs_dao.dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/activity_logs_table.dart';

part 'activity_logs_dao.g.dart';

class ActivityLogQuery {
  const ActivityLogQuery({
    this.limit = 50,
    this.offset = 0,
    this.userId,
    this.category,
    this.severity,
    this.entityType,
    this.entityId,
    this.action,
    this.search,
    this.from,
    this.to,
  });

  final int limit;
  final int offset;
  final int? userId;
  final String? category;
  final String? severity;
  final String? entityType;
  final int? entityId;
  final String? action;
  final String? search;
  final DateTime? from;
  final DateTime? to;
}

@DriftAccessor(tables: [ActivityLogs])
class ActivityLogsDao extends DatabaseAccessor<AppDatabase>
    with _$ActivityLogsDaoMixin {
  ActivityLogsDao(super.db);

  Future<int> insertLog(ActivityLogsCompanion entry) =>
      into(activityLogs).insert(entry);

  Expression<bool> _filter($ActivityLogsTable t, ActivityLogQuery q) {
    Expression<bool> expr = const Constant(true);
    if (q.userId != null) expr = expr & t.userId.equals(q.userId!);
    if (q.category != null) expr = expr & t.category.equals(q.category!);
    if (q.severity != null) expr = expr & t.severity.equals(q.severity!);
    if (q.entityType != null) expr = expr & t.entityType.equals(q.entityType!);
    if (q.entityId != null) expr = expr & t.entityId.equals(q.entityId!);
    if (q.action != null) expr = expr & t.action.equals(q.action!);
    if (q.from != null) expr = expr & t.createdAt.isBiggerOrEqualValue(q.from!);
    if (q.to != null) expr = expr & t.createdAt.isSmallerOrEqualValue(q.to!);
    if (q.search != null && q.search!.trim().isNotEmpty) {
      final term = '%${q.search!.trim()}%';
      expr = expr &
          (t.title.like(term) |
              t.description.like(term) |
              t.activityType.like(term) |
              t.usernameSnapshot.like(term));
    }
    return expr;
  }

  Future<List<ActivityLog>> queryPage(ActivityLogQuery q) =>
      (select(activityLogs)
            ..where((t) => _filter(t, q))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(q.limit, offset: q.offset))
          .get();

  Future<int> count(ActivityLogQuery q) async {
    final countExp = activityLogs.id.count();
    final query = selectOnly(activityLogs)..addColumns([countExp]);
    query.where(_filter(activityLogs, q));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }
}