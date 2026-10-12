import 'package:drift/drift.dart';

import '../activity/activity_categories.dart';
import '../activity/activity_context.dart';
import '../activity/activity_severity.dart';
import '../activity/activity_types.dart';
import '../database/app_database.dart';

/// Transaction-scoped expense UPDATE/VOID row mutations and activity logs (B22).
class ExpenseMutationInTransactionWriter {
  ExpenseMutationInTransactionWriter(this._db);

  final AppDatabase _db;

  Future<void> updateExpenseRowInTransaction({
    required int expenseId,
    required int categoryId,
    required double amount,
    required DateTime expenseDate,
    required DateTime paidAt,
    required String notes,
    int? sessionId,
    required int createdBy,
  }) async {
    final updated = await (_db.update(_db.expenseRecords)
          ..where(
            (e) => e.id.equals(expenseId) & e.isVoided.equals(false),
          ))
        .write(
      ExpenseRecordsCompanion(
        categoryId: Value(categoryId),
        amount: Value(amount),
        expenseDate: Value(expenseDate),
        paidAt: Value(paidAt),
        notes: Value(notes),
        sessionId: Value(sessionId),
        createdBy: Value(createdBy),
        updatedAt: Value(DateTime.now()),
        isVoided: const Value(false),
      ),
    );

    if (updated == 0) {
      throw StateError('Cannot update expense: not found or voided');
    }
  }

  /// Returns true if void was applied; false if already voided.
  Future<bool> voidExpenseRowInTransaction({required int expenseId}) async {
    final updated = await (_db.update(_db.expenseRecords)
          ..where(
            (e) => e.id.equals(expenseId) & e.isVoided.equals(false),
          ))
        .write(
      ExpenseRecordsCompanion(
        isVoided: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (updated == 0) {
      final row = await (_db.select(_db.expenseRecords)
            ..where((e) => e.id.equals(expenseId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Expense record not found');
      }
      if (row.isVoided) {
        return false;
      }
      throw StateError('Failed to void expense');
    }
    return true;
  }

  Future<void> insertUpdateActivityLog({
    required int expenseId,
    required int updatedBy,
    required String description,
  }) async {
    final ctx = ActivityContextHolder.current;
    await _db.activityLogsDao.insertLog(
      ActivityLogsCompanion.insert(
        activityType: ActivityTypes.expenseUpdated,
        category: ActivityCategories.financial,
        severity: ActivitySeverity.info,
        userId: Value(updatedBy),
        usernameSnapshot: Value(ctx.username),
        roleSnapshot: Value(ctx.roleName),
        sessionId: Value(ctx.sessionId),
        entityType: const Value('expense_record'),
        entityId: Value(expenseId),
        action: 'update',
        title: '\u062a\u0639\u062f\u064a\u0644 \u0645\u0635\u0631\u0648\u0641',
        description: Value(description),
        routeContext: Value(ctx.routeContext),
      ),
    );
  }

  Future<void> insertVoidActivityLog({
    required int expenseId,
    required int voidedBy,
  }) async {
    final ctx = ActivityContextHolder.current;
    await _db.activityLogsDao.insertLog(
      ActivityLogsCompanion.insert(
        activityType: ActivityTypes.expenseVoided,
        category: ActivityCategories.financial,
        severity: ActivitySeverity.warning,
        userId: Value(voidedBy),
        usernameSnapshot: Value(ctx.username),
        roleSnapshot: Value(ctx.roleName),
        sessionId: Value(ctx.sessionId),
        entityType: const Value('expense_record'),
        entityId: Value(expenseId),
        action: 'void',
        title: '\u0625\u0644\u063a\u0627\u0621 \u0645\u0635\u0631\u0648\u0641',
        description: const Value(''),
        routeContext: Value(ctx.routeContext),
      ),
    );
  }
}
