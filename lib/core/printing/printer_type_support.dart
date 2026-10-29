// lib/core/printing/printer_type_support.dart
//
// Single source of truth for which [PrinterType] values have a working
// print-delivery path in the current application build.

import 'printer_config.dart';

abstract final class PrinterTypeSupport {
  /// Printer types that may reach a real adapter print path (B41 Stage 1).
  static const Set<PrinterType> printDeliverySupported = {
    PrinterType.pdf,
    PrinterType.usbThermal,
  };

  static bool isPrintDeliverySupported(PrinterType type) =>
      printDeliverySupported.contains(type);

  /// Whether the settings dropdown allows selecting [type] for new choices.
  static bool isSelectableInSettings(PrinterType type) =>
      isPrintDeliverySupported(type);
}
