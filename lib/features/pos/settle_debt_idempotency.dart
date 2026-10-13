import 'package:flutter/foundation.dart';

/// Fixed note for POS cart-panel debt settlement (matches [PosRepository.settleDebt] default).
const kPosSettleDebtNote = 'تسوية دين من POS';

/// Amount tolerance aligned with [CustomerAccountService] B6 parameter matching.
const posSettleDebtAmountTolerance = 0.0001;

/// Sticky idempotency key + bound intent for POS settle-debt (B24).
///
/// UI-only; B6 remains authoritative for persistence and replay.
@visibleForTesting
class PosSettleDebtIdempotencyState {
  String? idempotencyKey;
  int? boundCustomerId;
  double? boundAmount;
  String? boundNote;

  void resetAttempt() {
    idempotencyKey = null;
    boundCustomerId = null;
    boundAmount = null;
    boundNote = null;
  }

  bool matchesBoundIntent({
    required int customerId,
    required double amount,
    required String note,
  }) {
    if (idempotencyKey == null) return false;
    final normalizedNote = note.trim();
    if (boundCustomerId != customerId) return false;
    if (boundAmount == null ||
        (boundAmount! - amount).abs() > posSettleDebtAmountTolerance) {
      return false;
    }
    if (boundNote != normalizedNote) return false;
    return true;
  }

  /// Returns the idempotency key for this submit. Invalidates prior key if intent changed.
  String prepareKey({
    required int customerId,
    required double amount,
    required String note,
    required String Function() generateUuid,
  }) {
    if (idempotencyKey != null &&
        !matchesBoundIntent(
          customerId: customerId,
          amount: amount,
          note: note,
        )) {
      resetAttempt();
    }
    idempotencyKey ??= generateUuid();
    boundCustomerId = customerId;
    boundAmount = amount;
    boundNote = note.trim();
    return idempotencyKey!;
  }

  void onSuccessfulPayment() => resetAttempt();

  void onIdempotencyConflict() => resetAttempt();
}

/// Mirrors [_CartPanelState._settleDebt] early exit when a submit is in flight.
@visibleForTesting
bool canStartSettleDebtSubmit({required bool inFlight}) => !inFlight;