import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart' as appdb;
import '../models/other_income_category.dart';
import '../models/other_income_page.dart';
import '../models/other_income_summary.dart';
import '../repositories/other_income_repository.dart';

// ── Repository provider ───────────────────────────────────────────────────

/// Injects AppDatabase through Riverpod — never uses AppDatabase.instance directly.
final otherIncomeRepositoryProvider = Provider<OtherIncomeRepository>((ref) {
  return OtherIncomeRepository(appdb.AppDatabase.instance);
});

// ── Filter model ──────────────────────────────────────────────────────────

const _sentinel = Object();

class OtherIncomeFilter {
  const OtherIncomeFilter({
    this.page = 0,
    this.pageSize = 25,
    this.includeVoided = false,
    this.categoryId,
    this.dateFrom,
    this.dateTo,
  });

  final int page;
  final int pageSize;
  final bool includeVoided;
  final int? categoryId;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  OtherIncomeFilter copyWith({
    int? page,
    int? pageSize,
    bool? includeVoided,
    Object? categoryId = _sentinel,
    Object? dateFrom = _sentinel,
    Object? dateTo = _sentinel,
  }) {
    return OtherIncomeFilter(
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      includeVoided: includeVoided ?? this.includeVoided,
      categoryId:
          categoryId == _sentinel ? this.categoryId : categoryId as int?,
      dateFrom: dateFrom == _sentinel ? this.dateFrom : dateFrom as DateTime?,
      dateTo: dateTo == _sentinel ? this.dateTo : dateTo as DateTime?,
    );
  }
}

class OtherIncomeFilterNotifier extends Notifier<OtherIncomeFilter> {
  @override
  OtherIncomeFilter build() => const OtherIncomeFilter();

  void setPage(int page) => state = state.copyWith(page: page);

  void setIncludeVoided(bool v) =>
      state = state.copyWith(includeVoided: v, page: 0);

  void setCategoryId(int? id) =>
      state = state.copyWith(categoryId: id, page: 0);

  void setDateRange(DateTime? from, DateTime? to) =>
      state = state.copyWith(dateFrom: from, dateTo: to, page: 0);

  void reset() => state = const OtherIncomeFilter();
}

final otherIncomeFilterProvider =
    NotifierProvider<OtherIncomeFilterNotifier, OtherIncomeFilter>(
        OtherIncomeFilterNotifier.new);

// ── Data providers ────────────────────────────────────────────────────────

final otherIncomeCategoriesProvider =
    FutureProvider.autoDispose<List<OtherIncomeCategory>>((ref) async {
  final keepAlive = ref.keepAlive();
  Future.delayed(const Duration(seconds: 45), keepAlive.close);
  return ref
      .read(otherIncomeRepositoryProvider)
      .listCategories(activeOnly: false);
});

final otherIncomeProvider =
    FutureProvider.autoDispose<OtherIncomePage>((ref) async {
  final filter = ref.watch(otherIncomeFilterProvider);
  final keepAlive = ref.keepAlive();
  Future.delayed(const Duration(seconds: 45), keepAlive.close);
  return ref.read(otherIncomeRepositoryProvider).getIncomePaged(
        page: filter.page,
        pageSize: filter.pageSize,
        includeVoided: filter.includeVoided,
        categoryId: filter.categoryId,
        dateFrom: filter.dateFrom,
        dateTo: filter.dateTo,
      );
});

final otherIncomeSummaryProvider =
    FutureProvider.autoDispose<OtherIncomeSummary>((ref) async {
  final keepAlive = ref.keepAlive();
  Future.delayed(const Duration(seconds: 45), keepAlive.close);
  return ref.read(otherIncomeRepositoryProvider).getSummary();
});
