// lib/core/services/pos_session_open_result.dart

class PosSessionOpenResult {
  const PosSessionOpenResult({
    required this.sessionId,
    required this.idempotentReplay,
  });

  final int sessionId;
  final bool idempotentReplay;
}
