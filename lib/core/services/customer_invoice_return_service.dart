// lib/core/services/customer_invoice_return_service.dart
//
// B16 — Canonical idempotent entry point for invoice-linked customer returns.

import 'package:flutter/foundation.dart';

import '../activity/activity_categories.dart';
import '../activity/activity_types.dart';
import '../constants/invoice_lifecycle.dart';
import '../database/app_database.dart';
import 'activity_logger_service.dart';
import 'customer_invoice_return_fingerprint.dart';
import 'customer_invoice_return_idempotency_conflict_exception.dart';
import 'customer_invoice_return_posting_result.dart';
import 'partial_return_service.dart';

class _IdempotencySealRace implements Exception {}

class CustomerInvoiceReturnService {
  CustomerInvoiceReturnService(
    this._db, {
    PartialReturnService? partialReturnService,
    @visibleForTesting Future<void> Function()? preSealHook,
  })  : _partialReturnService =
            partialReturnService ?? PartialReturnService(_db),
        _preSealHook = preSealHook;

  @visibleForTesting
  CustomerInvoiceReturnService.withCreditPoster(
    this._db, {
    required CustomerReturnCreditPoster creditPoster,
    Future<void> Function()? preSealHook,
  })  : _partialReturnService = PartialReturnService.withCreditPoster(
          _db,
          creditPoster: creditPoster,
        ),
        _preSealHook = preSealHook;

  final AppDatabase _db;
  final PartialReturnService _partialReturnService;
  final Future<void> Function()? _preSealHook;

  Future<CustomerInvoiceReturnPostingResult> processPartialReturn({
    required String idempotencyKey,
    required int saleInvoiceId,
    required List<CustomerInvoicePartialReturnLine> lines,
    required int returnedByUserId,
    String? note,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('empty partial return lines');
    }

    final inv = await _db.salesDao.getInvoiceById(saleInvoiceId);
    if (inv == null) throw StateError('الفاتورة غير موجودة');

    final fingerprintHash = CustomerInvoiceReturnFingerprint.computePartial(
      customerId: inv.customerId,
      saleInvoiceId: saleInvoiceId,
      lines: lines
          .map(
            (line) => CustomerInvoicePartialReturnLineInput(
              saleItemId: line.saleItemId,
              quantity: line.quantity,
            ),
          )
          .toList(),
      note: note,
    );

    final result = await _runWithIdempotency(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fingerprintHash,
      customerId: inv.customerId,
      saleInvoiceId: saleInvoiceId,
      returnType: CustomerInvoiceReturnType.partial,
      executeFresh: () async {
        final execution =
            await _partialReturnService.executePartialReturnInTransaction(
          saleInvoiceId: saleInvoiceId,
          lines: lines,
          returnedByUserId: returnedByUserId,
          note: note,
        );
        return CustomerInvoiceReturnPostingResult(
          customerReturnId: execution.customerReturnId,
          returnType: CustomerInvoiceReturnType.partial,
          executionPath: CustomerInvoiceExecutionPath.partialBatch,
          primaryReferenceId: execution.primaryReferenceId,
          idempotentReplay: false,
        );
      },
    );

    if (!result.idempotentReplay) {
      await ActivityLoggerService(_db).logWarning(
        activityType: ActivityTypes.returnPartial,
        category: ActivityCategories.returns,
        action: 'partial_return',
        title: 'إرجاع جزئي لفاتورة',
        entityType: 'invoice',
        entityId: saleInvoiceId,
        metadata: {'lines': lines.length, 'note': note},
      );
    }

    return result;
  }

  Future<CustomerInvoiceReturnPostingResult> processFullReturn({
    required String idempotencyKey,
    required int saleInvoiceId,
    required int returnedByUserId,
    required String note,
  }) async {
    final inv = await _db.salesDao.getInvoiceById(saleInvoiceId);
    if (inv == null) throw StateError('الفاتورة غير موجودة');

    final fingerprintHash = CustomerInvoiceReturnFingerprint.computeFull(
      customerId: inv.customerId,
      saleInvoiceId: saleInvoiceId,
      note: note,
    );

    final result = await _runWithIdempotency(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fingerprintHash,
      customerId: inv.customerId,
      saleInvoiceId: saleInvoiceId,
      returnType: CustomerInvoiceReturnType.full,
      executeFresh: () => _executeFullReturnInTransaction(
        saleInvoiceId: saleInvoiceId,
        returnedByUserId: returnedByUserId,
        note: note,
      ),
    );

    if (!result.idempotentReplay) {
      await ActivityLoggerService(_db).logWarning(
        activityType: ActivityTypes.returnFull,
        category: ActivityCategories.returns,
        action: 'full_return',
        title: 'إرجاع كامل لفاتورة',
        entityType: 'invoice',
        entityId: saleInvoiceId,
        metadata: {'note': note},
      );
    }

    return result;
  }

  Future<CustomerInvoiceReturnPostingResult> _executeFullReturnInTransaction({
    required int saleInvoiceId,
    required int returnedByUserId,
    required String note,
  }) async {
    final invNow = await _db.salesDao.getInvoiceById(saleInvoiceId);
    if (invNow == null) throw StateError('الفاتورة غير موجودة');
    if (invNow.invoiceStatus == InvoiceLifecycleStatus.returned) {
      throw StateError('الفاتورة مرتجعة مسبقاً');
    }

    final hasPartialReturns =
        await _db.saleItemReturnsDao.hasAnyReturns(saleInvoiceId);

    if (hasPartialReturns ||
        invNow.invoiceStatus == InvoiceLifecycleStatus.partiallyReturned) {
      final execution =
          await _partialReturnService.executeReturnAllRemainingInTransaction(
        saleInvoiceId: saleInvoiceId,
        returnedByUserId: returnedByUserId,
        note: note,
      );
      return CustomerInvoiceReturnPostingResult(
        customerReturnId: execution.customerReturnId,
        returnType: CustomerInvoiceReturnType.full,
        executionPath: CustomerInvoiceExecutionPath.fullRemaining,
        primaryReferenceId: execution.primaryReferenceId,
        idempotentReplay: false,
      );
    }

    final freshReturnId =
        await _db.returnsDao.executeFreshFullReturnInTransaction(
      invoiceId: saleInvoiceId,
      note: note,
      returnedByUserId: returnedByUserId,
    );

    if (freshReturnId == null) {
      final execution =
          await _partialReturnService.executeReturnAllRemainingInTransaction(
        saleInvoiceId: saleInvoiceId,
        returnedByUserId: returnedByUserId,
        note: note,
      );
      return CustomerInvoiceReturnPostingResult(
        customerReturnId: execution.customerReturnId,
        returnType: CustomerInvoiceReturnType.full,
        executionPath: CustomerInvoiceExecutionPath.fullRemaining,
        primaryReferenceId: execution.primaryReferenceId,
        idempotentReplay: false,
      );
    }

    return CustomerInvoiceReturnPostingResult(
      customerReturnId: freshReturnId,
      returnType: CustomerInvoiceReturnType.full,
      executionPath: CustomerInvoiceExecutionPath.fullFresh,
      primaryReferenceId: freshReturnId,
      idempotentReplay: false,
    );
  }

  Future<CustomerInvoiceReturnPostingResult> _runWithIdempotency({
    required String idempotencyKey,
    required String fingerprintHash,
    required int? customerId,
    required int saleInvoiceId,
    required CustomerInvoiceReturnType returnType,
    required Future<CustomerInvoiceReturnPostingResult> Function() executeFresh,
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await _db.transaction(() async {
          final existing = await _db.customerInvoiceReturnIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (existing.fingerprintHash != fingerprintHash) {
              throw const CustomerInvoiceReturnIdempotencyConflictException();
            }
            return _resultFromExisting(existing);
          }

          final execution = await executeFresh();

          if (_preSealHook != null) {
            await _preSealHook!();
          }

          try {
            await _db.customerInvoiceReturnIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              fingerprintHash: fingerprintHash,
              customerId: customerId,
              saleInvoiceId: saleInvoiceId,
              returnType: returnType == CustomerInvoiceReturnType.partial
                  ? 'partial'
                  : 'full',
              customerReturnId: execution.customerReturnId,
              primaryReferenceId: execution.primaryReferenceId,
              executionPath: execution.executionPath.code,
            );
          } catch (e) {
            if (_isUniqueIdempotencyKeyViolation(e)) {
              throw _IdempotencySealRace();
            }
            rethrow;
          }

          return execution;
        });
      } on _IdempotencySealRace {
        continue;
      } on CustomerInvoiceReturnIdempotencyConflictException {
        rethrow;
      } catch (e, st) {
        if (_isSqliteBusyOrLocked(e) && attempt < 7) {
          await Future<void>.delayed(
            Duration(milliseconds: 25 * (attempt + 1)),
          );
          continue;
        }
        debugPrint('[CustomerInvoiceReturnService] Error: $e\n$st');
        rethrow;
      }
    }

    return _db.transaction(() async {
      final existing = await _db.customerInvoiceReturnIdempotencyDao
          .findByIdempotencyKey(idempotencyKey);
      if (existing != null && existing.fingerprintHash == fingerprintHash) {
        return _resultFromExisting(existing);
      }
      throw const CustomerInvoiceReturnIdempotencyConflictException();
    });
  }

  CustomerInvoiceReturnPostingResult _resultFromExisting(
    CustomerInvoiceReturnIdempotencyData existing,
  ) {
    return CustomerInvoiceReturnPostingResult(
      customerReturnId: existing.customerReturnId,
      returnType: existing.returnType == 'full'
          ? CustomerInvoiceReturnType.full
          : CustomerInvoiceReturnType.partial,
      executionPath:
          CustomerInvoiceExecutionPath.fromCode(existing.executionPath),
      primaryReferenceId: existing.primaryReferenceId,
      idempotentReplay: true,
    );
  }

  bool _isUniqueIdempotencyKeyViolation(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('customer_invoice_return_idempotency');
  }

  bool _isSqliteBusyOrLocked(Object error) {
    final message = error.toString();
    return message.contains('database is locked') ||
        message.contains('SqliteException(5)');
  }
}
