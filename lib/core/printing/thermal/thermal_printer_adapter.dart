// lib/core/printing/thermal/thermal_printer_adapter.dart
//
// Abstract intermediate class for all ESC/POS thermal adapters.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../../features/pos/models/invoice_models.dart';
import '../adapters/usb_thermal_printer_adapter.dart';
import '../print_outcome.dart';
import '../printer_adapter.dart';
import '../printer_capabilities.dart';
import '../printer_config.dart';
import 'esc_pos_builder.dart';

abstract class ThermalPrinterAdapter extends PrinterAdapter {
  final PrinterConfig config;

  const ThermalPrinterAdapter(this.config);

  PrinterCapabilities get capabilities;

  Future<void> sendBytes(Uint8List bytes);

  PrintDeliveryKind get deliveryKind => PrintDeliveryKind.usbRawSpooler;

  @override
  @nonVirtual
  Future<PrintOutcome> print(InvoiceData data) async {
    final tag = runtimeType.toString();

    debugPrint('[$tag] -- Thermal print job started ----------------------');
    debugPrint('[$tag]   Invoice #    : ${data.invoiceNumber}');

    final sw = Stopwatch()..start();

    final Uint8List bytes;
    try {
      bytes = buildBytes(data);
      debugPrint('[$tag]   ESC/POS size : ${bytes.length} bytes');
    } catch (e, s) {
      debugPrint('[$tag] ESC/POS build FAILED: $e\n$s');
      return PrintOutcome.failed(
        code: 'escpos_build_failed',
        debugDetail: e.toString(),
      );
    }

    try {
      await sendBytes(bytes);
      sw.stop();
      debugPrint(
          '[$tag] Spooler submission OK in ${sw.elapsedMilliseconds} ms');
      return PrintOutcome.submitted(kind: deliveryKind);
    } on ArgumentError {
      rethrow;
    } on PrinterNotFoundException catch (e) {
      sw.stop();
      return PrintOutcome.failed(
        code: 'printer_not_found',
        debugDetail: e.message,
      );
    } on PrinterWriteException catch (e) {
      sw.stop();
      return PrintOutcome.failed(
        code: 'printer_write_failed',
        debugDetail: e.message,
      );
    } catch (e, s) {
      sw.stop();
      debugPrint('[$tag] sendBytes FAILED: $e\n$s');
      return PrintOutcome.failed(
        code: 'thermal_send_failed',
        debugDetail: e.toString(),
      );
    }
  }

  Uint8List buildBytes(InvoiceData data) =>
      EscPosBuilder.fromInvoice(data, capabilities);
}
