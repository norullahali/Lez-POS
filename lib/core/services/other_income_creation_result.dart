// lib/core/services/other_income_creation_result.dart

class OtherIncomeCreationResult {
  const OtherIncomeCreationResult({
    required this.otherIncomeRecordId,
    required this.idempotentReplay,
  });

  final int otherIncomeRecordId;
  final bool idempotentReplay;
}