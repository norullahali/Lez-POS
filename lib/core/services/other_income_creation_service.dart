import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../activity/activity_categories.dart';
import '../activity/activity_context.dart';
import '../activity/activity_severity.dart';
import '../activity/activity_types.dart';
import '../database/app_database.dart';
import 'other_income_creation_fingerprint.dart';
import 'other_income_creation_idempotency_conflict_exception.dart';
import 'other_income_creation_result.dart';

class _IdempotencySealRace implements Exception {}

/// Canonical orchestrator for other income creation with persistent idempotency (B19).
class OtherIncomeCreationService {
  OtherIncomeCreationService(
    this.db, {
    @visibleForTesting Future<void> Function()? preSealHook,
    @visibleForTesting Future<void> Function()? beforeIncomeInsertHook,
  })  : _preSealHook = preSealHook,
        _beforeIncomeInsertHook = beforeIncomeInsertHook;

  final AppDatabase db;
  final Future<void> Function()? _preSealHook;
  final Future<void> Function()? _beforeIncomeInsertHook;

  /// Processes other income creation with idempotency.
  ///
  /// [idempotencyKey] identifies the operation. Retries with the same key and
  /// identical [fingerprintHash] replay the original income without mutation.
  Future<OtherIncomeCreationResult> processCreate({
    required String idempotencyKey,
    required String fingerprintHash,
    required int categoryId,
    required double amount,
    required DateTime incomeDate,
    required DateTime receivedAt,
    required String notes,
    required int createdBy,
    int? sessionId,
  }) async {
    final normalizedIncomeDate =
        OtherIncomeCreationFingerprint.normalizeDate(incomeDate);
    final normalizedReceivedAt =
        OtherIncomeCreationFingerprint.normalizeDate(receivedAt);
    final roundedAmount = OtherIncomeCreationFingerprint.roundAmount(amount);
    final normalizedNotes = OtherIncomeCreationFingerprint.normalizeNotes(notes);

    if (createdBy <= 0) {
      throw ArgumentError('createdBy must be positive');
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

    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await db.transaction(() async {
          final existing = await db.otherIncomeIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (existing.fingerprintHash != fingerprintHash) {
              throw const OtherIncomeCreationIdempotencyConflictException();
            }
            return OtherIncomeCreationResult(
              otherIncomeRecordId: existing.otherIncomeRecordId,
              idempotentReplay: true,
            );
          }

          if (_beforeIncomeInsertHook != null) {
            await _beforeIncomeInsertHook!();
          }

          final incomeId = await db.otherIncomeDao.createIncomeInTransaction(
            OtherIncomeRecordsCompanion(
              categoryId: Value(categoryId),
              amount: Value(roundedAmount),
              incomeDate: Value(normalizedIncomeDate),
              receivedAt: Value(normalizedReceivedAt),
              notes: Value(normalizedNotes),
              sessionId: Value(sessionId),
              createdBy: Value(createdBy),
            ),
          );

          await _insertOtherIncomeCreationActivityLog(
            incomeId: incomeId,
            description: roundedAmount.toStringAsFixed(2),
          );

          if (_preSealHook != null) {
            await _preSealHook!();
          }

          try {
            await db.otherIncomeIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              fingerprintHash: fingerprintHash,
              otherIncomeRecordId: incomeId,
            );
          } catch (e) {
            if (_isUniqueIdempotencyKeyViolation(e)) {
              throw _IdempotencySealRace();
            }
            rethrow;
          }

          return OtherIncomeCreationResult(
            otherIncomeRecordId: incomeId,
            idempotentReplay: false,
          );
        });
      } on _IdempotencySealRace {
        continue;
      } on OtherIncomeCreationIdempotencyConflictException {
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
        debugPrint('[OtherIncomeCreationService] Error in processCreate: $e\n$st');
        if (e is Exception) rethrow;
        throw Exception('Failed to create other income: ${e.toString()}');
      }
    }

    return db.transaction(() async {
      final existing = await db.otherIncomeIdempotencyDao
          .findByIdempotencyKey(idempotencyKey);
      if (existing != null && existing.fingerprintHash == fingerprintHash) {
        return OtherIncomeCreationResult(
          otherIncomeRecordId: existing.otherIncomeRecordId,
          idempotentReplay: true,
        );
      }
      throw const OtherIncomeCreationIdempotencyConflictException();
    });
  }

  /// Writes the other-income-create activity log inside the caller transaction.
  /// Uses [activityLogsDao] directly so insert failures propagate and roll back.
  Future<void> _insertOtherIncomeCreationActivityLog({
    required int incomeId,
    required String description,
  }) async {
    final ctx = ActivityContextHolder.current;
    await db.activityLogsDao.insertLog(
      ActivityLogsCompanion.insert(
        activityType: ActivityTypes.incomeCreated,
        category: ActivityCategories.financial,
        severity: ActivitySeverity.info,
        userId: Value(ctx.userId),
        usernameSnapshot: Value(ctx.username),
        roleSnapshot: Value(ctx.roleName),
        sessionId: Value(ctx.sessionId),
        entityType: const Value('other_income_record'),
        entityId: Value(incomeId),
        action: 'create',
        title: '\u062a\u0633\u062c\u064a\u0644 \u0625\u064a\u0631\u0627\u062f',
        description: Value(description),
        routeContext: Value(ctx.routeContext),
      ),
    );
  }

  bool _isUniqueIdempotencyKeyViolation(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('other_income_idempotency');
  }

  bool _isSqliteBusyOrLocked(Object error) {
    final message = error.toString();
    return message.contains('database is locked') ||
        message.contains('SqliteException(5)');
  }
}