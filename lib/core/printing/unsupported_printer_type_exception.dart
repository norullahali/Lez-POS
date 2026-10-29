// lib/core/printing/unsupported_printer_type_exception.dart

import 'printer_config.dart';

/// Thrown when [PrintManager] is asked to print using a [PrinterType] that
/// has no operational delivery implementation yet.
class UnsupportedPrinterTypeException implements Exception {
  final PrinterType type;

  const UnsupportedPrinterTypeException(this.type);

  /// Arabic message suitable for settings test-print feedback.
  String get messageAr =>
      'نوع الطابعة "${_typeLabelAr(type)}" غير مدعوم حالياً للطباعة. '
      'اختر طابعة PDF أو USB من الإعدادات، أو انتظر دعم هذا النوع لاحقاً.';

  @override
  String toString() =>
      'UnsupportedPrinterTypeException(${type.name}): $messageAr';

  static String _typeLabelAr(PrinterType type) => switch (type) {
        PrinterType.pdf => 'PDF',
        PrinterType.usbThermal => 'USB حرارية',
        PrinterType.lanThermal => 'شبكة (LAN)',
        PrinterType.bluetoothThermal => 'بلوتوث',
      };
}
