// lib/features/customers/providers/customer_refund_settlement_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/customer_refund_settlement_service.dart';
import '../providers/customer_accounts_provider.dart';
import '../utils/customer_refund_settlement_messages.dart';

/// Refreshes read-only customer credit/balance displays after successful refund.
void invalidateCustomerRefundDisplays(Ref ref, int customerId) {
  ref.invalidate(customerAvailableCreditProvider(customerId));
  ref.invalidate(customerBalanceProvider(customerId));
  ref.invalidate(customerHistoryProvider(customerId));
}

/// Canonical Phase C Step 2.1 settlement service — sole financial write boundary for refunds.
final customerRefundSettlementServiceProvider =
    Provider<CustomerRefundSettlementService>((ref) {
  return CustomerRefundSettlementService(AppDatabase.instance);
});

/// Read-only display of aggregate customer credit (negative balance as positive credit).
final customerAvailableCreditProvider =
    FutureProvider.autoDispose.family<double, int>((ref, customerId) async {
  final dao = ref.read(customerAccountsDaoProvider);
  final balance = await dao.calculateBalanceFromTransactions(customerId);
  return balance < 0 ? -balance : 0.0;
});

enum CustomerRefundSettlementUiStatus { idle, submitting, success, failure }

class CustomerRefundSettlementUiState {
  final int customerId;
  final String customerName;
  final double availableCredit;
  final String amountText;
  final String note;
  final int? returnId;
  final String? returnLabel;
  final CustomerRefundSettlementUiStatus status;
  final String? errorMessage;

  const CustomerRefundSettlementUiState({
    required this.customerId,
    required this.customerName,
    required this.availableCredit,
    this.amountText = '',
    this.note = '',
    this.returnId,
    this.returnLabel,
    this.status = CustomerRefundSettlementUiStatus.idle,
    this.errorMessage,
  });

  double? get parsedAmount => parseCustomerRefundAmountText(amountText);

  String? get amountValidationError =>
      validateCustomerRefundAmountText(amountText, availableCredit);

  double? get remainingCreditPreview {
    final amount = parsedAmount;
    if (amount == null) return null;
    return (availableCredit - amount).clamp(0.0, availableCredit);
  }

  bool get isSubmitting =>
      status == CustomerRefundSettlementUiStatus.submitting;

  bool get canSubmit =>
      !isSubmitting && amountValidationError == null && (parsedAmount ?? 0) > 0;

  bool get hasAvailableCredit => availableCredit > 0.0001;

  CustomerRefundSettlementUiState copyWith({
    String? amountText,
    String? note,
    CustomerRefundSettlementUiStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CustomerRefundSettlementUiState(
      customerId: customerId,
      customerName: customerName,
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
double? parseCustomerRefundAmountText(String text) {
  final normalized = text.trim().replaceAll(',', '');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

/// UX-only validation — service remains authoritative for financial checks.
String? validateCustomerRefundAmountText(String text, double availableCredit) {
  final normalized = text.trim();
  if (normalized.isEmpty) {
    return 'مبلغ الاسترداد مطلوب';
  }
  final amount = parseCustomerRefundAmountText(text);
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

class CustomerRefundSettlementUiNotifier
    extends Notifier<CustomerRefundSettlementUiState?> {
  int _submitGeneration = 0;

  @override
  CustomerRefundSettlementUiState? build() => null;

  void init({
    required int customerId,
    required String customerName,
    required double availableCredit,
    int? returnId,
    String? returnLabel,
  }) {
    _submitGeneration = 0;
    state = CustomerRefundSettlementUiState(
      customerId: customerId,
      customerName: customerName,
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
      status: CustomerRefundSettlementUiStatus.idle,
    );
  }

  void setNote(String value) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      note: value,
      clearError: true,
      status: CustomerRefundSettlementUiStatus.idle,
    );
  }

  /// Submits via [CustomerRefundSettlementService.settleCredit].
  /// Returns true only after successful service completion.
  Future<bool> submit() async {
    final current = state;
    if (current == null || current.isSubmitting) return false;

    final generation = ++_submitGeneration;
    state = current.copyWith(
      status: CustomerRefundSettlementUiStatus.submitting,
      clearError: true,
    );

    final validationError = current.amountValidationError;
    if (validationError != null) {
      state = current.copyWith(
        status: CustomerRefundSettlementUiStatus.failure,
        errorMessage: validationError,
      );
      return false;
    }

    final amount = current.parsedAmount;
    if (amount == null || amount <= 0) {
      state = current.copyWith(
        status: CustomerRefundSettlementUiStatus.failure,
        errorMessage: customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.invalidAmount,
        ),
      );
      return false;
    }

    try {
      await ref.read(customerRefundSettlementServiceProvider).settleCredit(
            customerId: current.customerId,
            amount: amount,
            returnId: current.returnId,
            note: current.note.trim().isEmpty ? null : current.note.trim(),
          );
      if (!_isCurrentSubmit(generation)) return false;

      invalidateCustomerRefundDisplays(ref, current.customerId);

      state = current.copyWith(
        status: CustomerRefundSettlementUiStatus.success,
        clearError: true,
      );
      return true;
    } on CustomerRefundSettlementException catch (e) {
      if (!_isCurrentSubmit(generation)) return false;
      state = current.copyWith(
        amountText: current.amountText,
        note: current.note,
        status: CustomerRefundSettlementUiStatus.failure,
        errorMessage: customerRefundSettlementFailureMessage(e.code),
      );
      return false;
    } catch (_) {
      if (!_isCurrentSubmit(generation)) return false;
      state = current.copyWith(
        amountText: current.amountText,
        note: current.note,
        status: CustomerRefundSettlementUiStatus.failure,
        errorMessage: customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.unexpectedFailure,
        ),
      );
      return false;
    }
  }

  bool _isCurrentSubmit(int generation) => generation == _submitGeneration;
}

final customerRefundSettlementProvider = NotifierProvider<
    CustomerRefundSettlementUiNotifier, CustomerRefundSettlementUiState?>(
  CustomerRefundSettlementUiNotifier.new,
);
