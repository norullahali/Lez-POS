// lib/core/services/pos_session_close_invalid_closed_by_user_exception.dart

class PosSessionCloseInvalidClosedByUserException implements Exception {
  const PosSessionCloseInvalidClosedByUserException({required this.closedByUserId});

  final int closedByUserId;

  @override
  String toString() =>
      'POS session close rejected: closedByUserId=$closedByUserId is not a '
      'valid user';
}
