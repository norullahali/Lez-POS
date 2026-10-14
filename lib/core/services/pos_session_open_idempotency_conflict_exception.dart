// lib/core/services/pos_session_open_idempotency_conflict_exception.dart

class PosSessionOpenIdempotencyConflictException implements Exception {
  const PosSessionOpenIdempotencyConflictException();

  @override
  String toString() =>
      'POS session open idempotency key reused with different parameters';
}
