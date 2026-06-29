import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart' as db;
import '../models/expense_category.dart';
import '../models/expense_page.dart';
import '../models/expense_summary.dart';
import '../repositories/expense_repository.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(db.AppDatabase.instance);
});

class ExpensesFilter {
  const ExpensesFilter({
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

  ExpensesFilter copyWith({
    int? page,
    int? pageSize,
    bool? includeVoided,
    Object? categoryId = _sentinel,
    Object? dateFrom = _sentinel,
    Object? dateTo = _sentinel,
  }) {
    return ExpensesFilter(
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

const _sentinel = Object();

class ExpensesFilterNotifier extends Notifier<ExpensesFilter> {
  @override
  ExpensesFilter build() => const ExpensesFilter();

  void setPage(int page) => state = state.copyWith(page: page);

  void setIncludeVoided(bool v) =>
      state = state.copyWith(includeVoided: v, page: 0);

  void setCategoryId(int? id) =>
      state = state.copyWith(categoryId: id, page: 0);

  void setDateRange(DateTime? from, DateTime? to) =>
      state = state.copyWith(dateFrom: from, dateTo: to, page: 0);

  void reset() => state = const ExpensesFilter();
}

final expensesFilterProvider =
    NotifierProvider<ExpensesFilterNotifier, ExpensesFilter>(
        ExpensesFilterNotifier.new);

final expenseCategoriesProvider =
    FutureProvider.autoDispose<List<ExpenseCategory>>((ref) async {
  final keepAlive = ref.keepAlive();
  Future.delayed(const Duration(seconds: 45), keepAlive.close);
  return ref.read(expenseRepositoryProvider).listCategories(activeOnly: false);
});

final expensesProvider =
    FutureProvider.autoDispose<ExpensePage>((ref) async {
  final filter = ref.watch(expensesFilterProvider);
  final keepAlive = ref.keepAlive();
  Future.delayed(const Duration(seconds: 45), keepAlive.close);
  return ref.read(expenseRepositoryProvider).getExpensesPaged(
        page: filter.page,
        pageSize: filter.pageSize,
        includeVoided: filter.includeVoided,
        categoryId: filter.categoryId,
        dateFrom: filter.dateFrom,
        dateTo: filter.dateTo,
      );
});

final expenseSummaryProvider =
    FutureProvider.autoDispose<ExpenseSummary>((ref) async {
  final categories =
      await ref.watch(expenseCategoriesProvider.future);
  final activeCats = categories.where((c) => c.isActive).length;
  return ref
      .read(expenseRepositoryProvider)
      .getSummary(categoryCount: activeCats);
});

final _usersMapProvider = FutureProvider.autoDispose<Map<int, String>>((ref) async {
  final users = await db.AppDatabase.instance.usersDao.getAllUsers();
  return {for (final u in users) u.id: u.fullName};
});

final usersMapForExpensesProvider = _usersMapProvider;