import 'package:flutter/foundation.dart';

import '../../core/services/supplier_return_fingerprint.dart';
import '../../core/services/supplier_return_idempotency_conflict_exception.dart';
import '../../core/services/supplier_return_posting_result.dart';
import '../../core/services/supplier_return_service.dart';

/// Canonical operation-intent fingerprint for purchase-linked supplier returns (B33).
///
/// Must match [SupplierReturnService.postPurchaseLinkedReturn] input hashing.
String computeSupplierReturnIntentFingerprint(SupplierReturnPostingInput input) {
  return SupplierReturnFingerprint.compute(input);
}

/// Sticky supplier-return operation keys per canonical intent fingerprint (B33).
///
/// UI-only; [SupplierReturnService.postPurchaseLinkedReturn] remains authoritative.
class SupplierReturnIdempotencyState {
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

/// One submit intent built from the draft posting input (B33).
class SupplierReturnSubmitIntent {
  const SupplierReturnSubmitIntent({required this.input});

  final SupplierReturnPostingInput input;

  String get fingerprintHash => computeSupplierReturnIntentFingerprint(input);
}

enum SupplierReturnSubmitOutcome {
  skippedInFlight,
  success,
  postSuccessRefreshFailed,
  idempotencyConflict,
  serviceFailure,
  staleCompletion,
}

/// Orchestrates sticky keys; slot clear is generation-guarded via [isSubmitStillCurrent] (B33).
class SupplierReturnSubmitRunner {
  SupplierReturnSubmitRunner({
    SupplierReturnIdempotencyState? idempotency,
  }) : idempotency = idempotency ?? SupplierReturnIdempotencyState();

  final SupplierReturnIdempotencyState idempotency;
  bool _inFlight = false;

  bool get inFlight => _inFlight;

  Future<SupplierReturnSubmitOutcome> submit({
    required SupplierReturnSubmitIntent intent,
    required String Function() generateUuid,
    required bool Function() isSubmitStillCurrent,
    required Future<SupplierReturnPostingResult> Function(String idempotencyKey)
        invokeService,
    required Future<void> Function(SupplierReturnPostingResult result)
        postSuccessRefresh,
  }) async {
    if (_inFlight) {
      return SupplierReturnSubmitOutcome.skippedInFlight;
    }

    final fingerprintHash = intent.fingerprintHash;
    final returnKey = idempotency.prepareReturnKey(
      fingerprintHash: fingerprintHash,
      generateUuid: generateUuid,
    );

    _inFlight = true;
    try {
      final result = await invokeService(returnKey);

      if (!isSubmitStillCurrent()) {
        return SupplierReturnSubmitOutcome.staleCompletion;
      }

      try {
        await postSuccessRefresh(result);
      } catch (_) {
        return SupplierReturnSubmitOutcome.postSuccessRefreshFailed;
      }

      if (!isSubmitStillCurrent()) {
        return SupplierReturnSubmitOutcome.staleCompletion;
      }

      idempotency.clearReturnKey(fingerprintHash);
      return SupplierReturnSubmitOutcome.success;
    } on SupplierReturnIdempotencyConflictException {
      return SupplierReturnSubmitOutcome.idempotencyConflict;
    } on SupplierReturnPostingException {
      rethrow;
    } catch (_) {
      return SupplierReturnSubmitOutcome.serviceFailure;
    } finally {
      _inFlight = false;
    }
  }
}
