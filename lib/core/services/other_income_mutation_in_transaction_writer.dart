import 'package:drift/drift.dart';

import '../activity/activity_categories.dart';
import '../activity/activity_context.dart';
import '../activity/activity_severity.dart';
import '../activity/activity_types.dart';
import '../database/app_database.dart';

/// Transaction-scoped other income UPDATE/VOID row mutations and activity logs (B23).
class OtherIncomeMutationInTransactionWriter {
  OtherIncomeMutationInTransactionWriter(this._db);

  final AppDatabase _db;

  Future<void> updateIncomeRowInTransaction({
    required int otherIncomeRecordId,
    required int categoryId,
    required double amount,
    required DateTime incomeDate,
    required DateTime receivedAt,
    required String notes,
    int? sessionId,
    required int createdBy,
  }) async {
    final updated = await (_db.update(_db.otherIncomeRecords)
          ..where(
            (e) => e.id.equals(otherIncomeRecordId) & e.isVoided.equals(false),
          ))
        .write(
      OtherIncomeRecordsCompanion(
        categoryId: Value(categoryId),
        amount: Value(amount),
        incomeDate: Value(incomeDate),
        receivedAt: Value(receivedAt),
        notes: Value(notes),
        sessionId: Value(sessionId),
        createdBy: Value(createdBy),
        updatedAt: Value(DateTime.now()),
        isVoided: const Value(false),
      ),
    );

    if (updated == 0) {
      throw StateError('Cannot update other income: not found or voided');
    }
  }

  /// Returns true if void was applied; false if already voided.
  Future<bool> voidIncomeRowInTransaction({
    required int otherIncomeRecordId,
  }) async {
    final updated = await (_db.update(_db.otherIncomeRecords)
          ..where(
            (e) => e.id.equals(otherIncomeRecordId) & e.isVoided.equals(false),
          ))
        .write(
      OtherIncomeRecordsCompanion(
        isVoided: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (updated == 0) {
      final row = await (_db.select(_db.otherIncomeRecords)
            ..where((e) => e.id.equals(otherIncomeRecordId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Other income record not found');
      }
      if (row.isVoided) {
        return false;
      }
      throw StateError('Failed to void other income');
    }
    return true;
  }

  Future<void> insertUpdateActivityLog({
    required int otherIncomeRecordId,
    required int updatedBy,
    required String description,
  }) async {
    final ctx = ActivityContextHolder.current;
    await _db.activityLogsDao.insertLog(
      ActivityLogsCompanion.insert(
        activityType: ActivityTypes.incomeUpdated,
        category: ActivityCategories.financial,
        severity: ActivitySeverity.info,
        userId: Value(updatedBy),
        usernameSnapshot: Value(ctx.username),
        roleSnapshot: Value(ctx.roleName),
        sessionId: Value(ctx.sessionId),
        entityType: const Value('other_income_record'),
        entityId: Value(otherIncomeRecordId),
        action: 'update',
        title: '\u062a\u0639\u062f\u064a\u0644 \u0625\u064a\u0631\u0627\u062f',
        description: Value(description),
        routeContext: Value(ctx.routeContext),
      ),
    );
  }

  Future<void> insertVoidActivityLog({
    required int otherIncomeRecordId,
    required int voidedBy,
  }) async {
    final ctx = ActivityContextHolder.current;
    await _db.activityLogsDao.insertLog(
      ActivityLogsCompanion.insert(
        activityType: ActivityTypes.incomeVoided,
        category: ActivityCategories.financial,
        severity: ActivitySeverity.warning,
        userId: Value(voidedBy),
        usernameSnapshot: Value(ctx.username),
        roleSnapshot: Value(ctx.roleName),
        sessionId: Value(ctx.sessionId),
        entityType: const Value('other_income_record'),
        entityId: Value(otherIncomeRecordId),
        action: 'void',
        title: '\u0625\u0644\u063a\u0627\u0621 \u0625\u064a\u0631\u0627\u062f',
        description: const Value(''),
        routeContext: Value(ctx.routeContext),
      ),
    );
  }
}
