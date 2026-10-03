// lib/core/services/manual_return_result.dart

class ManualReturnResult {
  const ManualReturnResult({
    required this.customerReturnId,
    required this.idempotentReplay,
  });

  final int customerReturnId;
  final bool idempotentReplay;
}
