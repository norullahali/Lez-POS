// lib/core/services/credit_limit_exception.dart

/// Thrown when a credit sale would exceed the customer's configured debt ceiling.
class CreditLimitExceededException implements Exception {
  const CreditLimitExceededException({
    required this.customerId,
    required this.currentBalance,
    required this.creditLimit,
    required this.requestedAmount,
  });

  final int customerId;
  final double currentBalance;
  final double creditLimit;
  final double requestedAmount;

  double get projectedBalance => currentBalance + requestedAmount;

  String get localizedMessage =>
      'تجاوز سقف الدين المسموح للعميل.\n'
      'الرصيد الحالي: ${currentBalance.toStringAsFixed(0)} د.ع | '
      'المطلوب: ${requestedAmount.toStringAsFixed(0)} د.ع | '
      'السقف: ${creditLimit.toStringAsFixed(0)} د.ع';

  @override
  String toString() => localizedMessage;
}
