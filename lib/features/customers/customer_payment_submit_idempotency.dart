import '../../core/services/customer_payment_idempotency_conflict_exception.dart';
import '../../core/services/customer_payment_result.dart';

/// Immutable snapshot for one customer payment submit (B36).
///
/// [note] must match the value passed to [CustomerAccountService.processPayment]
/// (typically from UI `_paymentNote()`, including the default `'دفعة نقدية'`).
class CustomerPaymentSubmitIntent {
  const CustomerPaymentSubmitIntent({
    required this.customerId,
    required this.amount,
    required this.note,
  });

  final int customerId;
  final double amount;
  final String note;
}

enum CustomerPaymentSubmitOutcome {
  skippedInFlight,
  success,
  postSuccessRefreshFailed,
  idempotencyConflict,
  serviceFailure,
  staleCompletion,
}

/// Generation-guarded customer payment submit orchestration (B36).
///
/// UI-only; [CustomerAccountService.processPayment] remains authoritative.
class CustomerPaymentSubmitRunner {
  bool _inFlight = false;

  bool get inFlight => _inFlight;

  Future<CustomerPaymentSubmitOutcome> submit({
    required CustomerPaymentSubmitIntent intent,
    required String idempotencyKey,
    required bool Function() isSubmitStillCurrent,
    required Future<CustomerPaymentResult> Function(String idempotencyKey)
        invokeService,
    required Future<void> Function(CustomerPaymentResult result)
        postSuccessRefresh,
  }) async {
    if (_inFlight) {
      return CustomerPaymentSubmitOutcome.skippedInFlight;
    }

    _inFlight = true;
    try {
      final result = await invokeService(idempotencyKey);

      if (!isSubmitStillCurrent()) {
        return CustomerPaymentSubmitOutcome.staleCompletion;
      }

      try {
        await postSuccessRefresh(result);
      } catch (_) {
        if (!isSubmitStillCurrent()) {
          return CustomerPaymentSubmitOutcome.staleCompletion;
        }
        return CustomerPaymentSubmitOutcome.postSuccessRefreshFailed;
      }

      if (!isSubmitStillCurrent()) {
        return CustomerPaymentSubmitOutcome.staleCompletion;
      }

      return CustomerPaymentSubmitOutcome.success;
    } on CustomerPaymentIdempotencyConflictException {
      return CustomerPaymentSubmitOutcome.idempotencyConflict;
    } catch (_) {
      return CustomerPaymentSubmitOutcome.serviceFailure;
    } finally {
      _inFlight = false;
    }
  }
}