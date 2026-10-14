import 'package:flutter/foundation.dart';

/// Per cart-slot checkout idempotency (B27).
@visibleForTesting
class PosCheckoutIdempotencySlotState {
  String? idempotencyKey;
  String? boundFingerprintHash;

  void reset() {
    idempotencyKey = null;
    boundFingerprintHash = null;
  }
}

/// Sticky checkout operation keys bound to B5 fingerprint hash per cart slot.
///
/// UI-only; [PosSaleService.processSale] (B5) remains authoritative.
@visibleForTesting
class PosCheckoutIdempotencyState {
  final Map<int, PosCheckoutIdempotencySlotState> _slots = {};

  PosCheckoutIdempotencySlotState slot(int cartSlotId) =>
      _slots.putIfAbsent(cartSlotId, PosCheckoutIdempotencySlotState.new);

  /// Returns a stable UUID for [cartSlotId] + [fingerprintHash].
  String prepareCheckoutKey({
    required int cartSlotId,
    required String fingerprintHash,
    required String Function() generateUuid,
  }) {
    final s = slot(cartSlotId);
    if (s.idempotencyKey != null &&
        s.boundFingerprintHash != null &&
        s.boundFingerprintHash != fingerprintHash) {
      s.reset();
    }
    s.idempotencyKey ??= generateUuid();
    s.boundFingerprintHash = fingerprintHash;
    return s.idempotencyKey!;
  }

  void clearCheckoutKey(int cartSlotId) {
    _slots[cartSlotId]?.reset();
  }

  void removeSlot(int cartSlotId) {
    _slots.remove(cartSlotId);
  }

  @visibleForTesting
  Map<int, PosCheckoutIdempotencySlotState> get slotsForTesting => _slots;
}

/// Mirrors [_CartPanelState._checkout] early exit when a submit is in flight.
@visibleForTesting
bool canStartCheckoutSubmit({required bool inFlight}) => !inFlight;
