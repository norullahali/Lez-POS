// lib/core/printing/print_manager.dart
//
// Central entry point for all printing in Lez POS.
//
// Architecture:
//
//   printSale() / printPurchaseInvoice() / ...
//         |
//         v
//    PrintManager.print(InvoiceData)
//         |
//         |-- PrinterType.pdf            --> PdfPrinterAdapter
//         |                                    InvoicePdfBuilderClean (layout)
//         |                                    package:printing (delivery)
//         |
//         |-- PrinterType.usbThermal     --> UsbThermalPrinterAdapter
//         |                                    ThermalPrinterAdapter (base)
//         |                                    EscPosBuilder (bytes)
//         |                                    win32 WritePrinter [TODO]
//         |
//         |-- PrinterType.lanThermal     --> LanThermalPrinterAdapter
//         |                                    ThermalPrinterAdapter (base)
//         |                                    EscPosBuilder (bytes)
//         |                                    dart:io Socket [TODO]
//         |
//         `-- PrinterType.bluetoothThermal -> BluetoothThermalPrinterAdapter
//                                             ThermalPrinterAdapter (base)
//                                             EscPosBuilder (bytes)
//                                             Platform BT plugin [TODO]
//
// Usage:
//   final config = await settingsService.getPrinterConfig();
//   await PrintManager(config).print(invoiceData);

import 'package:flutter/foundation.dart';

import '../../features/pos/models/invoice_models.dart';
import 'adapters/bluetooth_thermal_printer_adapter.dart';
import 'adapters/lan_thermal_printer_adapter.dart';
import 'adapters/pdf_printer_adapter.dart';
import 'adapters/usb_thermal_printer_adapter.dart';
import 'printer_adapter.dart';
import 'printer_config.dart';

/// Central printer router for Lez POS.
///
/// Instantiate with the current [PrinterConfig] from [SettingsService]
/// and call [print].  The manager selects the correct adapter, adds
/// structured debug logs, and tracks timing for each job.
class PrintManager {
  final PrinterConfig config;

  const PrintManager(this.config);

  // -- Main entry point ------------------------------------------------------

  /// Routes [data] to the correct adapter and prints it.
  ///
  /// Throws the adapter error on unrecoverable failures so the caller
  /// can show user-visible feedback (SnackBar, dialog, etc.).
  Future<void> print(InvoiceData data) async {
    _logJobStart(data);

    final adapter = _buildAdapter();
    debugPrint('[PrintManager]   Adapter      : ${adapter.runtimeType}');

    final sw = Stopwatch()..start();
    try {
      await adapter.print(data);
      sw.stop();
      debugPrint(
          '[PrintManager] ✓ Print job completed in ${sw.elapsedMilliseconds} ms');
    } catch (e, s) {
      sw.stop();
      debugPrint(
          '[PrintManager] ✗ Print job FAILED after ${sw.elapsedMilliseconds} ms');
      debugPrint('[PrintManager]   Error  : $e');
      debugPrint('[PrintManager]   Stack  : $s');
      rethrow;
    }
  }

  // -- Availability check ----------------------------------------------------

  /// Returns true when the configured printer is currently reachable.
  Future<bool> isAvailable() async {
    debugPrint(
        '[PrintManager] Checking availability for ${config.type.name} printer...');
    final available = await _buildAdapter().isAvailable();
    debugPrint('[PrintManager]   Available: $available');
    return available;
  }

  // -- Adapter factory -------------------------------------------------------

  PrinterAdapter _buildAdapter() {
    return switch (config.type) {
      PrinterType.pdf              => PdfPrinterAdapter(config),
      PrinterType.usbThermal       => UsbThermalPrinterAdapter(config),
      PrinterType.lanThermal       => LanThermalPrinterAdapter(config),
      PrinterType.bluetoothThermal => BluetoothThermalPrinterAdapter(config),
    };
  }

  // -- Debug logging ---------------------------------------------------------

  void _logJobStart(InvoiceData data) {
    debugPrint('[PrintManager] === Print job started =======================');
    debugPrint('[PrintManager]   Printer type : ${config.type.name}');
    debugPrint('[PrintManager]   Paper size   : ${config.paperSize.name}');
    debugPrint('[PrintManager]   Printer name : ${config.printerName ?? "(OS default)"}');
    if (config.printerIp != null) {
      debugPrint('[PrintManager]   Printer IP   : ${config.printerIp}:${config.printerPort}');
    }
    if (config.bluetoothDeviceId != null) {
      debugPrint('[PrintManager]   BT device    : ${config.bluetoothDeviceId}');
    }
    debugPrint('[PrintManager]   Invoice #    : ${data.invoiceNumber}');
    debugPrint('[PrintManager]   Store        : ${data.storeName}');
    debugPrint('[PrintManager]   Items        : ${data.items.length}');
    debugPrint('[PrintManager]   Total        : ${data.total} IQD');
    debugPrint('[PrintManager] ---------------------------------------------');
  }
}
