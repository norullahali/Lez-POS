import 'package:flutter/foundation.dart';

/// Sticky refund-settlement operation keys per canonical intent fingerprint (B28).
///
/// UI-only; [CustomerRefundSettlementService.settleCredit] remains authoritative.
class CustomerRefundSettlementIdempotencyState {
  final Map<String, String> _keysByFingerprint = {};

  /// Returns a stable UUID for [fingerprintHash].
  String prepareSettlementKey({
    required String fingerprintHash,
    required String Function() generateUuid,
  }) {
    return _keysByFingerprint.putIfAbsent(fingerprintHash, generateUuid);
  }

  void clearSettlementKey(String fingerprintHash) {
    _keysByFingerprint.remove(fingerprintHash);
  }

  @visibleForTesting
  String? keyForFingerprint(String fingerprintHash) =>
      _keysByFingerprint[fingerprintHash];

  @visibleForTesting
  Map<String, String> get keysByFingerprintForTesting => _keysByFingerprint;
}
