import 'package:drift/drift.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'expense_creation_fingerprint.dart';
import 'expense_mutation_fingerprint.dart';
import 'expense_mutation_in_transaction_writer.dart';
import 'expense_mutation_save_idempotency_conflict_exception.dart';
import 'expense_mutation_save_result.dart';

class _IdempotencySealRace implements Exception {}

/// Canonical orchestrator for expense UPDATE and VOID with idempotency (B22).
class ExpenseMutationSaveService {
  ExpenseMutationSaveService(
    this.db, {
    ExpenseMutationInTransactionWriter? writer,
    @visibleForTesting Future<void> Function()? preSealHook,
    @visibleForTesting Future<void> Function()? beforeMutationHook,
    @visibleForTesting Future<void> Function()? testActivityLogHook,
  })  : _writer = writer ?? ExpenseMutationInTransactionWriter(db),
        _preSealHook = preSealHook,
        _beforeMutationHook = beforeMutationHook,
        _testActivityLogHook = testActivityLogHook;

  final AppDatabase db;
  final ExpenseMutationInTransactionWriter _writer;
  final Future<void> Function()? _preSealHook;
  final Future<void> Function()? _beforeMutationHook;
  final Future<void> Function()? _testActivityLogHook;

  static const int _sqliteBusy = 5;
  static const int _sqliteLocked = 6;
  static const int _sqliteConstraintPrimaryKey = 1555;
  static const int _sqliteConstraintUnique = 2067;

  Future<ExpenseMutationSaveResult> processUpdate({
    required String idempotencyKey,
    required String fingerprintHash,
    required int expenseId,
    required int categoryId,
    required double amount,
    required DateTime expenseDate,
    required DateTime paidAt,
    required String notes,
    required int updatedBy,
    int? sessionId,
  }) async {
    final normalizedExpenseDate =
        ExpenseCreationFingerprint.normalizeDate(expenseDate);
    final normalizedPaidAt = ExpenseCreationFingerprint.normalizeDate(paidAt);
    final roundedAmount = ExpenseCreationFingerprint.roundAmount(amount);
    final normalizedNotes = ExpenseCreationFingerprint.normalizeNotes(notes);

    if (updatedBy <= 0) {
      throw ArgumentError('updatedBy must be positive');
    }
    if (expenseId <= 0) {
      throw ArgumentError('expenseId must be positive');
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

    return _runWithRetry(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fingerprintHash,
      operationType: ExpenseMutationFingerprint.operationUpdate,
      expenseId: expenseId,
      work: () async {
        if (_beforeMutationHook != null) {
          await _beforeMutationHook!();
        }

        final existing = await db.expensesDao.getExpenseById(expenseId);
        if (existing == null) {
          throw StateError('Expense record not found');
        }
        if (existing.isVoided) {
          throw StateError('Cannot update voided expense');
        }

        final description =
            '${existing.amount.toStringAsFixed(2)} -> ${roundedAmount.toStringAsFixed(2)}';

        await _writer.updateExpenseRowInTransaction(
          expenseId: expenseId,
          categoryId: categoryId,
          amount: roundedAmount,
          expenseDate: normalizedExpenseDate,
          paidAt: normalizedPaidAt,
          notes: normalizedNotes,
          sessionId: sessionId,
          createdBy: existing.createdBy,
        );

        if (_testActivityLogHook != null) {
          await _testActivityLogHook!();
        } else {
          await _writer.insertUpdateActivityLog(
            expenseId: expenseId,
            updatedBy: updatedBy,
            description: description,
          );
        }

        return ExpenseMutationSaveResult(
          expenseRecordId: expenseId,
          idempotentReplay: false,
        );
      },
    );
  }

  Future<ExpenseMutationSaveResult> processVoid({
    required String idempotencyKey,
    required String fingerprintHash,
    required int expenseId,
    required int voidedBy,
  }) async {
    if (voidedBy <= 0) {
      throw ArgumentError('voidedBy must be positive');
    }
    if (expenseId <= 0) {
      throw ArgumentError('expenseId must be positive');
    }

    return _runWithRetry(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fingerprintHash,
      operationType: ExpenseMutationFingerprint.operationVoid,
      expenseId: expenseId,
      work: () async {
        if (_beforeMutationHook != null) {
          await _beforeMutationHook!();
        }

        final applied = await _writer.voidExpenseRowInTransaction(
          expenseId: expenseId,
        );
        if (!applied) {
          return ExpenseMutationSaveResult(
            expenseRecordId: expenseId,
            idempotentReplay: false,
            alreadyVoided: true,
          );
        }

        if (_testActivityLogHook != null) {
          await _testActivityLogHook!();
        } else {
          await _writer.insertVoidActivityLog(
            expenseId: expenseId,
            voidedBy: voidedBy,
          );
        }

        return ExpenseMutationSaveResult(
          expenseRecordId: expenseId,
          idempotentReplay: false,
        );
      },
    );
  }

  Future<ExpenseMutationSaveResult> _runWithRetry({
    required String idempotencyKey,
    required String fingerprintHash,
    required String operationType,
    required int expenseId,
    required Future<ExpenseMutationSaveResult> Function() work,
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await db.transaction(() async {
          final existing = await db.expenseMutationIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (existing.fingerprintHash != fingerprintHash ||
                existing.operationType != operationType) {
              throw const ExpenseMutationSaveIdempotencyConflictException();
            }
            return ExpenseMutationSaveResult(
              expenseRecordId: existing.expenseRecordId,
              idempotentReplay: true,
            );
          }

          final result = await work();

          if (result.alreadyVoided) {
            return result;
          }

          if (_preSealHook != null) {
            await _preSealHook!();
          }

          try {
            await db.expenseMutationIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              operationType: operationType,
              fingerprintHash: fingerprintHash,
              expenseRecordId: result.expenseRecordId,
            );
          } catch (e) {
            if (_isUniqueIdempotencyKeyViolation(e)) {
              throw _IdempotencySealRace();
            }
            rethrow;
          }

          return result;
        });
      } on _IdempotencySealRace {
        continue;
      } on ExpenseMutationSaveIdempotencyConflictException {
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
        debugPrint(
          '[ExpenseMutationSaveService] Error: $e\n$st',
        );
        if (e is Exception) rethrow;
        throw Exception('Failed expense mutation: ${e.toString()}');
      }
    }

    return db.transaction(() async {
      final existing = await db.expenseMutationIdempotencyDao
          .findByIdempotencyKey(idempotencyKey);
      if (existing != null &&
          existing.fingerprintHash == fingerprintHash &&
          existing.operationType == operationType) {
        return ExpenseMutationSaveResult(
          expenseRecordId: existing.expenseRecordId,
          idempotentReplay: true,
        );
      }
      throw const ExpenseMutationSaveIdempotencyConflictException();
    });
  }

  bool _isUniqueIdempotencyKeyViolation(Object error) {
    if (error is! SqliteException) {
      return false;
    }
    final extended = error.extendedResultCode;
    if (extended != _sqliteConstraintPrimaryKey &&
        extended != _sqliteConstraintUnique) {
      return false;
    }
    return _sqliteStatementTargetsTable(error, 'expense_mutation_idempotency');
  }

  bool _sqliteStatementTargetsTable(Object error, String tableName) {
    if (error is! SqliteException) {
      return false;
    }
    final statement = error.causingStatement;
    if (statement != null && statement.contains(tableName)) {
      return true;
    }
    return error.message.contains(tableName);
  }

  bool _isSqliteBusyOrLocked(Object error) {
    if (error is SqliteException) {
      return error.resultCode == _sqliteBusy ||
          error.resultCode == _sqliteLocked;
    }
    final message = error.toString();
    return message.contains('database is locked') ||
        message.contains('SqliteException(5)') ||
        message.contains('SqliteException(6)');
  }
}
