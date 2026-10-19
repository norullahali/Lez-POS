import 'package:flutter/foundation.dart';

import '../../core/services/quick_return_fingerprint.dart';
import '../../core/services/quick_return_idempotency_conflict_exception.dart';

/// Canonical operation-intent fingerprint for quick return UI (B31).
///
/// Must match [PosSaleService.processQuickReturn] parameter normalization.
String computeQuickReturnIntentFingerprint({
  required int productId,
  required double quantity,
  required double refundAmount,
  required String reason,
  required int userId,
  int? approvedByUserId,
}) {
  return QuickReturnFingerprint.compute(
    productId: productId,
    quantity: QuickReturnFingerprint.roundAmount(quantity),
    refundAmount: QuickReturnFingerprint.roundAmount(refundAmount),
    reason: QuickReturnFingerprint.normalizeReason(reason),
    userId: userId,
    approvedByUserId: approvedByUserId,
  );
}

/// Sticky quick-return operation keys per canonical intent fingerprint (B31).
///
/// UI-only; [PosSaleService.processQuickReturn] remains authoritative.
class CustomerQuickReturnIdempotencyState {
  final Map<String, String> _keysByFingerprint = {};

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

/// Parameters for one quick-return submit intent (B31 orchestration).
class QuickReturnSubmitIntent {
  const QuickReturnSubmitIntent({
    required this.productId,
    required this.quantity,
    required this.refundAmount,
    required this.reason,
    required this.userId,
    this.approvedByUserId,
  });

  final int productId;
  final double quantity;
  final double refundAmount;
  final String reason;
  final int userId;
  final int? approvedByUserId;

  String get fingerprintHash => computeQuickReturnIntentFingerprint(
        productId: productId,
        quantity: quantity,
        refundAmount: refundAmount,
        reason: reason,
        userId: userId,
        approvedByUserId: approvedByUserId,
      );
}

enum QuickReturnSubmitOutcome {
  skippedInFlight,
  success,
  postSuccessRefreshFailed,
  idempotencyConflict,
  serviceFailure,
}

/// Orchestrates sticky keys + post-success clear semantics (B31).
class CustomerQuickReturnSubmitRunner {
  CustomerQuickReturnSubmitRunner({
    CustomerQuickReturnIdempotencyState? idempotency,
  }) : idempotency = idempotency ?? CustomerQuickReturnIdempotencyState();

  final CustomerQuickReturnIdempotencyState idempotency;
  bool _inFlight = false;

  bool get inFlight => _inFlight;

  Future<QuickReturnSubmitOutcome> submit({
    required QuickReturnSubmitIntent intent,
    required String Function() generateUuid,
    required Future<void> Function(String idempotencyKey) invokeService,
    required Future<void> Function() postSuccessRefresh,
  }) async {
    if (_inFlight) {
      return QuickReturnSubmitOutcome.skippedInFlight;
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
        return QuickReturnSubmitOutcome.postSuccessRefreshFailed;
      }

      idempotency.clearReturnKey(fingerprintHash);
      return QuickReturnSubmitOutcome.success;
    } on QuickReturnIdempotencyConflictException {
      return QuickReturnSubmitOutcome.idempotencyConflict;
    } catch (_) {
      return QuickReturnSubmitOutcome.serviceFailure;
    } finally {
      _inFlight = false;
    }
  }
}
