import 'package:drift/drift.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'other_income_creation_fingerprint.dart';
import 'other_income_mutation_fingerprint.dart';
import 'other_income_mutation_in_transaction_writer.dart';
import 'other_income_mutation_save_idempotency_conflict_exception.dart';
import 'other_income_mutation_save_result.dart';

class _IdempotencySealRace implements Exception {}

/// Canonical orchestrator for other income UPDATE and VOID with idempotency (B23).
class OtherIncomeMutationSaveService {
  OtherIncomeMutationSaveService(
    this.db, {
    OtherIncomeMutationInTransactionWriter? writer,
    @visibleForTesting Future<void> Function()? preSealHook,
    @visibleForTesting Future<void> Function()? beforeMutationHook,
    @visibleForTesting Future<void> Function()? testActivityLogHook,
  })  : _writer = writer ?? OtherIncomeMutationInTransactionWriter(db),
        _preSealHook = preSealHook,
        _beforeMutationHook = beforeMutationHook,
        _testActivityLogHook = testActivityLogHook;

  final AppDatabase db;
  final OtherIncomeMutationInTransactionWriter _writer;
  final Future<void> Function()? _preSealHook;
  final Future<void> Function()? _beforeMutationHook;
  final Future<void> Function()? _testActivityLogHook;

  static const int _sqliteBusy = 5;
  static const int _sqliteLocked = 6;
  static const int _sqliteConstraintPrimaryKey = 1555;
  static const int _sqliteConstraintUnique = 2067;

  Future<OtherIncomeMutationSaveResult> processUpdate({
    required String idempotencyKey,
    required String fingerprintHash,
    required int otherIncomeRecordId,
    required int categoryId,
    required double amount,
    required DateTime incomeDate,
    required DateTime receivedAt,
    required String notes,
    required int updatedBy,
    int? sessionId,
  }) async {
    final normalizedIncomeDate =
        OtherIncomeCreationFingerprint.normalizeDate(incomeDate);
    final normalizedReceivedAt =
        OtherIncomeCreationFingerprint.normalizeDate(receivedAt);
    final roundedAmount = OtherIncomeCreationFingerprint.roundAmount(amount);
    final normalizedNotes = OtherIncomeCreationFingerprint.normalizeNotes(notes);

    if (updatedBy <= 0) {
      throw ArgumentError('updatedBy must be positive');
    }
    if (otherIncomeRecordId <= 0) {
      throw ArgumentError('otherIncomeRecordId must be positive');
    }
    if (categoryId <= 0) {
      throw ArgumentError('categoryId must be positive');
    }
    if (roundedAmount <= 0) {
      throw ArgumentError('amount must be positive');
    }

    final category = await db.otherIncomeDao.getCategoryById(categoryId);
    if (category == null) {
      throw StateError('Other income category not found');
    }
    if (!category.isActive) {
      throw StateError('Other income category is not active');
    }

    return _runWithRetry(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fingerprintHash,
      operationType: OtherIncomeMutationFingerprint.operationUpdate,
      otherIncomeRecordId: otherIncomeRecordId,
      work: () async {
        if (_beforeMutationHook != null) {
          await _beforeMutationHook!();
        }

        final existing =
            await db.otherIncomeDao.getIncomeById(otherIncomeRecordId);
        if (existing == null) {
          throw StateError('Other income record not found');
        }
        if (existing.isVoided) {
          throw StateError('Cannot update voided other income');
        }

        final description =
            '${existing.amount.toStringAsFixed(2)} -> ${roundedAmount.toStringAsFixed(2)}';

        await _writer.updateIncomeRowInTransaction(
          otherIncomeRecordId: otherIncomeRecordId,
          categoryId: categoryId,
          amount: roundedAmount,
          incomeDate: normalizedIncomeDate,
          receivedAt: normalizedReceivedAt,
          notes: normalizedNotes,
          sessionId: sessionId,
          createdBy: existing.createdBy,
        );

        if (_testActivityLogHook != null) {
          await _testActivityLogHook!();
        } else {
          await _writer.insertUpdateActivityLog(
            otherIncomeRecordId: otherIncomeRecordId,
            updatedBy: updatedBy,
            description: description,
          );
        }

        return OtherIncomeMutationSaveResult(
          otherIncomeRecordId: otherIncomeRecordId,
          idempotentReplay: false,
        );
      },
    );
  }

  Future<OtherIncomeMutationSaveResult> processVoid({
    required String idempotencyKey,
    required String fingerprintHash,
    required int otherIncomeRecordId,
    required int voidedBy,
  }) async {
    if (voidedBy <= 0) {
      throw ArgumentError('voidedBy must be positive');
    }
    if (otherIncomeRecordId <= 0) {
      throw ArgumentError('otherIncomeRecordId must be positive');
    }

    return _runWithRetry(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fingerprintHash,
      operationType: OtherIncomeMutationFingerprint.operationVoid,
      otherIncomeRecordId: otherIncomeRecordId,
      work: () async {
        if (_beforeMutationHook != null) {
          await _beforeMutationHook!();
        }

        final applied = await _writer.voidIncomeRowInTransaction(
          otherIncomeRecordId: otherIncomeRecordId,
        );
        if (!applied) {
          return OtherIncomeMutationSaveResult(
            otherIncomeRecordId: otherIncomeRecordId,
            idempotentReplay: false,
            alreadyVoided: true,
          );
        }

        if (_testActivityLogHook != null) {
          await _testActivityLogHook!();
        } else {
          await _writer.insertVoidActivityLog(
            otherIncomeRecordId: otherIncomeRecordId,
            voidedBy: voidedBy,
          );
        }

        return OtherIncomeMutationSaveResult(
          otherIncomeRecordId: otherIncomeRecordId,
          idempotentReplay: false,
        );
      },
    );
  }

  Future<OtherIncomeMutationSaveResult> _runWithRetry({
    required String idempotencyKey,
    required String fingerprintHash,
    required String operationType,
    required int otherIncomeRecordId,
    required Future<OtherIncomeMutationSaveResult> Function() work,
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await db.transaction(() async {
          final existing = await db.otherIncomeMutationIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (existing.fingerprintHash != fingerprintHash ||
                existing.operationType != operationType) {
              throw const OtherIncomeMutationSaveIdempotencyConflictException();
            }
            return OtherIncomeMutationSaveResult(
              otherIncomeRecordId: existing.otherIncomeRecordId,
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
            await db.otherIncomeMutationIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              operationType: operationType,
              fingerprintHash: fingerprintHash,
              otherIncomeRecordId: result.otherIncomeRecordId,
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
      } on OtherIncomeMutationSaveIdempotencyConflictException {
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
          '[OtherIncomeMutationSaveService] Error: $e\n$st',
        );
        if (e is Exception) rethrow;
        throw Exception('Failed other income mutation: ${e.toString()}');
      }
    }

    return db.transaction(() async {
      final existing = await db.otherIncomeMutationIdempotencyDao
          .findByIdempotencyKey(idempotencyKey);
      if (existing != null &&
          existing.fingerprintHash == fingerprintHash &&
          existing.operationType == operationType) {
        return OtherIncomeMutationSaveResult(
          otherIncomeRecordId: existing.otherIncomeRecordId,
          idempotentReplay: true,
        );
      }
      throw const OtherIncomeMutationSaveIdempotencyConflictException();
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
    return _sqliteStatementTargetsTable(error, 'other_income_mutation_idempotency');
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
