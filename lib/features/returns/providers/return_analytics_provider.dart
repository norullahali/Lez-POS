// lib/features/returns/providers/return_analytics_provider.dart
//
// Riverpod state management for the Return Analytics Dashboard.
// Persistent FutureProviders (non-autoDispose) read directly from the
// repository — no intermediate cache layer on the analytics data path.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../models/return_analytics_models.dart';
import '../repositories/return_analytics_repository.dart';
import '../utils/return_analytics_date_utils.dart';

// ---- Repository provider ----------------------------------------------------

final returnAnalyticsRepositoryProvider =
    Provider<ReturnAnalyticsRepository>((ref) {
  return ReturnAnalyticsRepository(AppDatabase.instance);
});

// ---- Filter state -----------------------------------------------------------

/// Bumped after return operations to trigger a refetch of all analytics queries.
final returnAnalyticsGenerationProvider = StateProvider<int>((ref) => 0);

final returnAnalyticsFilterProvider =
    StateProvider<ReturnAnalyticsFilter>((ref) => const ReturnAnalyticsFilter());

ReturnAnalyticsFilter _activeFilter(Ref ref) =>
    ReturnAnalyticsDateUtils.normalizeFilter(
      ref.read(returnAnalyticsFilterProvider),
    );

// ---- Data providers (persistent, filter-aware, direct DB reads) -------------

final returnOverviewProvider = FutureProvider<ReturnOverview>((ref) async {
  ref.watch(returnAnalyticsGenerationProvider);
  final filter = ReturnAnalyticsDateUtils.normalizeFilter(
    ref.watch(returnAnalyticsFilterProvider),
  );
  return ref.read(returnAnalyticsRepositoryProvider).getOverview(filter);
});

final returnTrendProvider =
    FutureProvider<List<ReturnTrendPoint>>((ref) async {
  ref.watch(returnAnalyticsGenerationProvider);
  final filter = ReturnAnalyticsDateUtils.normalizeFilter(
    ref.watch(returnAnalyticsFilterProvider),
  );
  return ref.read(returnAnalyticsRepositoryProvider).getDailyTrend(filter);
});

final topReturnedProductsProvider =
    FutureProvider<List<TopReturnedProduct>>((ref) async {
  ref.watch(returnAnalyticsGenerationProvider);
  final filter = ReturnAnalyticsDateUtils.normalizeFilter(
    ref.watch(returnAnalyticsFilterProvider),
  );
  return ref.read(returnAnalyticsRepositoryProvider).getTopProducts(filter);
});

final cashierReturnStatsProvider =
    FutureProvider<List<CashierReturnStat>>((ref) async {
  ref.watch(returnAnalyticsGenerationProvider);
  final filter = ReturnAnalyticsDateUtils.normalizeFilter(
    ref.watch(returnAnalyticsFilterProvider),
  );
  return ref.read(returnAnalyticsRepositoryProvider).getCashierStats(filter);
});

final suspiciousFlagsProvider =
    FutureProvider<List<SuspiciousFlag>>((ref) async {
  ref.watch(returnAnalyticsGenerationProvider);
  return ref.read(returnAnalyticsRepositoryProvider).getSuspiciousFlags();
});

// ---- Filter dropdown options ------------------------------------------------

final analyticsCashierFilterOptionsProvider =
    FutureProvider<List<AnalyticsFilterOption>>((ref) async {
  ref.watch(returnAnalyticsGenerationProvider);
  return ref.read(returnAnalyticsRepositoryProvider).getCashierFilterOptions();
});

final analyticsProductFilterOptionsProvider =
    FutureProvider<List<AnalyticsFilterOption>>((ref) async {
  ref.watch(returnAnalyticsGenerationProvider);
  return ref.read(returnAnalyticsRepositoryProvider).getProductFilterOptions();
});

// ---- Recent activity with pagination ----------------------------------------

class RecentActivityState {
  final List<RecentAuditRow> rows;
  final int totalCount;
  final int page;
  final bool isLoading;
  final bool hasLoadedOnce;

  const RecentActivityState({
    required this.rows,
    required this.totalCount,
    required this.page,
    required this.isLoading,
    required this.hasLoadedOnce,
  });

  static const empty = RecentActivityState(
    rows: [],
    totalCount: 0,
    page: 0,
    isLoading: false,
    hasLoadedOnce: false,
  );

  RecentActivityState copyWith({
    List<RecentAuditRow>? rows,
    int? totalCount,
    int? page,
    bool? isLoading,
    bool? hasLoadedOnce,
  }) =>
      RecentActivityState(
        rows: rows ?? this.rows,
        totalCount: totalCount ?? this.totalCount,
        page: page ?? this.page,
        isLoading: isLoading ?? this.isLoading,
        hasLoadedOnce: hasLoadedOnce ?? this.hasLoadedOnce,
      );
}

class RecentActivityNotifier extends Notifier<RecentActivityState> {
  static const _pageSize = 50;
  int _requestId = 0;

  @override
  RecentActivityState build() {
    ref.listen(returnAnalyticsFilterProvider, (_, __) => refresh());
    ref.listen(returnAnalyticsGenerationProvider, (_, __) => refresh());
    Future.microtask(refresh);
    return RecentActivityState.empty;
  }

  ReturnAnalyticsRepository get _repo =>
      ref.read(returnAnalyticsRepositoryProvider);

  Future<void> loadPage(int page) async {
    final filter = _activeFilter(ref);
    final requestId = ++_requestId;

    state = state.copyWith(isLoading: true);

    try {
      final rows = await _repo.getRecentActivity(
        filter: filter,
        limit: _pageSize,
        offset: page * _pageSize,
      );
      if (requestId != _requestId) return;
      final total = await _repo.getRecentActivityCount(filter);
      if (requestId != _requestId) return;

      state = RecentActivityState(
        rows: rows,
        totalCount: total,
        page: page,
        isLoading: false,
        hasLoadedOnce: true,
      );
    } catch (_) {
      if (requestId != _requestId) return;
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refresh() => loadPage(0);
}

final recentActivityProvider =
    NotifierProvider<RecentActivityNotifier, RecentActivityState>(
        RecentActivityNotifier.new);

/// Triggers a refetch of all analytics data after a return operation.
void invalidateReturnAnalytics(WidgetRef ref) {
  ref.read(returnAnalyticsGenerationProvider.notifier).state++;
  ref.read(recentActivityProvider.notifier).refresh();
}
