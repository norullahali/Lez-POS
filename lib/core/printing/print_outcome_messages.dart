// lib/core/printing/print_outcome_messages.dart
//
// Operator-facing Arabic strings for print outcomes (B41 Stage 2).

import 'print_outcome.dart';
import 'unsupported_printer_type_exception.dart';

/// Short SnackBar text for failed / unsupported print attempts.
String printFailureMessageAr(PrintOutcome outcome) {
  if (outcome.kind == PrintOutcomeKind.unsupportedConfig &&
      outcome.unsupportedType != null) {
    return UnsupportedPrinterTypeException(outcome.unsupportedType!)
        .messageAr;
  }

  return switch (outcome.code) {
    'printer_not_found' =>
      'تعذر العثور على الطابعة. تحقق من اسم الطابعة في إعدادات الفاتورة.',
    'printer_write_failed' =>
      'تعذر إرسال البيانات إلى الطابعة. تحقق من اتصال الطابعة وحاول مرة أخرى.',
    'pdf_build_failed' => 'تعذر إنشاء ملف PDF للفاتورة.',
    'pdf_layout_failed' => 'تعذر فتح نافذة الطباعة.',
    _ => 'تعذر إتمام الطباعة. تحقق من إعدادات الطابعة وحاول مرة أخرى.',
  };
}

/// After checkout: sale saved, print did not succeed (not for cancellation).
String checkoutPrintFailureMessageAr(PrintOutcome outcome) {
  if (outcome.isCancelled) return '';
  final detail = printFailureMessageAr(outcome);
  if (detail.contains('Ctrl+P')) return detail;
  return 'تم حفظ الفاتورة، لكن تعذرت طباعتها. '
      'يمكنك إعادة المحاولة باستخدام Ctrl+P.';
}

/// Settings test print — success wording (submission, not paper proof).
String testPrintSuccessMessageAr(PrintDeliveryKind kind) => switch (kind) {
      PrintDeliveryKind.pdfDialog =>
        'تم إرسال الطباعة التجريبية إلى نافذة الطباعة.',
      PrintDeliveryKind.usbRawSpooler =>
        'تم إرسال الطباعة التجريبية إلى قائمة انتظار الطابعة.',
    };
