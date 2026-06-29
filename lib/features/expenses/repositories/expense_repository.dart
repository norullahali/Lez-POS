import 'package:drift/drift.dart';

import '../../../core/activity/activity_categories.dart';
import '../../../core/activity/activity_types.dart';
import '../../../core/database/app_database.dart' as db;
import '../../../core/services/activity_logger_service.dart';
import '../models/expense_category.dart';
import '../models/expense_page.dart';
import '../models/expense_record.dart';
import '../models/expense_summary.dart';

class ExpenseRepository {
  ExpenseRepository(this._db) {
    _activityLogger = ActivityLoggerService(_db);
  }

  final db.AppDatabase _db;
  late final ActivityLoggerService _activityLogger;

  Future<int> createCategory(ExpenseCategory category) async {
    final id = await _db.expensesDao.createCategory(
      db.ExpenseCategoriesCompanion(
        name: Value(category.name),
        description: Value(category.description),
        isActive: Value(category.isActive),
      ),
    );
    await _activityLogger.logEntityCreate(
      activityType: ActivityTypes.expenseCategoryCreated,
      category: ActivityCategories.financial,
      entityType: 'expense_category',
      entityId: id,
      title: '\u0625\u0636\u0627\u0641\u0629 \u0641\u0626\u0629 \u0645\u0635\u0631\u0648\u0641',
      description: category.name,
    );
    return id;
  }

  Future<void> updateCategory(ExpenseCategory category) async {
    if (category.id == null) {
      throw ArgumentError('ExpenseCategory.id is required for update');
    }
    await _db.expensesDao.updateCategory(
      db.ExpenseCategoriesCompanion(
        id: Value(category.id!),
        name: Value(category.name),
        description: Value(category.description),
        isActive: Value(category.isActive),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _activityLogger.logEntityUpdate(
      activityType: ActivityTypes.expenseCategoryUpdated,
      category: ActivityCategories.financial,
      entityType: 'expense_category',
      entityId: category.id!,
      title: '\u062a\u0639\u062f\u064a\u0644 \u0641\u0626\u0629 \u0645\u0635\u0631\u0648\u0641',
      description: category.name,
    );
  }

  Future<List<ExpenseCategory>> listCategories({bool activeOnly = true}) async {
    final rows = await _db.expensesDao.listCategories(activeOnly: activeOnly);
    return rows.map(ExpenseCategory.fromDrift).toList();
  }

  Future<int> createExpense(ExpenseRecord record) async {
    final id = await _db.expensesDao.createExpense(
      db.ExpenseRecordsCompanion(
        categoryId: Value(record.categoryId),
        amount: Value(record.amount),
        expenseDate: Value(record.expenseDate),
        paidAt: Value(record.paidAt),
        notes: Value(record.notes),
        sessionId: Value(record.sessionId),
        createdBy: Value(record.createdBy),
      ),
    );
    await _activityLogger.logEntityCreate(
      activityType: ActivityTypes.expenseCreated,
      category: ActivityCategories.financial,
      entityType: 'expense_record',
      entityId: id,
      title: '\u062a\u0633\u062c\u064a\u0644 \u0645\u0635\u0631\u0648\u0641',
      description: record.amount.toStringAsFixed(2),
    );
    return id;
  }

  Future<void> updateExpense(ExpenseRecord record) async {
    if (record.id == null) {
      throw ArgumentError('ExpenseRecord.id is required for update');
    }
    late db.ExpenseRecord before;
    await _db.transaction(() async {
      final fetched = await _db.expensesDao.getExpenseById(record.id!);
      if (fetched == null) throw StateError('Expense record not found');
      if (fetched.isVoided) throw StateError('Cannot update voided expense');
      before = fetched;
      await _db.expensesDao.updateExpense(
        db.ExpenseRecordsCompanion(
          id: Value(record.id!),
          categoryId: Value(record.categoryId),
          amount: Value(record.amount),
          expenseDate: Value(record.expenseDate),
          paidAt: Value(record.paidAt),
          notes: Value(record.notes),
          sessionId: Value(record.sessionId),
          createdBy: Value(record.createdBy),
          updatedAt: Value(DateTime.now()),
          isVoided: const Value(false),
        ),
      );
    });
    await _activityLogger.logEntityUpdate(
      activityType: ActivityTypes.expenseUpdated,
      category: ActivityCategories.financial,
      entityType: 'expense_record',
      entityId: record.id!,
      title: '\u062a\u0639\u062f\u064a\u0644 \u0645\u0635\u0631\u0648\u0641',
      description: '${before.amount} -> ${record.amount}',
    );
  }

  Future<void> voidExpense(int id) async {
    db.ExpenseRecord? before;
    await _db.transaction(() async {
      final fetched = await _db.expensesDao.getExpenseById(id);
      if (fetched == null) throw StateError('Expense record not found');
      if (fetched.isVoided) return;
      before = fetched;
      final voided = await _db.expensesDao.voidExpense(id);
      if (!voided) throw StateError('Failed to void expense');
    });
    if (before == null) return;
    await _activityLogger.logInfo(
      activityType: ActivityTypes.expenseVoided,
      category: ActivityCategories.financial,
      action: 'void',
      title: '\u0625\u0644\u063a\u0627\u0621 \u0645\u0635\u0631\u0648\u0641',
      description: before!.notes,
      entityId: id,
    );
  }

  Future<ExpensePage> getExpensesPaged({
    required int page,
    required int pageSize,
    bool includeVoided = false,
    int? categoryId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final result = await _db.expensesDao.getExpensesPaged(
      page: page,
      pageSize: pageSize,
      includeVoided: includeVoided,
      categoryId: categoryId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    return ExpensePage(
      items: result.items.map(ExpenseRecord.fromDrift).toList(),
      totalCount: result.totalCount,
      page: result.page,
      pageSize: result.pageSize,
    );
  }

  Future<ExpenseSummary> getSummary({required int categoryCount}) async {
    final (activeCount, totalAmount, voidedCount) =
        await _db.expensesDao.getExpenseSummary();
    return ExpenseSummary(
      activeCount: activeCount,
      totalAmount: totalAmount,
      voidedCount: voidedCount,
      categoryCount: categoryCount,
    );
  }
}