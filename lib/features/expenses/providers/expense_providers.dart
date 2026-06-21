import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart' as db;
import '../models/expense_category.dart';
import '../models/expense_page.dart';
import '../repositories/expense_repository.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(db.AppDatabase.instance);
});

class ExpensesFilter {
  const ExpensesFilter({
    this.page = 0,
    this.pageSize = 50,
    this.includeVoided = false,
  });

  final int page;
  final int pageSize;
  final bool includeVoided;

  ExpensesFilter copyWith({
    int? page,
    int? pageSize,
    bool? includeVoided,
  }) {
    return ExpensesFilter(
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      includeVoided: includeVoided ?? this.includeVoided,
    );
  }
}

class ExpensesFilterNotifier extends Notifier<ExpensesFilter> {
  @override
  ExpensesFilter build() => const ExpensesFilter();

  void setPage(int page) => state = state.copyWith(page: page);

  void setIncludeVoided(bool includeVoided) =>
      state = state.copyWith(includeVoided: includeVoided, page: 0);

  void reset() => state = const ExpensesFilter();
}

final expensesFilterProvider =
    NotifierProvider<ExpensesFilterNotifier, ExpensesFilter>(
  ExpensesFilterNotifier.new,
);

final expenseCategoriesProvider =
    FutureProvider.autoDispose<List<ExpenseCategory>>((ref) async {
  final cache = ref.keepAlive();
  Future.delayed(const Duration(seconds: 45), cache.close);
  return ref.read(expenseRepositoryProvider).listCategories();
});

final expensesProvider = FutureProvider.autoDispose<ExpensePage>((ref) async {
  final filter = ref.watch(expensesFilterProvider);
  final cache = ref.keepAlive();
  Future.delayed(const Duration(seconds: 45), cache.close);
  return ref.read(expenseRepositoryProvider).getExpensesPaged(
        page: filter.page,
        pageSize: filter.pageSize,
        includeVoided: filter.includeVoided,
      );
});