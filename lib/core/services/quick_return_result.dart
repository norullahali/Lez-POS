// lib/core/services/quick_return_result.dart

class QuickReturnResult {
  const QuickReturnResult({
    required this.customerReturnId,
    required this.idempotentReplay,
  });

  final int customerReturnId;
  final bool idempotentReplay;
}
