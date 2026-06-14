// lib/core/printing/adapters/lan_thermal_printer_adapter.dart
//
// ESC/POS printing over TCP/IP (LAN thermal printer).
// Extends ThermalPrinterAdapter — ESC/POS byte building and job logging
// are handled by the base class.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:lez_pos/core/utils/receipt_paper_size.dart';
import '../printer_capabilities.dart';
import '../thermal/thermal_printer_adapter.dart';

/// LAN ESC/POS thermal printer adapter (TCP/IP, default port 9100).
///
/// STATUS: Placeholder — [sendBytes] throws [UnimplementedError].
///         [isAvailable] returns false until transport is wired.
///
/// TODO(thermal-lan) — implementation plan:
///   1. In [sendBytes]:
///      a. Socket.connect(config.printerIp!, config.printerPort)
///         with a 5-second connection timeout.
///      b. socket.add(bytes).
///      c. await socket.flush().
///      d. await socket.close().
///   2. In [isAvailable]:
///      Try Socket.connect with a 2-second timeout.
///      Catch SocketException → return false.
///      Close immediately on success → return true.
class LanThermalPrinterAdapter extends ThermalPrinterAdapter {
  const LanThermalPrinterAdapter(super.config);

  @override
  PrinterCapabilities get capabilities {
    return config.paperSize == ReceiptPaperSize.thermal58
        ? const PrinterCapabilities(
            connectionType: ConnectionType.lan,
            paperWidth: '58mm',
            charsPerLine: 32,
            supportsCut: true,
            codePageId: 33,
          )
        : PrinterCapabilities.thermal80Lan;
  }

  @override
  Future<void> sendBytes(Uint8List bytes) async {
    final target = '${config.printerIp ?? "?"}: ${config.printerPort}';
    debugPrint('[LanThermalPrinterAdapter] Target   : $target');
    debugPrint('[LanThermalPrinterAdapter] Bytes    : ${bytes.length}');

    // TODO(thermal-lan): open dart:io Socket, write bytes, flush and close.
    throw UnimplementedError(
      'LAN thermal printing is not yet implemented. '
      'Switch printer type to "pdf" in Settings.',
    );
  }

  @override
  Future<bool> isAvailable() async {
    debugPrint('[LanThermalPrinterAdapter] isAvailable — '
        'TCP probe not implemented, returning false.');
    // TODO(thermal-lan): Socket.connect with 2-second timeout.
    return false;
  }
}
