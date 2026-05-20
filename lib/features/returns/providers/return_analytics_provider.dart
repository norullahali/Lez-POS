// lib/features/returns/providers/return_analytics_provider.dart
//
// Riverpod state management for the Return Analytics Dashboard.
// All providers are READ-ONLY — they never mutate any data.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../models/return_analytics_models.dart';
import '../repositories/return_analytics_repository.dart';

// ---- Repository provider ----------------------------------------------------

final returnAnalyticsRepositoryProvider =
    Provider<ReturnAnalyticsRepository>((ref) {
  return ReturnAnalyticsRepository(AppDatabase.instance);
});

// ---- Filter state -----------------------------------------------------------

final returnAnalyticsFilterProvider =
    StateProvider<ReturnAnalyticsFilter>((ref) => const ReturnAnalyticsFilter());

// ---- Data providers ---------------------------------------------------------

final returnOverviewProvider =
    FutureProvider.autoDispose<ReturnOverview>((ref) async {
  final filter = ref.watch(returnAnalyticsFilterProvider);
  final repo = ref.watch(returnAnalyticsRepositoryProvider);
  return repo.getOverview(filter);
});

final returnTrendProvider =
    FutureProvider.autoDispose<List<ReturnTrendPoint>>((ref) async {
  final filter = ref.watch(returnAnalyticsFilterProvider);
  final repo = ref.watch(returnAnalyticsRepositoryProvider);
  return repo.getDailyTrend(filter);
});

final topReturnedProductsProvider =
    FutureProvider.autoDispose<List<TopReturnedProduct>>((ref) async {
  final filter = ref.watch(returnAnalyticsFilterProvider);
  final repo = ref.watch(returnAnalyticsRepositoryProvider);
  return repo.getTopProducts(filter);
});

final cashierReturnStatsProvider =
    FutureProvider.autoDispose<List<CashierReturnStat>>((ref) async {
  final filter = ref.watch(returnAnalyticsFilterProvider);
  final repo = ref.watch(returnAnalyticsRepositoryProvider);
  return repo.getCashierStats(filter);
});

final suspiciousFlagsProvider =
    FutureProvider.autoDispose<List<SuspiciousFlag>>((ref) async {
  final repo = ref.watch(returnAnalyticsRepositoryProvider);
  return repo.getSuspiciousFlags();
});

// ---- Recent activity with pagination ----------------------------------------

class RecentActivityState {
  final List<RecentAuditRow> rows;
  final int totalCount;
  final int page;
  final bool isLoading;

  const RecentActivityState({
    required this.rows,
    required this.totalCount,
    required this.page,
    required this.isLoading,
  });

  static const empty = RecentActivityState(
    rows: [],
    totalCount: 0,
    page: 0,
    isLoading: false,
  );

  RecentActivityState copyWith({
    List<RecentAuditRow>? rows,
    int? totalCount,
    int? page,
    bool? isLoading,
  }) =>
      RecentActivityState(
        rows: rows ?? this.rows,
        totalCount: totalCount ?? this.totalCount,
        page: page ?? this.page,
        isLoading: isLoading ?? this.isLoading,
      );
}

class RecentActivityNotifier extends Notifier<RecentActivityState> {
  static const _pageSize = 50;

  @override
  RecentActivityState build() => RecentActivityState.empty;

  ReturnAnalyticsRepository get _repo =>
      ref.read(returnAnalyticsRepositoryProvider);

  ReturnAnalyticsFilter get _filter =>
      ref.read(returnAnalyticsFilterProvider);

  Future<void> loadPage(int page) async {
    state = state.copyWith(isLoading: true);
    final rows = await _repo.getRecentActivity(
      filter: _filter,
      limit: _pageSize,
      offset: page * _pageSize,
    );
    final total = await _repo.getRecentActivityCount(_filter);
    state = RecentActivityState(
      rows: rows,
      totalCount: total,
      page: page,
      isLoading: false,
    );
  }

  Future<void> refresh() => loadPage(0);
}

final recentActivityProvider =
    NotifierProvider<RecentActivityNotifier, RecentActivityState>(
        RecentActivityNotifier.new);
final analyticsCashierFilterOptionsProvider =
    FutureProvider.autoDispose<List<AnalyticsFilterOption>>((ref) async {
  final repo = ref.watch(returnAnalyticsRepositoryProvider);
  return repo.getCashierFilterOptions();
});

final analyticsProductFilterOptionsProvider =
    FutureProvider.autoDispose<List<AnalyticsFilterOption>>((ref) async {
  final repo = ref.watch(returnAnalyticsRepositoryProvider);
  return repo.getProductFilterOptions();
});
