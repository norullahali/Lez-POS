// lib/core/printing/thermal/thermal_printer_adapter.dart
//
// Abstract intermediate class for all ESC/POS thermal adapters.
//
// Class hierarchy:
//   PrinterAdapter                         (printer_adapter.dart)
//   --- ThermalPrinterAdapter              ← this file
//       --- UsbThermalPrinterAdapter
//       --- LanThermalPrinterAdapter
//       --- BluetoothThermalPrinterAdapter
//
// Subclasses implement only [sendBytes] (transport I/O) and [capabilities]
// (hardware feature flags).  The [print] orchestration, ESC/POS build step,
// and structured debug logging are sealed here.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../../features/pos/models/invoice_models.dart';
import '../printer_adapter.dart';
import '../printer_capabilities.dart';
import '../printer_config.dart';
import 'esc_pos_builder.dart';

/// Abstract base for all ESC/POS thermal printer adapters.
///
/// Concrete subclasses must override:
///   - [capabilities] — return the correct [PrinterCapabilities] preset.
///   - [sendBytes]    — write raw bytes to the physical transport.
abstract class ThermalPrinterAdapter extends PrinterAdapter {
  final PrinterConfig config;

  const ThermalPrinterAdapter(this.config);

  // -- Abstract API (subclasses must implement) ------------------------------

  /// Hardware capability descriptor for this adapter instance.
  PrinterCapabilities get capabilities;

  /// Write [bytes] to the printer via the concrete transport layer.
  ///
  /// - USB adapter  : calls win32 WritePrinter.
  /// - LAN adapter  : writes to a TCP socket.
  /// - BT adapter   : writes to a Bluetooth RFCOMM stream.
  ///
  /// Throws on transport failure (connection refused, device missing, etc.).
  Future<void> sendBytes(Uint8List bytes);

  // -- Sealed print orchestration (do not override) --------------------------

  @override
  @nonVirtual
  Future<void> print(InvoiceData data) async {
    final tag = runtimeType.toString();

    debugPrint('[$tag] -- Thermal print job started ----------------------');
    debugPrint('[$tag]   Invoice #    : ${data.invoiceNumber}');
    debugPrint('[$tag]   Items        : ${data.items.length}');
    debugPrint('[$tag]   Total        : ${data.total} IQD');
    debugPrint('[$tag]   Paper size   : ${config.paperSize.name}');
    debugPrint('[$tag]   Capabilities : $capabilities');

    final sw = Stopwatch()..start();

    // Step 1 — Build ESC/POS byte stream
    final Uint8List bytes;
    try {
      bytes = buildBytes(data);
      debugPrint('[$tag]   ESC/POS size : ${bytes.length} bytes '
          '(built in ${sw.elapsedMilliseconds} ms)');
    } catch (e, s) {
      debugPrint('[$tag] ✗ ESC/POS build FAILED: $e\n$s');
      rethrow;
    }

    // Step 2 — Send to hardware
    try {
      await sendBytes(bytes);
      sw.stop();
      debugPrint('[$tag] ✓ Print job completed in ${sw.elapsedMilliseconds} ms');
    } catch (e, s) {
      sw.stop();
      debugPrint(
          '[$tag] ✗ sendBytes FAILED after ${sw.elapsedMilliseconds} ms: $e\n$s');
      rethrow;
    }
  }

  // -- ESC/POS byte builder (override to customise) --------------------------

  /// Converts [InvoiceData] to an ESC/POS [Uint8List] via [EscPosBuilder.fromInvoice].
  ///
  /// Subclasses may override to prepend/append adapter-specific commands
  /// (e.g. logo download, beep, drawer kick).
  Uint8List buildBytes(InvoiceData data) =>
      EscPosBuilder.fromInvoice(data, capabilities);
}
