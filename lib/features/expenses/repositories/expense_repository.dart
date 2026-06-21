import 'package:drift/drift.dart';

import '../../../core/activity/activity_categories.dart';
import '../../../core/activity/activity_types.dart';
import '../../../core/database/app_database.dart' as db;
import '../../../core/services/activity_logger_service.dart';
import '../models/expense_category.dart';
import '../models/expense_page.dart';
import '../models/expense_record.dart';

class ExpenseRepository {
  ExpenseRepository(this._db) {
    _activityLogger = ActivityLoggerService(_db);
  }

  final db.AppDatabase _db;
  late final ActivityLoggerService _activityLogger;

  Future<int> createCategory(ExpenseCategory category) async {
    final id = await _db.expensesDao.createCategory(
      db.ExpenseCategoriesCompanion.insert(
        name: category.name,
        description: Value(category.description),
        isActive: Value(category.isActive),
      ),
    );

    await _activityLogger.logEntityCreate(
      activityType: ActivityTypes.expenseCategoryCreated,
      category: ActivityCategories.financial,
      entityType: 'expense_category',
      entityId: id,
      title: 'إضافة فئة مصروف',
      description: category.name,
      after: {'name': category.name, 'isActive': category.isActive},
    );

    return id;
  }

  Future<void> updateCategory(ExpenseCategory category) async {
    if (category.id == null) {
      throw ArgumentError('ExpenseCategory.id is required for update');
    }

    final before = await _db.expensesDao.getCategoryById(category.id!);
    final now = DateTime.now();

    await _db.expensesDao.updateCategory(
      db.ExpenseCategoriesCompanion(
        id: Value(category.id!),
        name: Value(category.name),
        description: Value(category.description),
        isActive: Value(category.isActive),
        updatedAt: Value(now),
      ),
    );

    await _activityLogger.logEntityUpdate(
      activityType: ActivityTypes.expenseCategoryUpdated,
      category: ActivityCategories.financial,
      entityType: 'expense_category',
      entityId: category.id!,
      title: 'تعديل فئة مصروف',
      description: category.name,
      before: before == null
          ? null
          : {
              'name': before.name,
              'description': before.description,
              'isActive': before.isActive,
            },
      after: {
        'name': category.name,
        'description': category.description,
        'isActive': category.isActive,
      },
    );
  }

  Future<List<ExpenseCategory>> listCategories({bool activeOnly = true}) async {
    final rows = await _db.expensesDao.listCategories(activeOnly: activeOnly);
    return rows.map(ExpenseCategory.fromDrift).toList();
  }

  Future<int> createExpense(ExpenseRecord record) async {
    final id = await _db.expensesDao.createExpense(
      db.ExpenseRecordsCompanion.insert(
        categoryId: record.categoryId,
        amount: record.amount,
        expenseDate: record.expenseDate,
        paidAt: record.paidAt,
        notes: Value(record.notes),
        sessionId: Value(record.sessionId),
        createdBy: record.createdBy,
      ),
    );

    await _activityLogger.logEntityCreate(
      activityType: ActivityTypes.expenseCreated,
      category: ActivityCategories.financial,
      entityType: 'expense',
      entityId: id,
      title: 'تسجيل مصروف',
      description: record.notes.isEmpty ? null : record.notes,
      after: {
        'categoryId': record.categoryId,
        'amount': record.amount,
        'paidAt': record.paidAt.toIso8601String(),
      },
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
      if (fetched == null) {
        throw StateError('Expense record not found');
      }
      if (fetched.isVoided) {
        throw StateError('Cannot update voided expense');
      }
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
      entityType: 'expense',
      entityId: record.id!,
      title: 'تعديل مصروف',
      description: record.notes.isEmpty ? null : record.notes,
      before: {
        'categoryId': before.categoryId,
        'amount': before.amount,
        'paidAt': before.paidAt.toIso8601String(),
      },
      after: {
        'categoryId': record.categoryId,
        'amount': record.amount,
        'paidAt': record.paidAt.toIso8601String(),
      },
    );
  }

  Future<void> voidExpense(int id) async {
    db.ExpenseRecord? before;

    await _db.transaction(() async {
      final fetched = await _db.expensesDao.getExpenseById(id);
      if (fetched == null) {
        throw StateError('Expense record not found');
      }
      if (fetched.isVoided) {
        return;
      }
      before = fetched;

      final voided = await _db.expensesDao.voidExpense(id);
      if (!voided) {
        throw StateError('Failed to void expense');
      }
    });

    if (before == null) return;

    await _activityLogger.logInfo(
      activityType: ActivityTypes.expenseVoided,
      category: ActivityCategories.financial,
      action: 'void',
      title: 'إلغاء مصروف',
      description: before!.notes.isEmpty ? null : before!.notes,
      entityType: 'expense',
      entityId: id,
      metadata: {
        'amount': before!.amount,
        'categoryId': before!.categoryId,
        'paidAt': before!.paidAt.toIso8601String(),
      },
    );
  }

  Future<ExpenseRecord?> getExpenseById(int id) async {
    final row = await _db.expensesDao.getExpenseById(id);
    return row == null ? null : ExpenseRecord.fromDrift(row);
  }

  Future<ExpensePage> getExpensesPaged({
    required int page,
    required int pageSize,
    bool includeVoided = false,
  }) async {
    final result = await _db.expensesDao.getExpensesPaged(
      page: page,
      pageSize: pageSize,
      includeVoided: includeVoided,
    );

    return ExpensePage(
      items: result.items
          .map((r) => ExpenseRecord.fromDrift(r))
          .toList(),
      totalCount: result.totalCount,
      page: result.page,
      pageSize: result.pageSize,
    );
  }
}