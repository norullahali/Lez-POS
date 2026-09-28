// lib/core/services/supplier_payment_exceeds_payable_exception.dart

/// Thrown when a supplier payment exceeds the outstanding payable amount.
class SupplierPaymentExceedsPayableException implements Exception {
  const SupplierPaymentExceedsPayableException({
    required this.supplierId,
    required this.currentPayable,
    required this.requestedAmount,
  });

  final int supplierId;
  final double currentPayable;
  final double requestedAmount;

  double get remainingPayable => currentPayable > 0 ? currentPayable : 0;

  String get localizedMessage =>
      'تجاوز مبلغ الدفع الرصيد المستحق للمورد.\n'
      'الرصيد الحالي: ${currentPayable.toStringAsFixed(0)} د.ع | '
      'المطلوب: ${requestedAmount.toStringAsFixed(0)} د.ع | '
      'المتبقي: ${remainingPayable.toStringAsFixed(0)} د.ع';

  @override
  String toString() => localizedMessage;
}
