import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../activity/activity_categories.dart';
import '../activity/activity_context.dart';
import '../activity/activity_severity.dart';
import '../activity/activity_types.dart';
import '../database/app_database.dart';
import 'expense_creation_fingerprint.dart';
import 'expense_creation_idempotency_conflict_exception.dart';
import 'expense_creation_result.dart';

class _IdempotencySealRace implements Exception {}

/// Canonical orchestrator for expense creation with persistent idempotency (B18).
class ExpenseCreationService {
  ExpenseCreationService(
    this.db, {
    @visibleForTesting Future<void> Function()? preSealHook,
    @visibleForTesting Future<void> Function()? beforeExpenseInsertHook,
    @visibleForTesting Future<void> Function()? testActivityLogHook,
  })  : _preSealHook = preSealHook,
        _beforeExpenseInsertHook = beforeExpenseInsertHook,
        _testActivityLogHook = testActivityLogHook;

  final AppDatabase db;
  final Future<void> Function()? _preSealHook;
  final Future<void> Function()? _beforeExpenseInsertHook;
  final Future<void> Function()? _testActivityLogHook;

  /// Processes expense creation with idempotency.
  ///
  /// [idempotencyKey] identifies the operation. Retries with the same key and
  /// identical [fingerprintHash] replay the original expense without mutation.
  Future<ExpenseCreationResult> processCreate({
    required String idempotencyKey,
    required String fingerprintHash,
    required int categoryId,
    required double amount,
    required DateTime expenseDate,
    required DateTime paidAt,
    required String notes,
    required int createdBy,
    int? sessionId,
  }) async {
    final normalizedExpenseDate =
        ExpenseCreationFingerprint.normalizeDate(expenseDate);
    final normalizedPaidAt = ExpenseCreationFingerprint.normalizeDate(paidAt);
    final roundedAmount = ExpenseCreationFingerprint.roundAmount(amount);
    final normalizedNotes = ExpenseCreationFingerprint.normalizeNotes(notes);

    if (createdBy <= 0) {
      throw ArgumentError('createdBy must be positive');
    }
    if (categoryId <= 0) {
      throw ArgumentError('categoryId must be positive');
    }
    if (roundedAmount <= 0) {
      throw ArgumentError('amount must be positive');
    }

    final category = await db.expensesDao.getCategoryById(categoryId);
    if (category == null) {
      throw StateError('Expense category not found');
    }
    if (!category.isActive) {
      throw StateError('Expense category is not active');
    }

    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await db.transaction(() async {
          final existing = await db.expenseIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (existing.fingerprintHash != fingerprintHash) {
              throw const ExpenseCreationIdempotencyConflictException();
            }
            return ExpenseCreationResult(
              expenseRecordId: existing.expenseRecordId,
              idempotentReplay: true,
            );
          }

          if (_beforeExpenseInsertHook != null) {
            await _beforeExpenseInsertHook!();
          }

          final expenseId = await db.expensesDao.createExpenseInTransaction(
            ExpenseRecordsCompanion(
              categoryId: Value(categoryId),
              amount: Value(roundedAmount),
              expenseDate: Value(normalizedExpenseDate),
              paidAt: Value(normalizedPaidAt),
              notes: Value(normalizedNotes),
              sessionId: Value(sessionId),
              createdBy: Value(createdBy),
            ),
          );

          if (_testActivityLogHook != null) {
            await _testActivityLogHook!();
          } else {
            await _insertExpenseCreationActivityLog(
              expenseId: expenseId,
              description: roundedAmount.toStringAsFixed(2),
            );
          }

          if (_preSealHook != null) {
            await _preSealHook!();
          }

          try {
            await db.expenseIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              fingerprintHash: fingerprintHash,
              expenseRecordId: expenseId,
            );
          } catch (e) {
            if (_isUniqueIdempotencyKeyViolation(e)) {
              throw _IdempotencySealRace();
            }
            rethrow;
          }

          return ExpenseCreationResult(
            expenseRecordId: expenseId,
            idempotentReplay: false,
          );
        });
      } on _IdempotencySealRace {
        continue;
      } on ExpenseCreationIdempotencyConflictException {
        rethrow;
      } on ArgumentError {
        rethrow;
      } on StateError {
        rethrow;
      } catch (e, st) {
        if (_isSqliteBusyOrLocked(e) && attempt < 7) {
          await Future<void>.delayed(
            Duration(milliseconds: 25 * (attempt + 1)),
          );
          continue;
        }
        debugPrint('[ExpenseCreationService] Error in processCreate: $e\n$st');
        if (e is Exception) rethrow;
        throw Exception('Failed to create expense: ${e.toString()}');
      }
    }

    return db.transaction(() async {
      final existing =
          await db.expenseIdempotencyDao.findByIdempotencyKey(idempotencyKey);
      if (existing != null && existing.fingerprintHash == fingerprintHash) {
        return ExpenseCreationResult(
          expenseRecordId: existing.expenseRecordId,
          idempotentReplay: true,
        );
      }
      throw const ExpenseCreationIdempotencyConflictException();
    });
  }

  /// Writes the expense-create activity log inside the caller transaction.
  /// Uses [activityLogsDao] directly so insert failures propagate and roll back.
  Future<void> _insertExpenseCreationActivityLog({
    required int expenseId,
    required String description,
  }) async {
    final ctx = ActivityContextHolder.current;
    await db.activityLogsDao.insertLog(
      ActivityLogsCompanion.insert(
        activityType: ActivityTypes.expenseCreated,
        category: ActivityCategories.financial,
        severity: ActivitySeverity.info,
        userId: Value(ctx.userId),
        usernameSnapshot: Value(ctx.username),
        roleSnapshot: Value(ctx.roleName),
        sessionId: Value(ctx.sessionId),
        entityType: const Value('expense_record'),
        entityId: Value(expenseId),
        action: 'create',
        title: '\u062a\u0633\u062c\u064a\u0644 \u0645\u0635\u0631\u0648\u0641',
        description: Value(description),
        routeContext: Value(ctx.routeContext),
      ),
    );
  }

  bool _isUniqueIdempotencyKeyViolation(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('expense_idempotency');
  }

  bool _isSqliteBusyOrLocked(Object error) {
    final message = error.toString();
    return message.contains('database is locked') ||
        message.contains('SqliteException(5)');
  }
}