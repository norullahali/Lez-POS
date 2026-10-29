// lib/core/printing/print_manager.dart

import 'package:flutter/foundation.dart';

import '../../features/pos/models/invoice_models.dart';
import 'adapters/bluetooth_thermal_printer_adapter.dart';
import 'adapters/lan_thermal_printer_adapter.dart';
import 'adapters/pdf_printer_adapter.dart';
import 'adapters/usb_thermal_printer_adapter.dart';
import 'print_outcome.dart';
import 'printer_adapter.dart';
import 'printer_config.dart';
import 'printer_type_support.dart';

/// Central printer router for Lez POS.
class PrintManager {
  final PrinterConfig config;

  const PrintManager(this.config);

  /// Routes [data] to the correct adapter and returns a [PrintOutcome].
  Future<PrintOutcome> print(InvoiceData data) async {
    if (!PrinterTypeSupport.isPrintDeliverySupported(config.type)) {
      debugPrint(
          '[PrintManager] Unsupported printer type: ${config.type.name}');
      return PrintOutcome.unsupportedConfig(config.type);
    }

    _logJobStart(data);

    final adapter = _buildAdapter();
    debugPrint('[PrintManager]   Adapter      : ${adapter.runtimeType}');

    final sw = Stopwatch()..start();
    try {
      final outcome = await adapter.print(data);
      sw.stop();
      debugPrint(
          '[PrintManager] Outcome: ${outcome.code} (${outcome.kind.name}) '
          'in ${sw.elapsedMilliseconds} ms');
      if (outcome.debugDetail != null) {
        debugPrint('[PrintManager]   Detail: ${outcome.debugDetail}');
      }
      return outcome;
    } catch (e, s) {
      sw.stop();
      debugPrint(
          '[PrintManager] Unexpected error after ${sw.elapsedMilliseconds} ms');
      debugPrint('[PrintManager]   Error  : $e');
      debugPrint('[PrintManager]   Stack  : $s');
      rethrow;
    }
  }

  Future<bool> isAvailable() async {
    debugPrint(
        '[PrintManager] Checking availability for ${config.type.name} printer...');
    if (!PrinterTypeSupport.isPrintDeliverySupported(config.type)) {
      debugPrint('[PrintManager]   Available: false (type not supported)');
      return false;
    }
    final available = await _buildAdapter().isAvailable();
    debugPrint('[PrintManager]   Available: $available');
    return available;
  }

  PrinterAdapter _buildAdapter() {
    return switch (config.type) {
      PrinterType.pdf              => PdfPrinterAdapter(config),
      PrinterType.usbThermal       => UsbThermalPrinterAdapter(config),
      PrinterType.lanThermal       => LanThermalPrinterAdapter(config),
      PrinterType.bluetoothThermal => BluetoothThermalPrinterAdapter(config),
    };
  }

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
