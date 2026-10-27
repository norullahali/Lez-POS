import '../../core/services/customer_invoice_return_idempotency_conflict_exception.dart';
import '../../core/services/customer_invoice_return_posting_result.dart';
import '../../core/services/partial_return_service.dart';

enum CustomerInvoiceReturnSubmitMode { full, partial }

/// Immutable snapshot for one invoice-linked return submit (B38).
class CustomerInvoiceReturnSubmitIntent {
  const CustomerInvoiceReturnSubmitIntent.full({
    required this.saleInvoiceId,
    required this.customerId,
    required this.returnedByUserId,
    required this.note,
  })  : mode = CustomerInvoiceReturnSubmitMode.full,
        partialLines = null;

  const CustomerInvoiceReturnSubmitIntent.partial({
    required this.saleInvoiceId,
    required this.customerId,
    required this.returnedByUserId,
    required this.note,
    required this.partialLines,
  }) : mode = CustomerInvoiceReturnSubmitMode.partial;

  final CustomerInvoiceReturnSubmitMode mode;
  final int saleInvoiceId;
  final int customerId;
  final int returnedByUserId;
  final String note;
  final List<CustomerInvoicePartialReturnLine>? partialLines;
}

enum CustomerInvoiceReturnSubmitOutcome {
  skippedInFlight,
  success,
  postSuccessRefreshFailed,
  idempotencyConflict,
  serviceFailure,
  staleCompletion,
}

/// Generation-guarded invoice return submit orchestration (B38).
///
/// UI-only; [CustomerInvoiceReturnService] remains authoritative.
class CustomerInvoiceReturnSubmitRunner {
  bool _inFlight = false;

  bool get inFlight => _inFlight;

  Future<CustomerInvoiceReturnSubmitOutcome> submit({
    required CustomerInvoiceReturnSubmitIntent intent,
    required String idempotencyKey,
    required bool Function() isSubmitStillCurrent,
    required Future<CustomerInvoiceReturnPostingResult> Function(
      String idempotencyKey,
    ) invokeService,
    required Future<void> Function(CustomerInvoiceReturnPostingResult result)
        postSuccessRefresh,
  }) async {
    if (_inFlight) {
      return CustomerInvoiceReturnSubmitOutcome.skippedInFlight;
    }

    _inFlight = true;
    try {
      final result = await invokeService(idempotencyKey);

      if (!isSubmitStillCurrent()) {
        return CustomerInvoiceReturnSubmitOutcome.staleCompletion;
      }

      try {
        await postSuccessRefresh(result);
      } catch (_) {
        if (!isSubmitStillCurrent()) {
          return CustomerInvoiceReturnSubmitOutcome.staleCompletion;
        }
        return CustomerInvoiceReturnSubmitOutcome.postSuccessRefreshFailed;
      }

      if (!isSubmitStillCurrent()) {
        return CustomerInvoiceReturnSubmitOutcome.staleCompletion;
      }

      return CustomerInvoiceReturnSubmitOutcome.success;
    } on CustomerInvoiceReturnIdempotencyConflictException {
      return CustomerInvoiceReturnSubmitOutcome.idempotencyConflict;
    } catch (_) {
      return CustomerInvoiceReturnSubmitOutcome.serviceFailure;
    } finally {
      _inFlight = false;
    }
  }
}