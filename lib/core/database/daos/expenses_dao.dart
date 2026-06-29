import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/expense_categories_table.dart';
import '../tables/expense_records_table.dart';

part 'expenses_dao.g.dart';

class ExpensePageResult {
  const ExpensePageResult({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  final List<ExpenseRecord> items;
  final int totalCount;
  final int page;
  final int pageSize;

  int get totalPages =>
      pageSize <= 0 ? 0 : (totalCount + pageSize - 1) ~/ pageSize;
}

@DriftAccessor(tables: [ExpenseCategories, ExpenseRecords])
class ExpensesDao extends DatabaseAccessor<AppDatabase>
    with _$ExpensesDaoMixin {
  ExpensesDao(super.db);

  Future<int> createCategory(ExpenseCategoriesCompanion entry) =>
      into(expenseCategories).insert(entry);

  Future<bool> updateCategory(ExpenseCategoriesCompanion entry) =>
      update(expenseCategories).replace(entry);

  Future<List<ExpenseCategory>> listCategories({bool activeOnly = true}) {
    final query = select(expenseCategories)
      ..orderBy([(c) => OrderingTerm.asc(c.name)]);
    if (activeOnly) {
      query.where((c) => c.isActive.equals(true));
    }
    return query.get();
  }

  Future<ExpenseCategory?> getCategoryById(int id) =>
      (select(expenseCategories)..where((c) => c.id.equals(id)))
          .getSingleOrNull();

  Future<int> createExpense(ExpenseRecordsCompanion entry) =>
      into(expenseRecords).insert(entry);

  Future<bool> updateExpense(ExpenseRecordsCompanion entry) =>
      update(expenseRecords).replace(entry);

  Future<bool> voidExpense(int id) async {
    final rows = await (update(expenseRecords)..where((e) => e.id.equals(id)))
        .write(
      ExpenseRecordsCompanion(
        isVoided: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return rows > 0;
  }

  Future<ExpenseRecord?> getExpenseById(int id) =>
      (select(expenseRecords)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<ExpensePageResult> getExpensesPaged({
    required int page,
    required int pageSize,
    bool includeVoided = false,
    int? categoryId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final countExpr = expenseRecords.id.count();
    final countQuery = selectOnly(expenseRecords)..addColumns([countExpr]);
    if (!includeVoided) {
      countQuery.where(expenseRecords.isVoided.equals(false));
    }
    if (categoryId != null) {
      countQuery.where(expenseRecords.categoryId.equals(categoryId));
    }
    if (dateFrom != null) {
      countQuery.where(expenseRecords.paidAt.isBiggerOrEqualValue(dateFrom));
    }
    if (dateTo != null) {
      countQuery.where(expenseRecords.paidAt.isSmallerOrEqualValue(dateTo));
    }

    final countRow = await countQuery.getSingle();
    final totalCount = countRow.read(countExpr) ?? 0;

    if (totalCount == 0) {
      return ExpensePageResult(
        items: const [],
        totalCount: 0,
        page: page,
        pageSize: pageSize,
      );
    }

    final offset = page * pageSize;
    final query = select(expenseRecords)
      ..orderBy([
        (e) => OrderingTerm.desc(e.paidAt),
        (e) => OrderingTerm.desc(e.id),
      ])
      ..limit(pageSize, offset: offset);
    if (!includeVoided) query.where((e) => e.isVoided.equals(false));
    if (categoryId != null) {
      query.where((e) => e.categoryId.equals(categoryId));
    }
    if (dateFrom != null) {
      query.where((e) => e.paidAt.isBiggerOrEqualValue(dateFrom));
    }
    if (dateTo != null) {
      query.where((e) => e.paidAt.isSmallerOrEqualValue(dateTo));
    }

    final items = await query.get();
    return ExpensePageResult(
      items: items,
      totalCount: totalCount,
      page: page,
      pageSize: pageSize,
    );
  }

  Future<(int activeCount, double totalAmount, int voidedCount)>
      getExpenseSummary() async {
    final row = await customSelect(
      'SELECT '
      'COUNT(CASE WHEN is_voided = 0 THEN 1 END) AS active_count, '
      'COALESCE(SUM(CASE WHEN is_voided = 0 THEN amount END), 0.0) AS total_amount, '
      'COUNT(CASE WHEN is_voided = 1 THEN 1 END) AS voided_count '
      'FROM expense_records',
      readsFrom: {expenseRecords},
    ).getSingle();
    return (
      (row.data['active_count'] as int?) ?? 0,
      (row.data['total_amount'] as num?)?.toDouble() ?? 0.0,
      (row.data['voided_count'] as int?) ?? 0,
    );
  }
}