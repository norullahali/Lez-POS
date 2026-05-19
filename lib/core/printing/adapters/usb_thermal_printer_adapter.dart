// lib/core/printing/adapters/usb_thermal_printer_adapter.dart
//
// ESC/POS printing over a Windows USB (RAW) printer port.
//
// This adapter is fully implemented for Windows desktop.
// It delegates ALL win32 API calls to [RawWindowsPrinter] — this class
// contains only adapter-layer logic (capabilities, logging, error mapping).
//
// Call flow:
//   PrintManager.print(invoiceData)
//     --- UsbThermalPrinterAdapter.print(data)          [sealed in ThermalPrinterAdapter]
//           --- buildBytes(data)  → EscPosBuilder.fromInvoice(data, capabilities)
//           --- sendBytes(bytes)  → RawWindowsPrinter.send(bytes, printerName)
//                                       OpenPrinter → StartDocPrinter → StartPagePrinter
//                                       → WritePrinter → EndPagePrinter
//                                       → EndDocPrinter → ClosePrinter

import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../../core/utils/receipt_paper_size.dart';
import '../printer_capabilities.dart';
import '../printer_config.dart';
import '../thermal/thermal_printer_adapter.dart';
import '../windows/raw_windows_printer.dart';

/// Windows USB ESC/POS thermal printer adapter.
///
/// Supports both 58 mm and 80 mm thermal paper via [PrinterCapabilities].
///
/// Configuration (set in invoice settings → save → loaded by [PrinterConfig]):
///   - [PrinterConfig.printerName] — exact Windows printer name.
///     Leave empty to use the OS default printer.
///   - [PrinterConfig.paperSize]  — [ReceiptPaperSize.thermal58] or
///     [ReceiptPaperSize.thermal80] selects the correct column width.
///
/// Error handling:
///   - Empty byte buffer → [ArgumentError] (programming error, not user error).
///   - OpenPrinter failure → [PrinterNotFoundException] with win32 code.
///   - WritePrinter failure → [PrinterWriteException] with win32 code.
///   - Any failure propagates up through [ThermalPrinterAdapter.print] to
///     [PrintManager.print], which logs and re-throws so the UI can show
///     a user-visible SnackBar.
class UsbThermalPrinterAdapter extends ThermalPrinterAdapter {
  const UsbThermalPrinterAdapter(super.config);

  // -- Capabilities ---------------------------------------------------------

  @override
  PrinterCapabilities get capabilities {
    if (config.paperSize == ReceiptPaperSize.thermal58) {
      return PrinterCapabilities.thermal58Usb;
    }
    return PrinterCapabilities.thermal80Usb;
  }

  // -- Transport: sendBytes --------------------------------------------------

  @override
  Future<void> sendBytes(Uint8List bytes) async {
    final printerName = config.printerName;
    final display = (printerName == null || printerName.isEmpty)
        ? '(OS default)'
        : printerName;

    debugPrint('[UsbThermalPrinterAdapter] -- sendBytes ------------------');
    debugPrint('[UsbThermalPrinterAdapter]   Printer    : $display');
    debugPrint('[UsbThermalPrinterAdapter]   Paper size : ${config.paperSize.name}');
    debugPrint('[UsbThermalPrinterAdapter]   Byte count : ${bytes.length}');
    debugPrint('[UsbThermalPrinterAdapter]   Cols/line  : ${capabilities.charsPerLine}');

    if (bytes.isEmpty) {
      const msg = 'ESC/POS byte buffer is empty — nothing to send to printer.';
      debugPrint('[UsbThermalPrinterAdapter] ✗ $msg');
      throw ArgumentError(msg);
    }

    final result = await RawWindowsPrinter.send(
      bytes: bytes,
      printerName: printerName,
      docName: 'Lez POS',
    );

    if (!result.ok) {
      debugPrint('[UsbThermalPrinterAdapter] ✗ RAW send failed: ${result.errorMessage}');
      _throwFromResult(result, display);
    }

    debugPrint(
        '[UsbThermalPrinterAdapter] ✓ ${result.bytesWritten} bytes sent '
        'to "$display" in ${result.elapsedMs} ms.');
  }

  // -- Availability check ----------------------------------------------------

  @override
  Future<bool> isAvailable() async {
    final printerName = config.printerName;
    final display = (printerName == null || printerName.isEmpty)
        ? '(OS default)'
        : printerName;
    debugPrint(
        '[UsbThermalPrinterAdapter] isAvailable check for "$display"...');
    final available =
        await RawWindowsPrinter.checkAvailable(printerName);
    debugPrint(
        '[UsbThermalPrinterAdapter]   → ${available ? "✓ reachable" : "✗ not reachable"}');
    return available;
  }

  // -- Private helpers -------------------------------------------------------

  /// Maps a failed [RawPrintResult] to a descriptive exception.
  Never _throwFromResult(RawPrintResult result, String displayName) {
    final msg = result.errorMessage ?? 'Unknown printer error';
    final code = result.win32ErrorCode;

    // win32 error 0x2 (2)  = ERROR_FILE_NOT_FOUND — printer name wrong
    // win32 error 0x6 (6)  = ERROR_INVALID_HANDLE  — handle already closed
    // win32 error 0x5 (5)  = ERROR_ACCESS_DENIED   — permissions issue
    // win32 error 0x1771 (6001) = ERROR_PRINTER_NOT_FOUND (may vary)
    if (code == 2 || code == 1801) {
      throw PrinterNotFoundException(
        'Printer "$displayName" not found. '
        'Check the printer name in invoice settings and ensure the '
        'printer is installed in Windows. Win32: $code',
      );
    }

    throw PrinterWriteException(
      'Failed to send ESC/POS bytes to "$displayName": $msg',
      win32Code: code,
    );
  }
}

// ---------------------------------------------------------------------------
// Typed exceptions for the USB adapter
// ---------------------------------------------------------------------------

/// Thrown when the target printer cannot be opened (wrong name, not installed).
class PrinterNotFoundException implements Exception {
  final String message;
  const PrinterNotFoundException(this.message);

  @override
  String toString() => 'PrinterNotFoundException: $message';
}

/// Thrown when WritePrinter returns FALSE or partial bytes are written.
class PrinterWriteException implements Exception {
  final String message;
  final int? win32Code;

  const PrinterWriteException(this.message, {this.win32Code});

  @override
  String toString() => 'PrinterWriteException[$win32Code]: $message';
}
