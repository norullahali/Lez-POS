// test/support/pos_session_close_test_keys.dart

import 'package:uuid/uuid.dart';

const _b26CloseUuid = Uuid();

String b26SessionCloseKey([String suffix = '']) =>
    'b26-close-${suffix.isEmpty ? _b26CloseUuid.v4() : suffix}';

/// Mirrors [SessionCloseDialog] sticky-key rules for unit tests (B26 case 15).
class CloseDialogIdempotencyBinding {
  CloseDialogIdempotencyBinding({required String initialKey})
      : idempotencyKey = initialKey;

  String idempotencyKey;
  double? boundClosingCash;
  String? boundNotes;

  void syncClosingInputs({
    required double closingCash,
    required String? notes,
    required String Function() generateUuid,
  }) {
    if (boundClosingCash == null) {
      boundClosingCash = closingCash;
      boundNotes = notes;
      return;
    }
    if (boundClosingCash != closingCash || boundNotes != notes) {
      idempotencyKey = generateUuid();
      boundClosingCash = closingCash;
      boundNotes = notes;
    }
  }
}
