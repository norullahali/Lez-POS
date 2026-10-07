import 'package:flutter/foundation.dart';
import 'package:drift/native.dart' show SqliteException;

import '../database/app_database.dart';
import 'opening_stock_in_transaction_writer.dart';
import 'opening_stock_live_activity_exception.dart';
import 'opening_stock_product_already_opened_exception.dart';
import 'opening_stock_save_fingerprint.dart';
import 'opening_stock_save_idempotency_conflict_exception.dart';
import 'opening_stock_save_result.dart';

class _OpeningStockSealRace implements Exception {}

/// Canonical orchestrator for bulk opening stock save with idempotency (B20).
class OpeningStockSaveService {
  OpeningStockSaveService(
    this.db, {
    OpeningStockInTransactionWriter? writer,
    @visibleForTesting Future<void> Function()? preSealHook,
    @visibleForTesting Future<void> Function()? beforeProductInsertHook,
    @visibleForTesting Future<void> Function()? beforeLogInsertHook,
    @visibleForTesting Future<void> Function()? afterEligibilityCheckHook,
  })  : _writer = writer ?? OpeningStockInTransactionWriter(db),
        _preSealHook = preSealHook,
        _beforeProductInsertHook = beforeProductInsertHook,
        _beforeLogInsertHook = beforeLogInsertHook,
        _afterEligibilityCheckHook = afterEligibilityCheckHook;

  final AppDatabase db;
  final OpeningStockInTransactionWriter _writer;
  final Future<void> Function()? _preSealHook;
  final Future<void> Function()? _beforeProductInsertHook;
  final Future<void> Function()? _beforeLogInsertHook;
  final Future<void> Function()? _afterEligibilityCheckHook;

  static const int _sqliteBusy = 5;
  static const int _sqliteLocked = 6;
  static const int _sqliteConstraintPrimaryKey = 1555;
  static const int _sqliteConstraintUnique = 2067;

  Future<OpeningStockSaveResult> processSave({
    required String idempotencyKey,
    required String fingerprintHash,
    required List<OpeningStockFingerprintProduct> products,
    required int createdBy,
  }) async {
    if (createdBy <= 0) {
      throw ArgumentError('createdBy must be positive');
    }

    final normalizedProducts =
        OpeningStockSaveFingerprint.normalizeProducts(products);

    for (final product in normalizedProducts) {
      final row = await db.productsDao.getProductById(product.productId);
      if (row == null) {
        throw StateError('Product not found');
      }
      if (!row.isActive) {
        throw StateError('Product is not active');
      }
    }

    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await _runImmediateTransaction(() async {
          final existing = await db.openingStockIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (existing.fingerprintHash != fingerprintHash) {
              throw const OpeningStockSaveIdempotencyConflictException();
            }
            return const OpeningStockSaveResult(
              sealedProductIds: [],
              idempotentReplay: true,
            );
          }

          final sealedProductIds = <int>[];
          for (final product in normalizedProducts) {
            await _assertProductCanOpenInTransaction(product.productId);

            if (_afterEligibilityCheckHook != null) {
              await _afterEligibilityCheckHook!();
            }

            if (_beforeProductInsertHook != null) {
              await _beforeProductInsertHook!();
            }

            await _writer.insertOpeningStock(
              productId: product.productId,
              quantity: product.quantity,
              unitCost: product.unitCost,
              createdBy: createdBy,
            );

            try {
              await db.productOpeningStockSealsDao.insertSeal(
                productId: product.productId,
                quantity: product.quantity,
                unitCost: product.unitCost,
                idempotencyKey: idempotencyKey,
                createdBy: createdBy,
              );
            } catch (e) {
              if (_isUniqueProductSealViolation(e)) {
                throw OpeningStockProductAlreadyOpenedException(
                  product.productId,
                );
              }
              rethrow;
            }

            sealedProductIds.add(product.productId);
          }

          if (_beforeLogInsertHook != null) {
            await _beforeLogInsertHook!();
          }

          await db.logsDao.insertLog(
            userId: createdBy,
            actionType: 'OPENING_STOCK_SAVE',
            details:
                'Saved opening stock for ${normalizedProducts.length} products.',
          );

          if (_preSealHook != null) {
            await _preSealHook!();
          }

          try {
            await db.openingStockIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              fingerprintHash: fingerprintHash,
            );
          } catch (e) {
            if (_isUniqueBulkIdempotencyViolation(e)) {
              throw _OpeningStockSealRace();
            }
            rethrow;
          }

          return OpeningStockSaveResult(
            sealedProductIds: sealedProductIds,
            idempotentReplay: false,
          );
        });
      } on _OpeningStockSealRace {
        continue;
      } on OpeningStockSaveIdempotencyConflictException {
        rethrow;
      } on OpeningStockProductAlreadyOpenedException {
        rethrow;
      } on OpeningStockLiveActivityException {
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
        debugPrint('[OpeningStockSaveService] Error in processSave: $e\n$st');
        if (e is Exception) rethrow;
        throw Exception('Failed to save opening stock: ${e.toString()}');
      }
    }

    return db.transaction(() async {
      final existing = await db.openingStockIdempotencyDao
          .findByIdempotencyKey(idempotencyKey);
      if (existing != null && existing.fingerprintHash == fingerprintHash) {
        return const OpeningStockSaveResult(
          sealedProductIds: [],
          idempotentReplay: true,
        );
      }
      throw const OpeningStockSaveIdempotencyConflictException();
    });
  }

  /// Acquires the SQLite write lock before eligibility reads/mutations (B20-R1).
  ///
  /// Drift's default [AppDatabase.transaction] uses `BEGIN TRANSACTION` (DEFERRED),
  /// which can observe a stale WAL snapshot under multi-connection concurrency.
  /// `BEGIN IMMEDIATE` reserves the write lock up front so competing writers on
  /// other connections block until this bulk opening operation completes.
  Future<T> _runImmediateTransaction<T>(Future<T> Function() action) async {
    await db.customStatement('BEGIN IMMEDIATE');
    try {
      final result = await action();
      await db.customStatement('COMMIT');
      return result;
    } catch (e) {
      try {
        await db.customStatement('ROLLBACK');
      } catch (_) {
        // Ignore rollback failures after the original error.
      }
      rethrow;
    }
  }

  Future<void> _assertProductCanOpenInTransaction(int productId) async {
    final seal =
        await db.productOpeningStockSealsDao.findByProductId(productId);
    if (seal != null) {
      throw OpeningStockProductAlreadyOpenedException(productId);
    }

    if (await _writer.hasLiveInventoryActivity(productId)) {
      throw OpeningStockLiveActivityException(productId);
    }
  }

  bool _isUniqueConstraintViolation(Object error) {
    if (error is! SqliteException) {
      return false;
    }
    final extended = error.extendedResultCode;
    return extended == _sqliteConstraintPrimaryKey ||
        extended == _sqliteConstraintUnique;
  }

  bool _isUniqueBulkIdempotencyViolation(Object error) {
    if (!_isUniqueConstraintViolation(error)) {
      return false;
    }
    return _sqliteStatementTargetsTable(error, 'opening_stock_idempotency');
  }

  bool _isUniqueProductSealViolation(Object error) {
    if (!_isUniqueConstraintViolation(error)) {
      return false;
    }
    return _sqliteStatementTargetsTable(error, 'product_opening_stock_seals');
  }

  bool _sqliteStatementTargetsTable(Object error, String tableName) {
    if (error is! SqliteException) {
      return false;
    }
    final statement = error.causingStatement;
    if (statement != null && statement.contains(tableName)) {
      return true;
    }
    // Narrow fallback when the driver omits causingStatement.
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
