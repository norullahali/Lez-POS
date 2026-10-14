// lib/core/services/pos_session_close_result.dart

class PosSessionCloseResult {
  const PosSessionCloseResult({
    required this.sessionId,
    required this.idempotentReplay,
    required this.closingCash,
    required this.expectedCashAmount,
    required this.cashDifference,
  });

  final int sessionId;
  final bool idempotentReplay;
  final double closingCash;
  final double expectedCashAmount;
  final double cashDifference;
}
