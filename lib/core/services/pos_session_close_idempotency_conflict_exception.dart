// lib/core/services/pos_session_close_idempotency_conflict_exception.dart

class PosSessionCloseIdempotencyConflictException implements Exception {
  const PosSessionCloseIdempotencyConflictException();

  @override
  String toString() =>
      'POS session close idempotency conflict: close intent does not match '
      'the already-closed session';
}
