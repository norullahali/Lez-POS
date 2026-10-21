import '../../core/services/supplier_payment_fingerprint.dart';
import '../../core/services/supplier_payment_idempotency_conflict_exception.dart';
import '../../core/services/supplier_payment_result.dart';

/// Canonical operation-intent fingerprint for supplier payment UI (B35).
///
/// Must match [SupplierAccountService.processPayment] input normalization.
String computeSupplierPaymentIntentFingerprint({
  required int supplierId,
  required double amount,
  required String? note,
}) {
  final roundedAmount = SupplierPaymentFingerprint.roundAmount(amount);
  final canonicalNote = SupplierPaymentFingerprint.normalizeNote(note);
  return SupplierPaymentFingerprint.compute(
    supplierId: supplierId,
    amount: roundedAmount,
    note: canonicalNote,
  );
}

/// Immutable snapshot for one supplier payment submit (B35).
class SupplierPaymentSubmitIntent {
  const SupplierPaymentSubmitIntent({
    required this.supplierId,
    required this.amount,
    required this.note,
  });

  final int supplierId;
  final double amount;
  final String? note;

  String get fingerprintHash => computeSupplierPaymentIntentFingerprint(
        supplierId: supplierId,
        amount: amount,
        note: note,
      );
}

enum SupplierPaymentSubmitOutcome {
  skippedInFlight,
  success,
  postSuccessRefreshFailed,
  idempotencyConflict,
  serviceFailure,
  staleCompletion,
}

/// Generation-guarded supplier payment submit orchestration (B35).
///
/// UI-only; [SupplierAccountService.processPayment] remains authoritative.
class SupplierPaymentSubmitRunner {
  bool _inFlight = false;

  bool get inFlight => _inFlight;

  Future<SupplierPaymentSubmitOutcome> submit({
    required SupplierPaymentSubmitIntent intent,
    required String idempotencyKey,
    required bool Function() isSubmitStillCurrent,
    required Future<SupplierPaymentResult> Function(String idempotencyKey)
        invokeService,
    required Future<void> Function(SupplierPaymentResult result)
        postSuccessRefresh,
  }) async {
    if (_inFlight) {
      return SupplierPaymentSubmitOutcome.skippedInFlight;
    }

    _inFlight = true;
    try {
      final result = await invokeService(idempotencyKey);

      if (!isSubmitStillCurrent()) {
        return SupplierPaymentSubmitOutcome.staleCompletion;
      }

      try {
        await postSuccessRefresh(result);
      } catch (_) {
        return SupplierPaymentSubmitOutcome.postSuccessRefreshFailed;
      }

      if (!isSubmitStillCurrent()) {
        return SupplierPaymentSubmitOutcome.staleCompletion;
      }

      return SupplierPaymentSubmitOutcome.success;
    } on SupplierPaymentIdempotencyConflictException {
      return SupplierPaymentSubmitOutcome.idempotencyConflict;
    } catch (_) {
      return SupplierPaymentSubmitOutcome.serviceFailure;
    } finally {
      _inFlight = false;
    }
  }
}