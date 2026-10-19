import 'package:flutter/foundation.dart';

import '../../core/services/manual_return_fingerprint.dart';
import '../../core/services/manual_return_idempotency_conflict_exception.dart';
import '../../core/services/manual_return_result.dart';

/// Canonical operation-intent fingerprint for manual return UI (B30).
///
/// Must match [ManualReturnService.processManualReturn] parameter normalization.
String computeManualReturnIntentFingerprint({
  required int productId,
  required double quantity,
  required double unitPrice,
  required String reason,
  int? userId,
  int? approvedByUserId,
}) {
  return ManualReturnFingerprint.compute(
    productId: productId,
    quantity: ManualReturnFingerprint.roundAmount(quantity),
    unitPrice: ManualReturnFingerprint.roundAmount(unitPrice),
    reason: ManualReturnFingerprint.normalizeReason(reason),
    userId: userId,
    approvedByUserId: approvedByUserId,
  );
}

/// Sticky manual-return operation keys per canonical intent fingerprint (B30).
///
/// UI-only; [ManualReturnService.processManualReturn] remains authoritative.
class CustomerManualReturnIdempotencyState {
  final Map<String, String> _keysByFingerprint = {};

  /// Returns a stable UUID for [fingerprintHash].
  String prepareReturnKey({
    required String fingerprintHash,
    required String Function() generateUuid,
  }) {
    return _keysByFingerprint.putIfAbsent(fingerprintHash, generateUuid);
  }

  void clearReturnKey(String fingerprintHash) {
    _keysByFingerprint.remove(fingerprintHash);
  }

  @visibleForTesting
  String? keyForFingerprint(String fingerprintHash) =>
      _keysByFingerprint[fingerprintHash];

  @visibleForTesting
  Map<String, String> get keysByFingerprintForTesting => _keysByFingerprint;
}

/// Parameters for one manual-return submit intent (B30 orchestration).
class ManualReturnSubmitIntent {
  const ManualReturnSubmitIntent({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.reason,
    this.userId,
    this.approvedByUserId,
  });

  final int productId;
  final double quantity;
  final double unitPrice;
  final String reason;
  final int? userId;
  final int? approvedByUserId;

  String get fingerprintHash => computeManualReturnIntentFingerprint(
        productId: productId,
        quantity: quantity,
        unitPrice: unitPrice,
        reason: reason,
        userId: userId,
        approvedByUserId: approvedByUserId,
      );
}

enum ManualReturnSubmitOutcome {
  skippedInFlight,
  success,
  postSuccessRefreshFailed,
  idempotencyConflict,
  serviceFailure,
}

/// Orchestrates sticky keys + post-success clear semantics (B30).
class CustomerManualReturnSubmitRunner {
  CustomerManualReturnSubmitRunner({
    CustomerManualReturnIdempotencyState? idempotency,
  }) : idempotency = idempotency ?? CustomerManualReturnIdempotencyState();

  final CustomerManualReturnIdempotencyState idempotency;
  bool _inFlight = false;

  bool get inFlight => _inFlight;

  Future<ManualReturnSubmitOutcome> submit({
    required ManualReturnSubmitIntent intent,
    required String Function() generateUuid,
    required Future<ManualReturnResult> Function(String idempotencyKey)
        invokeService,
    required Future<void> Function() postSuccessRefresh,
  }) async {
    if (_inFlight) {
      return ManualReturnSubmitOutcome.skippedInFlight;
    }

    final fingerprintHash = intent.fingerprintHash;
    final returnKey = idempotency.prepareReturnKey(
      fingerprintHash: fingerprintHash,
      generateUuid: generateUuid,
    );

    _inFlight = true;
    try {
      await invokeService(returnKey);

      try {
        await postSuccessRefresh();
      } catch (_) {
        return ManualReturnSubmitOutcome.postSuccessRefreshFailed;
      }

      idempotency.clearReturnKey(fingerprintHash);
      return ManualReturnSubmitOutcome.success;
    } on ManualReturnIdempotencyConflictException {
      return ManualReturnSubmitOutcome.idempotencyConflict;
    } catch (_) {
      return ManualReturnSubmitOutcome.serviceFailure;
    } finally {
      _inFlight = false;
    }
  }
}
