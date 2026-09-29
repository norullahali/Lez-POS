/// Thrown when the same POS sale idempotency key is reused with a different
/// checkout fingerprint.
class PosSaleIdempotencyConflictException implements Exception {
  const PosSaleIdempotencyConflictException([
    this.message = 'idempotency key reused with different checkout parameters',
  ]);

  final String message;

  @override
  String toString() => message;
}
