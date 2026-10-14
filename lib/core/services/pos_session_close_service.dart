import 'dart:convert' show jsonEncode;

import 'package:drift/drift.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter/foundation.dart';

import '../activity/activity_categories.dart';
import '../activity/activity_context.dart';
import '../activity/activity_severity.dart';
import '../activity/activity_types.dart';
import '../database/app_database.dart';
import 'pos_session_close_fingerprint.dart';
import 'pos_session_close_idempotency_conflict_exception.dart';
import 'pos_session_close_invalid_closed_by_user_exception.dart';
import 'pos_session_close_result.dart';
import 'pos_session_not_found_exception.dart';

class _CloseConditionalRace implements Exception {}

/// Canonical orchestrator for POS session close (B26).
class PosSessionCloseService {
  PosSessionCloseService(
    this.db, {
    @visibleForTesting Future<void> Function()? beforeConditionalCloseHook,
    @visibleForTesting Future<void> Function()? beforeActivityLogHook,
  })  : _beforeConditionalCloseHook = beforeConditionalCloseHook,
        _beforeActivityLogHook = beforeActivityLogHook;

  final AppDatabase db;
  final Future<void> Function()? _beforeConditionalCloseHook;
  final Future<void> Function()? _beforeActivityLogHook;

  static const int _sqliteBusy = 5;
  static const int _sqliteLocked = 6;

  Future<PosSessionCloseResult> processClose({
    /// UI/correlation only (B26 v51). Replay/conflict uses closed row + fingerprint.
    required String idempotencyKey,
    required int sessionId,
    required double closingCash,
    String? notes,
    int? closedByUserId,
  }) async {
    if (closingCash < 0) {
      throw ArgumentError('closingCash must be non-negative');
    }

    final normalizedNotes = PosSessionCloseFingerprint.normalizeNotes(notes);
    final roundedCash = PosSessionCloseFingerprint.roundClosingCash(closingCash);
    final fingerprintHash = PosSessionCloseFingerprint.compute(
      sessionId: sessionId,
      closingCash: roundedCash,
      notes: normalizedNotes,
      closedByUserId: closedByUserId,
    );

    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await db.transaction(() async {
          final session = await db.salesDao.getSessionById(sessionId);
          if (session == null) {
            throw PosSessionNotFoundException(sessionId: sessionId);
          }

          if (session.isClosed) {
            return _replayOrConflictFromClosedRow(session, fingerprintHash);
          }

          final summary = await db.salesDao.getSessionSummary(sessionId);
          final cashSales = (summary['cash'] as num?)?.toDouble() ?? 0.0;
          final expectedCash = session.openingCash + cashSales;
          final difference = roundedCash - expectedCash;
          final closedAt = DateTime.now();

          if (closedByUserId != null) {
            final user = await db.usersDao.getUserById(closedByUserId);
            if (user == null) {
              throw PosSessionCloseInvalidClosedByUserException(
                closedByUserId: closedByUserId,
              );
            }
          }

          if (_beforeConditionalCloseHook != null) {
            await _beforeConditionalCloseHook!();
          }

          final affected = await db.salesDao.closeOpenSessionIfStillOpen(
            sessionId: sessionId,
            closingCash: roundedCash,
            expectedCashAmount: expectedCash,
            cashDifference: difference,
            closedAt: closedAt,
            closedByUserId: closedByUserId,
            notes: normalizedNotes,
          );

          if (affected == 0) {
            final reread = await db.salesDao.getSessionById(sessionId);
            if (reread == null) {
              throw PosSessionNotFoundException(sessionId: sessionId);
            }
            if (reread.isClosed) {
              return _replayOrConflictFromClosedRow(reread, fingerprintHash);
            }
            throw _CloseConditionalRace();
          }

          if (_beforeActivityLogHook != null) {
            await _beforeActivityLogHook!();
          }
          await _insertSessionCloseActivityLog(
            sessionId: sessionId,
            closingCash: roundedCash,
            expectedCash: expectedCash,
            difference: difference,
          );

          return PosSessionCloseResult(
            sessionId: sessionId,
            idempotentReplay: false,
            closingCash: roundedCash,
            expectedCashAmount: expectedCash,
            cashDifference: difference,
          );
        });
      } on _CloseConditionalRace {
        continue;
      } on PosSessionCloseIdempotencyConflictException {
        rethrow;
      } on PosSessionNotFoundException {
        rethrow;
      } on PosSessionCloseInvalidClosedByUserException {
        rethrow;
      } on ArgumentError {
        rethrow;
      } on StateError {
        rethrow;
      } catch (e, _) {
        if (_isSqliteBusyOrLocked(e) && attempt < 7) {
          await Future<void>.delayed(
            Duration(milliseconds: 25 * (attempt + 1)),
          );
          continue;
        }
        if (e is Exception) rethrow;
        throw Exception('Failed to close POS session: ${e.toString()}');
      }
    }

    throw StateError('POS session close retry budget exhausted');
  }

  PosSessionCloseResult _replayOrConflictFromClosedRow(
    PosSession session,
    String fingerprintHash,
  ) {
    final storedHash = PosSessionCloseFingerprint.fromClosedSession(
      sessionId: session.id,
      closingCash: session.closingCash ?? 0,
      notes: session.notes,
      closedByUserId: session.closedByUserId,
    );
    if (storedHash != fingerprintHash) {
      throw const PosSessionCloseIdempotencyConflictException();
    }
    return PosSessionCloseResult(
      sessionId: session.id,
      idempotentReplay: true,
      closingCash: session.closingCash ?? 0,
      expectedCashAmount: session.expectedCashAmount ?? 0,
      cashDifference: session.cashDifference ?? 0,
    );
  }

  Future<void> _insertSessionCloseActivityLog({
    required int sessionId,
    required double closingCash,
    required double expectedCash,
    required double difference,
  }) async {
    final ctx = ActivityContextHolder.current;
    await db.activityLogsDao.insertLog(
      ActivityLogsCompanion.insert(
        activityType: ActivityTypes.sessionClosed,
        category: ActivityCategories.sessions,
        severity: ActivitySeverity.info,
        userId: Value(ctx.userId),
        usernameSnapshot: Value(ctx.username),
        roleSnapshot: Value(ctx.roleName),
        sessionId: Value(ctx.sessionId),
        entityType: const Value('pos_session'),
        entityId: Value(sessionId),
        action: 'close',
        title: 'إغلاق جلسة نقطة البيع',
        metadataJson: Value(
          '{"closingCash":$closingCash,"expectedCash":$expectedCash,"difference":$difference}',
        ),
        routeContext: Value(ctx.routeContext),
      ),
    );
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
