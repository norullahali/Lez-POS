import 'dart:convert' show jsonEncode;

import 'package:drift/drift.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter/foundation.dart';

import '../activity/activity_categories.dart';
import '../activity/activity_context.dart';
import '../activity/activity_severity.dart';
import '../activity/activity_types.dart';
import '../database/app_database.dart';
import 'pos_session_already_open_exception.dart';
import 'pos_session_open_fingerprint.dart';
import 'pos_session_open_idempotency_conflict_exception.dart';
import 'pos_session_open_result.dart';

class _IdempotencySealRace implements Exception {}

/// Canonical orchestrator for POS session open (B25).
class PosSessionOpenService {
  PosSessionOpenService(
    this.db, {
    @visibleForTesting Future<void> Function()? afterIdempotencyLookupHook,
    @visibleForTesting Future<void> Function()? beforeActivityLogHook,
    @visibleForTesting Future<void> Function()? beforeSealHook,
  })  : _afterIdempotencyLookupHook = afterIdempotencyLookupHook,
        _beforeActivityLogHook = beforeActivityLogHook,
        _beforeSealHook = beforeSealHook;

  final AppDatabase db;
  final Future<void> Function()? _afterIdempotencyLookupHook;
  final Future<void> Function()? _beforeActivityLogHook;
  final Future<void> Function()? _beforeSealHook;

  static const int _sqliteBusy = 5;
  static const int _sqliteLocked = 6;
  static const int _sqliteConstraintUnique = 2067;

  Future<PosSessionOpenResult> processOpen({
    required String idempotencyKey,
    required String cashierName,
    required double openingCash,
    int? createdByUserId,
  }) async {
    if (openingCash < 0) {
      throw ArgumentError('openingCash must be non-negative');
    }

    final roundedCash = PosSessionOpenFingerprint.roundOpeningCash(openingCash);
    final fingerprintHash = PosSessionOpenFingerprint.compute(
      openingCash: roundedCash,
      createdByUserId: createdByUserId,
    );

    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await db.transaction(() async {
          final existing = await db.posSessionOpenIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (existing.fingerprintHash != fingerprintHash) {
              throw const PosSessionOpenIdempotencyConflictException();
            }
            return PosSessionOpenResult(
              sessionId: existing.posSessionId,
              idempotentReplay: true,
            );
          }

          if (_afterIdempotencyLookupHook != null) {
            await _afterIdempotencyLookupHook!();
          }

          final sessionId = await _insertOpenSessionRow(
            cashierName: cashierName,
            openingCash: roundedCash,
            createdByUserId: createdByUserId,
          );

          if (_beforeActivityLogHook != null) {
            await _beforeActivityLogHook!();
          } else {
            await _insertSessionOpenActivityLog(
              sessionId: sessionId,
              cashierName: cashierName,
              openingCash: roundedCash,
            );
          }

          if (_beforeSealHook != null) {
            await _beforeSealHook!();
          }

          try {
            await db.posSessionOpenIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              fingerprintHash: fingerprintHash,
              posSessionId: sessionId,
              openingCash: roundedCash,
              createdByUserId: createdByUserId,
            );
          } catch (e) {
            if (_isUniqueIdempotencyKeyViolation(e)) {
              throw _IdempotencySealRace();
            }
            rethrow;
          }

          return PosSessionOpenResult(
            sessionId: sessionId,
            idempotentReplay: false,
          );
        });
      } on _IdempotencySealRace {
        continue;
      } on PosSessionOpenIdempotencyConflictException {
        rethrow;
      } on PosSessionAlreadyOpenException {
        rethrow;
      } on ArgumentError {
        rethrow;
      } on StateError {
        rethrow;
      } catch (e, st) {
        if (_isSingleOpenSessionUniqueViolation(e)) {
          return await _resolveAfterSingleOpenUniqueViolation(
            idempotencyKey: idempotencyKey,
            fingerprintHash: fingerprintHash,
            originalError: e,
          );
        }
        if (_isSqliteBusyOrLocked(e) && attempt < 7) {
          await Future<void>.delayed(
            Duration(milliseconds: 25 * (attempt + 1)),
          );
          continue;
        }
        debugPrint('[PosSessionOpenService] Error in processOpen: $e\n$st');
        if (e is Exception) rethrow;
        throw Exception('Failed to open POS session: ${e.toString()}');
      }
    }

    return db.transaction(() async {
      final existing = await db.posSessionOpenIdempotencyDao
          .findByIdempotencyKey(idempotencyKey);
      if (existing != null && existing.fingerprintHash == fingerprintHash) {
        return PosSessionOpenResult(
          sessionId: existing.posSessionId,
          idempotentReplay: true,
        );
      }
      throw const PosSessionOpenIdempotencyConflictException();
    });
  }

  Future<int> _insertOpenSessionRow({
    required String cashierName,
    required double openingCash,
    int? createdByUserId,
  }) async {
    return db.salesDao.insertOpenSessionRow(
      PosSessionsCompanion(
        cashierName: Value(cashierName),
        openingCash: Value(openingCash),
        createdByUserId: Value(createdByUserId),
        openedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<PosSessionOpenResult> _resolveAfterSingleOpenUniqueViolation({
    required String idempotencyKey,
    required String fingerprintHash,
    required Object originalError,
  }) async {
    final existing = await db.posSessionOpenIdempotencyDao
        .findByIdempotencyKey(idempotencyKey);
    if (existing != null) {
      if (existing.fingerprintHash != fingerprintHash) {
        throw const PosSessionOpenIdempotencyConflictException();
      }
      return PosSessionOpenResult(
        sessionId: existing.posSessionId,
        idempotentReplay: true,
      );
    }

    final open = await db.salesDao.getOpenSession();
    if (open != null) {
      throw PosSessionAlreadyOpenException(existingSessionId: open.id);
    }
    if (originalError is Exception) {
      throw originalError;
    }
    throw Exception(originalError.toString());
  }

  Future<void> _insertSessionOpenActivityLog({
    required int sessionId,
    required String cashierName,
    required double openingCash,
  }) async {
    final ctx = ActivityContextHolder.current;
    await db.activityLogsDao.insertLog(
      ActivityLogsCompanion.insert(
        activityType: ActivityTypes.sessionOpened,
        category: ActivityCategories.sessions,
        severity: ActivitySeverity.info,
        userId: Value(ctx.userId),
        usernameSnapshot: Value(ctx.username),
        roleSnapshot: Value(ctx.roleName),
        sessionId: Value(ctx.sessionId),
        entityType: const Value('pos_session'),
        entityId: Value(sessionId),
        action: 'open',
        title: 'فتح جلسة نقطة البيع',
        metadataJson: Value(
          '{"cashierName":${jsonEncode(cashierName)},"openingCash":$openingCash}',
        ),
        routeContext: Value(ctx.routeContext),
      ),
    );
  }

  bool _isSingleOpenSessionUniqueViolation(Object error) {
    if (error is SqliteException && error.extendedResultCode == _sqliteConstraintUnique) {
      final message = error.message;
      if (message.contains('uq_pos_sessions_one_open')) return true;
    }
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('uq_pos_sessions_one_open');
  }

  bool _isUniqueIdempotencyKeyViolation(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('pos_session_open_idempotency');
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
