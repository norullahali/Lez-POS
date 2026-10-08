import 'package:drift/drift.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter/foundation.dart';

import '../activity/activity_categories.dart';
import '../activity/activity_context.dart';
import '../activity/activity_severity.dart';
import '../activity/activity_types.dart';
import '../database/app_database.dart';
import 'stock_adjustment_in_transaction_writer.dart';
import 'stock_adjustment_save_fingerprint.dart';
import 'stock_adjustment_save_idempotency_conflict_exception.dart';
import 'stock_adjustment_save_result.dart';

class _IdempotencySealRace implements Exception {}

/// Canonical orchestrator for stock adjustment save with idempotency (B21).
class StockAdjustmentSaveService {
  StockAdjustmentSaveService(
    this.db, {
    StockAdjustmentInTransactionWriter? writer,
    @visibleForTesting Future<void> Function()? preSealHook,
    @visibleForTesting Future<void> Function()? beforeAdjustmentHook,
    @visibleForTesting Future<void> Function()? testActivityLogHook,
  })  : _writer = writer ?? StockAdjustmentInTransactionWriter(db),
        _preSealHook = preSealHook,
        _beforeAdjustmentHook = beforeAdjustmentHook,
        _testActivityLogHook = testActivityLogHook;

  final AppDatabase db;
  final StockAdjustmentInTransactionWriter _writer;
  final Future<void> Function()? _preSealHook;
  final Future<void> Function()? _beforeAdjustmentHook;
  final Future<void> Function()? _testActivityLogHook;

  static const int _sqliteBusy = 5;
  static const int _sqliteLocked = 6;
  static const int _sqliteConstraintPrimaryKey = 1555;
  static const int _sqliteConstraintUnique = 2067;

  Future<StockAdjustmentSaveResult> processSave({
    required String idempotencyKey,
    required String fingerprintHash,
    required int productId,
    required double quantityChange,
    required String adjustmentType,
    required String reason,
    String note = '',
    required int createdBy,
  }) async {
    final roundedQuantity =
        StockAdjustmentSaveFingerprint.roundQuantity(quantityChange);
    final normalizedReason =
        StockAdjustmentSaveFingerprint.normalizeReason(reason);
    final normalizedNote = StockAdjustmentSaveFingerprint.normalizeNote(note);

    if (createdBy <= 0) {
      throw ArgumentError('createdBy must be positive');
    }
    if (productId <= 0) {
      throw ArgumentError('productId must be positive');
    }
    if (roundedQuantity == 0) {
      throw ArgumentError('quantityChange must be non-zero');
    }

    final product = await db.productsDao.getProductById(productId);
    if (product == null) {
      throw StateError('Product not found');
    }
    if (!product.isActive) {
      throw StateError('Product is not active');
    }

    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await db.transaction(() async {
          final existing = await db.stockAdjustmentIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (existing.fingerprintHash != fingerprintHash) {
              throw const StockAdjustmentSaveIdempotencyConflictException();
            }
            return StockAdjustmentSaveResult(
              stockAdjustmentId: existing.stockAdjustmentId,
              idempotentReplay: true,
            );
          }

          if (_beforeAdjustmentHook != null) {
            await _beforeAdjustmentHook!();
          }

          final adjustmentId = await _writer.applyAdjustmentInTransaction(
            productId: productId,
            quantityChange: roundedQuantity,
            adjustmentType: adjustmentType,
            reason: normalizedReason,
            note: normalizedNote,
            createdByUserId: createdBy,
          );

          if (_testActivityLogHook != null) {
            await _testActivityLogHook!();
          } else {
            await _insertAdjustmentActivityLog(
              adjustmentId: adjustmentId,
              productId: productId,
              quantityChange: roundedQuantity,
              adjustmentType: adjustmentType,
              reason: normalizedReason,
              createdBy: createdBy,
            );
          }

          if (_preSealHook != null) {
            await _preSealHook!();
          }

          try {
            await db.stockAdjustmentIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              fingerprintHash: fingerprintHash,
              stockAdjustmentId: adjustmentId,
            );
          } catch (e) {
            if (_isUniqueIdempotencyKeyViolation(e)) {
              throw _IdempotencySealRace();
            }
            rethrow;
          }

          return StockAdjustmentSaveResult(
            stockAdjustmentId: adjustmentId,
            idempotentReplay: false,
          );
        });
      } on _IdempotencySealRace {
        continue;
      } on StockAdjustmentSaveIdempotencyConflictException {
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
          '[StockAdjustmentSaveService] Error in processSave: $e\n$st',
        );
        if (e is Exception) rethrow;
        throw Exception('Failed to save stock adjustment: ${e.toString()}');
      }
    }

    return db.transaction(() async {
      final existing = await db.stockAdjustmentIdempotencyDao
          .findByIdempotencyKey(idempotencyKey);
      if (existing != null && existing.fingerprintHash == fingerprintHash) {
        return StockAdjustmentSaveResult(
          stockAdjustmentId: existing.stockAdjustmentId,
          idempotentReplay: true,
        );
      }
      throw const StockAdjustmentSaveIdempotencyConflictException();
    });
  }

  Future<void> _insertAdjustmentActivityLog({
    required int adjustmentId,
    required int productId,
    required double quantityChange,
    required String adjustmentType,
    required String reason,
    required int createdBy,
  }) async {
    final ctx = ActivityContextHolder.current;
    await db.activityLogsDao.insertLog(
      ActivityLogsCompanion.insert(
        activityType: ActivityTypes.stockAdjusted,
        category: ActivityCategories.inventory,
        severity: ActivitySeverity.warning,
        userId: Value(createdBy),
        usernameSnapshot: Value(ctx.username),
        roleSnapshot: Value(ctx.roleName),
        sessionId: Value(ctx.sessionId),
        entityType: const Value('stock_adjustment'),
        entityId: Value(adjustmentId),
        action: 'adjust',
        title: '\u062a\u0633\u0648\u064a\u0629 \u0645\u062e\u0632\u0648\u0646',
        description: Value(
          'product=$productId qty=$quantityChange type=$adjustmentType reason=$reason',
        ),
        routeContext: Value(ctx.routeContext),
      ),
    );
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
    return _sqliteStatementTargetsTable(error, 'stock_adjustment_idempotency');
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
