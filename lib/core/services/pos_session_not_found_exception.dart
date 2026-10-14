// lib/core/services/pos_session_not_found_exception.dart

class PosSessionNotFoundException implements Exception {
  const PosSessionNotFoundException({required this.sessionId});

  final int sessionId;

  @override
  String toString() => 'POS session not found (id=$sessionId)';
}
