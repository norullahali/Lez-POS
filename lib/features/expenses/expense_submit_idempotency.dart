import '../../core/services/expense_creation_fingerprint.dart';
import '../../core/services/expense_creation_idempotency_conflict_exception.dart';
import '../../core/services/expense_mutation_fingerprint.dart';
import '../../core/services/expense_mutation_save_idempotency_conflict_exception.dart';

enum ExpenseSubmitMode { create, update }

/// Immutable snapshot for one expense dialog submit (B39).
class ExpenseSubmitIntent {
  const ExpenseSubmitIntent.create({
    required this.categoryId,
    required this.amount,
    required this.expenseDate,
    required this.paidAt,
    required this.notes,
    required this.sessionId,
    required this.createdBy,
  })  : mode = ExpenseSubmitMode.create,
        expenseId = null,
        updatedBy = null;

  const ExpenseSubmitIntent.update({
    required this.expenseId,
    required this.categoryId,
    required this.amount,
    required this.expenseDate,
    required this.paidAt,
    required this.notes,
    required this.sessionId,
    required this.updatedBy,
  }) : mode = ExpenseSubmitMode.update,
       createdBy = null;

  final ExpenseSubmitMode mode;
  final int? expenseId;
  final int categoryId;
  final double amount;
  final DateTime expenseDate;
  final DateTime paidAt;
  final String notes;
  final int? sessionId;
  final int? createdBy;
  final int? updatedBy;

  String get fingerprintHash {
    switch (mode) {
      case ExpenseSubmitMode.create:
        return ExpenseCreationFingerprint.compute(
          categoryId: categoryId,
          amount: amount,
          expenseDate: expenseDate,
          paidAt: paidAt,
          notes: notes,
          sessionId: sessionId,
          createdBy: createdBy!,
        );
      case ExpenseSubmitMode.update:
        return ExpenseMutationFingerprint.computeUpdate(
          expenseId: expenseId!,
          categoryId: categoryId,
          amount: amount,
          expenseDate: expenseDate,
          paidAt: paidAt,
          notes: notes,
          sessionId: sessionId,
          updatedBy: updatedBy!,
        );
    }
  }
}

enum ExpenseSubmitOutcome {
  skippedInFlight,
  success,
  postSuccessRefreshFailed,
  idempotencyConflict,
  serviceFailure,
  staleCompletion,
}

/// Generation-guarded expense dialog submit orchestration (B39).
///
/// UI-only; expense creation/mutation services remain authoritative.
class ExpenseSubmitRunner {
  bool _inFlight = false;

  bool get inFlight => _inFlight;

  Future<ExpenseSubmitOutcome> submit({
    required ExpenseSubmitIntent intent,
    required String idempotencyKey,
    required bool Function() isSubmitStillCurrent,
    required Future<void> Function(String idempotencyKey) invokeService,
    required Future<void> Function() postSuccessRefresh,
  }) async {
    if (_inFlight) {
      return ExpenseSubmitOutcome.skippedInFlight;
    }

    _inFlight = true;
    try {
      await invokeService(idempotencyKey);

      if (!isSubmitStillCurrent()) {
        return ExpenseSubmitOutcome.staleCompletion;
      }

      try {
        await postSuccessRefresh();
      } catch (_) {
        if (!isSubmitStillCurrent()) {
          return ExpenseSubmitOutcome.staleCompletion;
        }
        return ExpenseSubmitOutcome.postSuccessRefreshFailed;
      }

      if (!isSubmitStillCurrent()) {
        return ExpenseSubmitOutcome.staleCompletion;
      }

      return ExpenseSubmitOutcome.success;
    } on ExpenseCreationIdempotencyConflictException {
      return ExpenseSubmitOutcome.idempotencyConflict;
    } on ExpenseMutationSaveIdempotencyConflictException {
      return ExpenseSubmitOutcome.idempotencyConflict;
    } catch (_) {
      return ExpenseSubmitOutcome.serviceFailure;
    } finally {
      _inFlight = false;
    }
  }
}