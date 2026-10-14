// lib/core/services/pos_session_already_open_exception.dart

class PosSessionAlreadyOpenException implements Exception {
  const PosSessionAlreadyOpenException({required this.existingSessionId});

  final int existingSessionId;

  @override
  String toString() =>
      'A POS session is already open (session #$existingSessionId)';
}
