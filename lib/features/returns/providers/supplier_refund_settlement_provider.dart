// lib/features/returns/providers/supplier_refund_settlement_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supplier_refund_settlement_service.dart';
import '../../suppliers/providers/supplier_accounts_provider.dart';
import '../utils/supplier_refund_settlement_messages.dart';
import 'supplier_return_service_provider.dart';

/// Refreshes read-only supplier credit/balance displays after successful refund.
void invalidateSupplierRefundDisplays(Ref ref, int supplierId) {
  ref.invalidate(supplierAvailableCreditProvider(supplierId));
  ref.invalidate(supplierBalanceProvider(supplierId));
  ref.invalidate(supplierHistoryProvider(supplierId));
}

/// Canonical SR.3.3 settlement service — sole financial write boundary for refunds.
final supplierRefundSettlementServiceProvider =
    Provider<SupplierRefundSettlementService>((ref) {
  return SupplierRefundSettlementService(AppDatabase.instance);
});

/// Read-only display of aggregate supplier credit (negative balance as positive credit).
final supplierAvailableCreditProvider =
    FutureProvider.autoDispose.family<double, int>((ref, supplierId) async {
  final dao = ref.read(supplierAccountsDaoProvider);
  final balance = await dao.calculateBalanceFromTransactions(supplierId);
  return balance < 0 ? -balance : 0.0;
});

enum SupplierRefundSettlementUiStatus { idle, submitting, success, failure }

class SupplierRefundSettlementUiState {
  final int supplierId;
  final String supplierName;
  final double availableCredit;
  final String amountText;
  final String note;
  final int? returnId;
  final String? returnLabel;
  final SupplierRefundSettlementUiStatus status;
  final String? errorMessage;

  const SupplierRefundSettlementUiState({
    required this.supplierId,
    required this.supplierName,
    required this.availableCredit,
    this.amountText = '',
    this.note = '',
    this.returnId,
    this.returnLabel,
    this.status = SupplierRefundSettlementUiStatus.idle,
    this.errorMessage,
  });

  double? get parsedAmount => parseRefundAmountText(amountText);

  String? get amountValidationError =>
      validateRefundAmountText(amountText, availableCredit);

  double? get remainingCreditPreview {
    final amount = parsedAmount;
    if (amount == null) return null;
    return (availableCredit - amount).clamp(0.0, availableCredit);
  }

  bool get isSubmitting =>
      status == SupplierRefundSettlementUiStatus.submitting;

  bool get canSubmit =>
      !isSubmitting && amountValidationError == null && (parsedAmount ?? 0) > 0;

  bool get hasAvailableCredit => availableCredit > 0.0001;

  SupplierRefundSettlementUiState copyWith({
    String? amountText,
    String? note,
    SupplierRefundSettlementUiStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SupplierRefundSettlementUiState(
      supplierId: supplierId,
      supplierName: supplierName,
      availableCredit: availableCredit,
      amountText: amountText ?? this.amountText,
      note: note ?? this.note,
      returnId: returnId,
      returnLabel: returnLabel,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// UX-only amount parsing for the refund dialog.
double? parseRefundAmountText(String text) {
  final normalized = text.trim().replaceAll(',', '');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

/// UX-only validation — service remains authoritative for financial checks.
String? validateRefundAmountText(String text, double availableCredit) {
  final normalized = text.trim();
  if (normalized.isEmpty) {
    return 'مبلغ الاسترداد مطلوب';
  }
  final amount = parseRefundAmountText(text);
  if (amount == null) {
    return 'مبلغ الاسترداد غير صالح';
  }
  if (amount <= 0) {
    return 'مبلغ الاسترداد غير صالح';
  }
  if (amount > availableCredit + 0.0001) {
    return 'مبلغ الاسترداد يتجاوز الرصيد الدائن المتاح';
  }
  return null;
}

class SupplierRefundSettlementUiNotifier
    extends Notifier<SupplierRefundSettlementUiState?> {
  int _submitGeneration = 0;

  @override
  SupplierRefundSettlementUiState? build() => null;

  void init({
    required int supplierId,
    required String supplierName,
    required double availableCredit,
    int? returnId,
    String? returnLabel,
  }) {
    _submitGeneration = 0;
    state = SupplierRefundSettlementUiState(
      supplierId: supplierId,
      supplierName: supplierName,
      availableCredit: availableCredit,
      returnId: returnId,
      returnLabel: returnLabel,
    );
  }

  void reset() {
    _submitGeneration = 0;
    state = null;
  }

  void setAmountText(String value) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      amountText: value,
      clearError: true,
      status: SupplierRefundSettlementUiStatus.idle,
    );
  }

  void setNote(String value) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      note: value,
      clearError: true,
      status: SupplierRefundSettlementUiStatus.idle,
    );
  }

  /// Submits via [SupplierRefundSettlementService.settleCredit].
  /// Returns true only after successful service completion.
  Future<bool> submit() async {
    final current = state;
    if (current == null || current.isSubmitting) return false;

    final generation = ++_submitGeneration;
    state = current.copyWith(
      status: SupplierRefundSettlementUiStatus.submitting,
      clearError: true,
    );

    final validationError = current.amountValidationError;
    if (validationError != null) {
      state = current.copyWith(
        status: SupplierRefundSettlementUiStatus.failure,
        errorMessage: validationError,
      );
      return false;
    }

    final amount = current.parsedAmount;
    if (amount == null || amount <= 0) {
      state = current.copyWith(
        status: SupplierRefundSettlementUiStatus.failure,
        errorMessage: supplierRefundSettlementFailureMessage(
          SupplierRefundSettlementFailure.invalidAmount,
        ),
      );
      return false;
    }

    try {
      await ref.read(supplierRefundSettlementServiceProvider).settleCredit(
            supplierId: current.supplierId,
            amount: amount,
            returnId: current.returnId,
            note: current.note.trim().isEmpty ? null : current.note.trim(),
          );
      if (!_isCurrentSubmit(generation)) return false;

      ref.read(supplierReturnsRefreshProvider.notifier).state++;
      invalidateSupplierRefundDisplays(ref, current.supplierId);

      state = current.copyWith(
        status: SupplierRefundSettlementUiStatus.success,
        clearError: true,
      );
      return true;
    } on SupplierRefundSettlementException catch (e) {
      if (!_isCurrentSubmit(generation)) return false;
      state = current.copyWith(
        amountText: current.amountText,
        note: current.note,
        status: SupplierRefundSettlementUiStatus.failure,
        errorMessage: supplierRefundSettlementFailureMessage(e.code),
      );
      return false;
    } catch (_) {
      if (!_isCurrentSubmit(generation)) return false;
      state = current.copyWith(
        amountText: current.amountText,
        note: current.note,
        status: SupplierRefundSettlementUiStatus.failure,
        errorMessage: supplierRefundSettlementFailureMessage(
          SupplierRefundSettlementFailure.unexpectedFailure,
        ),
      );
      return false;
    }
  }

  bool _isCurrentSubmit(int generation) => generation == _submitGeneration;
}

final supplierRefundSettlementProvider = NotifierProvider<
    SupplierRefundSettlementUiNotifier, SupplierRefundSettlementUiState?>(
  SupplierRefundSettlementUiNotifier.new,
);
