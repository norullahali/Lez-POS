import '../../core/services/other_income_creation_fingerprint.dart';
import '../../core/services/other_income_creation_idempotency_conflict_exception.dart';
import '../../core/services/other_income_mutation_fingerprint.dart';
import '../../core/services/other_income_mutation_save_idempotency_conflict_exception.dart';

enum OtherIncomeSubmitMode { create, update }

/// Immutable snapshot for one other-income dialog submit (B40).
class OtherIncomeSubmitIntent {
  const OtherIncomeSubmitIntent.create({
    required this.categoryId,
    required this.amount,
    required this.incomeDate,
    required this.receivedAt,
    required this.notes,
    required this.sessionId,
    required this.createdBy,
  })  : mode = OtherIncomeSubmitMode.create,
        otherIncomeRecordId = null,
        updatedBy = null;

  const OtherIncomeSubmitIntent.update({
    required this.otherIncomeRecordId,
    required this.categoryId,
    required this.amount,
    required this.incomeDate,
    required this.receivedAt,
    required this.notes,
    required this.sessionId,
    required this.updatedBy,
  })  : mode = OtherIncomeSubmitMode.update,
        createdBy = null;

  final OtherIncomeSubmitMode mode;
  final int? otherIncomeRecordId;
  final int categoryId;
  final double amount;
  final DateTime incomeDate;
  final DateTime receivedAt;
  final String notes;
  final int? sessionId;
  final int? createdBy;
  final int? updatedBy;

  String get fingerprintHash {
    switch (mode) {
      case OtherIncomeSubmitMode.create:
        return OtherIncomeCreationFingerprint.compute(
          categoryId: categoryId,
          amount: amount,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: notes,
          sessionId: sessionId,
          createdBy: createdBy!,
        );
      case OtherIncomeSubmitMode.update:
        return OtherIncomeMutationFingerprint.computeUpdate(
          otherIncomeRecordId: otherIncomeRecordId!,
          categoryId: categoryId,
          amount: amount,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: notes,
          sessionId: sessionId,
          updatedBy: updatedBy!,
        );
    }
  }
}

enum OtherIncomeSubmitOutcome {
  skippedInFlight,
  success,
  postSuccessRefreshFailed,
  idempotencyConflict,
  serviceFailure,
  staleCompletion,
}

/// Generation-guarded other-income dialog submit orchestration (B40).
///
/// UI-only; B19/B23 services remain authoritative.
class OtherIncomeSubmitRunner {
  bool _inFlight = false;

  bool get inFlight => _inFlight;

  Future<OtherIncomeSubmitOutcome> submit({
    required OtherIncomeSubmitIntent intent,
    required String idempotencyKey,
    required bool Function() isSubmitStillCurrent,
    required Future<void> Function(String idempotencyKey) invokeService,
    required Future<void> Function() postSuccessRefresh,
  }) async {
    if (_inFlight) {
      return OtherIncomeSubmitOutcome.skippedInFlight;
    }

    _inFlight = true;
    try {
      await invokeService(idempotencyKey);

      if (!isSubmitStillCurrent()) {
        return OtherIncomeSubmitOutcome.staleCompletion;
      }

      try {
        await postSuccessRefresh();
      } catch (_) {
        if (!isSubmitStillCurrent()) {
          return OtherIncomeSubmitOutcome.staleCompletion;
        }
        return OtherIncomeSubmitOutcome.postSuccessRefreshFailed;
      }

      if (!isSubmitStillCurrent()) {
        return OtherIncomeSubmitOutcome.staleCompletion;
      }

      return OtherIncomeSubmitOutcome.success;
    } on OtherIncomeCreationIdempotencyConflictException {
      return OtherIncomeSubmitOutcome.idempotencyConflict;
    } on OtherIncomeMutationSaveIdempotencyConflictException {
      return OtherIncomeSubmitOutcome.idempotencyConflict;
    } catch (_) {
      return OtherIncomeSubmitOutcome.serviceFailure;
    } finally {
      _inFlight = false;
    }
  }
}