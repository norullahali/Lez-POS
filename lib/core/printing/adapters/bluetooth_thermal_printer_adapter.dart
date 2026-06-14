// lib/core/printing/adapters/bluetooth_thermal_printer_adapter.dart
//
// ESC/POS printing over Bluetooth RFCOMM.
// Extends ThermalPrinterAdapter — ESC/POS byte building and job logging
// are handled by the base class.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:lez_pos/core/utils/receipt_paper_size.dart';
import '../printer_capabilities.dart';
import '../thermal/thermal_printer_adapter.dart';

/// Bluetooth ESC/POS thermal printer adapter.
///
/// STATUS: Placeholder — [sendBytes] throws [UnimplementedError].
///         [isAvailable] returns false until transport is wired.
///
/// TODO(thermal-bt) — implementation plan (platform-specific):
///
///   Windows:
///     Use Winsock2 RFCOMM socket via dart:ffi / win32 package.
///     Target: config.bluetoothDeviceId (MAC address).
///
///   Android / iOS (future mobile port):
///     Use a Bluetooth plugin (flutter_bluetooth_serial or similar).
///     Note: iOS requires MFi-certified printer for standard SPP.
///
///   Steps:
///     1. Pair the device out-of-band via OS Bluetooth settings.
///     2. Open an RFCOMM connection to config.bluetoothDeviceId.
///     3. sendBytes — write the ESC/POS Uint8List to the stream.
///     4. Flush and close the connection.
class BluetoothThermalPrinterAdapter extends ThermalPrinterAdapter {
  const BluetoothThermalPrinterAdapter(super.config);

  @override
  PrinterCapabilities get capabilities {
    // Bluetooth printers are typically 58 mm; override via config if needed.
    return config.paperSize == ReceiptPaperSize.thermal80
        ? const PrinterCapabilities(
            connectionType: ConnectionType.bluetooth,
            paperWidth: '80mm',
            charsPerLine: 48,
            supportsCut: true,
            codePageId: 33,
          )
        : PrinterCapabilities.thermal58Bt;
  }

  @override
  Future<void> sendBytes(Uint8List bytes) async {
    debugPrint('[BluetoothThermalPrinterAdapter] Device  : '
        '${config.bluetoothDeviceId ?? "(none set)"}');
    debugPrint('[BluetoothThermalPrinterAdapter] Bytes   : ${bytes.length}');

    // TODO(thermal-bt): connect via RFCOMM and write bytes.
    throw UnimplementedError(
      'Bluetooth thermal printing is not yet implemented. '
      'Switch printer type to "pdf" in Settings.',
    );
  }

  @override
  Future<bool> isAvailable() async {
    debugPrint('[BluetoothThermalPrinterAdapter] isAvailable — '
        'BT probe not implemented, returning false.');
    // TODO(thermal-bt): check that the device is paired and reachable.
    return false;
  }
}
