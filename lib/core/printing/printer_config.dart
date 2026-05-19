// lib/core/printing/printer_config.dart
//
// PrinterType enum, persistence key constants, and the immutable
// PrinterConfig value object used everywhere in the printing pipeline.

import '../utils/receipt_paper_size.dart';

// ---------------------------------------------------------------------------
// PrinterType
// ---------------------------------------------------------------------------

enum PrinterType {
  pdf,
  usbThermal,
  lanThermal,
  bluetoothThermal,
}

// ---------------------------------------------------------------------------
// PrinterSettingsKeys
// ---------------------------------------------------------------------------

abstract class PrinterSettingsKeys {
  static const String printerType        = 'printer_type';
  static const String printerName        = 'printer_name';
  static const String printerIp          = 'printer_ip';
  static const String printerPort        = 'printer_port';
  static const String bluetoothDeviceId  = 'bluetooth_device_id';
  static const String receiptPaperSize   = 'receipt_paper_size';
}

// ---------------------------------------------------------------------------
// PrinterConfig
// ---------------------------------------------------------------------------

class PrinterConfig {
  final PrinterType type;
  final String? printerName;
  final String? printerIp;
  final int printerPort;
  final String? bluetoothDeviceId;
  final ReceiptPaperSize paperSize;

  const PrinterConfig({
    this.type = PrinterType.pdf,
    this.printerName,
    this.printerIp,
    this.printerPort = 9100,
    this.bluetoothDeviceId,
    this.paperSize = ReceiptPaperSize.thermal80,
  });

  static const PrinterConfig defaults = PrinterConfig();

  static ReceiptPaperSize parsePaperSize(String? raw) {
    switch (raw) {
      case '58':
        return ReceiptPaperSize.thermal58;
      case 'a4':
        return ReceiptPaperSize.a4;
      default:
        return ReceiptPaperSize.thermal80;
    }
  }

  static String paperSizeToString(ReceiptPaperSize size) {
    switch (size) {
      case ReceiptPaperSize.thermal58:
        return '58';
      case ReceiptPaperSize.a4:
        return 'a4';
      case ReceiptPaperSize.thermal80:
        return '80';
    }
  }

  @override
  String toString() =>
      'PrinterConfig(type=${type.name}, paper=${paperSize.name}, '
      'name=$printerName, ip=$printerIp:$printerPort, bt=$bluetoothDeviceId)';
}
