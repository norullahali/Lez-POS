import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../core/activity/activity_categories.dart';
import '../../../core/activity/activity_types.dart';
import '../../../core/database/app_database.dart' as db;
import '../../../core/services/activity_logger_service.dart';
import '../../../core/services/expense_mutation_fingerprint.dart';
import '../../../core/services/expense_mutation_save_service.dart';
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

  /// Test-only update path. Production must use [ExpenseMutationSaveService.processUpdate].
  @visibleForTesting
  Future<void> updateExpenseForTest({
    required String idempotencyKey,
    required ExpenseRecord record,
    required int updatedBy,
  }) async {
    if (record.id == null) {
      throw ArgumentError('ExpenseRecord.id is required for update');
    }
    final fp = ExpenseMutationFingerprint.computeUpdate(
      expenseId: record.id!,
      categoryId: record.categoryId,
      amount: record.amount,
      expenseDate: record.expenseDate,
      paidAt: record.paidAt,
      notes: record.notes,
      updatedBy: updatedBy,
      sessionId: record.sessionId,
    );
    await ExpenseMutationSaveService(_db).processUpdate(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fp,
      expenseId: record.id!,
      categoryId: record.categoryId,
      amount: record.amount,
      expenseDate: record.expenseDate,
      paidAt: record.paidAt,
      notes: record.notes,
      updatedBy: updatedBy,
      sessionId: record.sessionId,
    );
  }

  /// Test-only void path. Production must use [ExpenseMutationSaveService.processVoid].
  @visibleForTesting
  Future<void> voidExpenseForTest({
    required String idempotencyKey,
    required int expenseId,
    required int voidedBy,
  }) async {
    final fp = ExpenseMutationFingerprint.computeVoid(
      expenseId: expenseId,
      voidedBy: voidedBy,
    );
    await ExpenseMutationSaveService(_db).processVoid(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fp,
      expenseId: expenseId,
      voidedBy: voidedBy,
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
