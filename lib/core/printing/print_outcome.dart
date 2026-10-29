// lib/core/printing/print_outcome.dart
//
// Structured result for print delivery (B41 Stage 2).
// "Submitted" means the best software signal available (OS dialog completed /
// spooler accepted RAW bytes) — not proof of physical paper output.

import 'printer_config.dart';

/// How the job was handed off to the platform.
enum PrintDeliveryKind {
  pdfDialog,
  usbRawSpooler,
}

enum PrintOutcomeKind {
  submitted,
  failed,
  cancelled,
  unsupportedConfig,
}

class PrintOutcome {
  const PrintOutcome._({
    required this.kind,
    this.deliveryKind,
    required this.code,
    this.debugDetail,
    this.unsupportedType,
  });

  final PrintOutcomeKind kind;
  final PrintDeliveryKind? deliveryKind;

  /// Stable identifier for logs/tests (e.g. `pdf_build_failed`).
  final String code;

  /// English/diagnostic detail for debug logs — not for operator SnackBars.
  final String? debugDetail;

  final PrinterType? unsupportedType;

  factory PrintOutcome.submitted({required PrintDeliveryKind kind}) =>
      PrintOutcome._(
        kind: PrintOutcomeKind.submitted,
        deliveryKind: kind,
        code: 'submitted',
      );

  factory PrintOutcome.cancelled() => const PrintOutcome._(
        kind: PrintOutcomeKind.cancelled,
        code: 'cancelled',
      );

  factory PrintOutcome.failed({
    required String code,
    String? debugDetail,
  }) =>
      PrintOutcome._(
        kind: PrintOutcomeKind.failed,
        code: code,
        debugDetail: debugDetail,
      );

  factory PrintOutcome.unsupportedConfig(PrinterType type) =>
      PrintOutcome._(
        kind: PrintOutcomeKind.unsupportedConfig,
        code: 'unsupported_config',
        unsupportedType: type,
      );

  bool get isSubmitted => kind == PrintOutcomeKind.submitted;

  bool get isCancelled => kind == PrintOutcomeKind.cancelled;

  bool get shouldShowOperatorError =>
      kind == PrintOutcomeKind.failed ||
      kind == PrintOutcomeKind.unsupportedConfig;
}
