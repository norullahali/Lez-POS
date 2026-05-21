// lib/features/activity/providers/activity_logs_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/daos/activity_logs_dao.dart';
import '../repositories/activity_logs_repository.dart';

final activityLogsRepositoryProvider = Provider((ref) {
  return ActivityLogsRepository(AppDatabase.instance);
});

class ActivityLogsFilter {
  const ActivityLogsFilter({
    this.userId,
    this.category,
    this.severity,
    this.entityType,
    this.action,
    this.search,
    this.from,
    this.to,
    this.page = 0,
    this.pageSize = 50,
  });

  final int? userId;
  final String? category;
  final String? severity;
  final String? entityType;
  final String? action;
  final String? search;
  final DateTime? from;
  final DateTime? to;
  final int page;
  final int pageSize;

  ActivityLogQuery toQuery() => ActivityLogQuery(
        limit: pageSize,
        offset: page * pageSize,
        userId: userId,
        category: category,
        severity: severity,
        entityType: entityType,
        action: action,
        search: search,
        from: from,
        to: to,
      );

  ActivityLogsFilter copyWith({
    int? userId,
    String? category,
    String? severity,
    String? entityType,
    String? action,
    String? search,
    DateTime? from,
    DateTime? to,
    int? page,
    int? pageSize,
    bool clearUserId = false,
    bool clearCategory = false,
    bool clearSeverity = false,
    bool clearEntityType = false,
    bool clearAction = false,
    bool clearSearch = false,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return ActivityLogsFilter(
      userId: clearUserId ? null : (userId ?? this.userId),
      category: clearCategory ? null : (category ?? this.category),
      severity: clearSeverity ? null : (severity ?? this.severity),
      entityType: clearEntityType ? null : (entityType ?? this.entityType),
      action: clearAction ? null : (action ?? this.action),
      search: clearSearch ? null : (search ?? this.search),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }
}

class ActivityLogsPage {
  const ActivityLogsPage({required this.items, required this.total, required this.filter});
  final List<ActivityLog> items;
  final int total;
  final ActivityLogsFilter filter;
}

final activityLogsFilterProvider = StateProvider<ActivityLogsFilter>((ref) {
  return const ActivityLogsFilter();
});

final activityLogsPageProvider = FutureProvider.autoDispose<ActivityLogsPage>((ref) async {
  final filter = ref.watch(activityLogsFilterProvider);
  final repo = ref.watch(activityLogsRepositoryProvider);
  final q = filter.toQuery();
  final countQ = ActivityLogQuery(
    userId: q.userId,
    category: q.category,
    severity: q.severity,
    entityType: q.entityType,
    entityId: q.entityId,
    action: q.action,
    search: q.search,
    from: q.from,
    to: q.to,
  );
  final results = await Future.wait([
    repo.queryPage(q),
    repo.count(countQ),
  ]);
  return ActivityLogsPage(
    items: results[0] as List<ActivityLog>,
    total: results[1] as int,
    filter: filter,
  );
});