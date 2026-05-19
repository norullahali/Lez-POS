// lib/core/printing/discovery/printer_discovery.dart
//
// Printer auto-discovery abstraction layer.
//
// Design goals:
//   1. Provide a stable interface today (NoOpPrinterDiscovery) that returns
//      an empty list so callers compile and run without errors.
//   2. Real implementations can be added per-transport without touching callers:
//      - WindowsUsbPrinterDiscovery  (win32 EnumPrinters)
//      - LanPrinterDiscovery         (mDNS / SNMP scan)
//      - BluetoothPrinterDiscovery   (Bluetooth LE/classic scan)
//
// Usage:
//   final discovery = NoOpPrinterDiscovery();
//   final printers  = await discovery.discover();
//
// When real discovery is needed, inject the appropriate implementation:
//   final discovery = LanPrinterDiscovery(subnet: '192.168.1');
//   final printers  = await discovery.discover();

import 'package:flutter/foundation.dart';

import '../printer_capabilities.dart';

// ---------------------------------------------------------------------------
// DiscoveredPrinter — a single printer found during discovery
// ---------------------------------------------------------------------------

/// A printer that was found during a discovery scan.
class DiscoveredPrinter {
  /// Human-readable name (OS name, mDNS hostname, or BT device name).
  final String name;

  /// How this printer is connected.
  final ConnectionType connectionType;

  /// IP address (LAN), MAC address (USB/BT), or OS path (Windows USB port).
  final String? address;

  /// Port number. Only meaningful for [ConnectionType.lan]. Default: 9100.
  final int port;

  /// Whether the printer responded to a capability probe.
  /// false = discovered by name only (no live check performed yet).
  final bool isReachable;

  const DiscoveredPrinter({
    required this.name,
    required this.connectionType,
    this.address,
    this.port = 9100,
    this.isReachable = false,
  });

  @override
  String toString() =>
      'DiscoveredPrinter(name=$name, conn=${connectionType.name}, '
      'addr=$address:$port, reachable=$isReachable)';
}

// ---------------------------------------------------------------------------
// PrinterDiscovery — abstract interface
// ---------------------------------------------------------------------------

/// Contract for all printer discovery implementations.
abstract class PrinterDiscovery {
  const PrinterDiscovery();

  /// Scans for available printers and returns the discovered list.
  ///
  /// May return an empty list if:
  ///   - No printers are found on the network/port.
  ///   - Discovery is not implemented yet ([NoOpPrinterDiscovery]).
  ///   - Platform does not support the scan type.
  ///
  /// Should not throw; log and return [] on failure.
  Future<List<DiscoveredPrinter>> discover();
}

// ---------------------------------------------------------------------------
// NoOpPrinterDiscovery — safe placeholder (no real scan)
// ---------------------------------------------------------------------------

/// Safe placeholder that returns an empty list immediately.
///
/// Use this until a real implementation is wired in.
/// Replace with platform-specific discovery in future phases:
///
/// Phase USB  : WindowsUsbPrinterDiscovery  (win32 EnumPrinters)
/// Phase LAN  : LanPrinterDiscovery         (ARP + port 9100 probe / mDNS)
/// Phase BT   : BluetoothPrinterDiscovery   (BT device scan)
class NoOpPrinterDiscovery extends PrinterDiscovery {
  const NoOpPrinterDiscovery();

  @override
  Future<List<DiscoveredPrinter>> discover() async {
    debugPrint(
      '[PrinterDiscovery] Auto-discovery not yet implemented. '
      'Returning empty list. Configure printer manually in Settings.',
    );
    return const [];
  }
}

// ---------------------------------------------------------------------------
// LanPrinterDiscovery (stub — TODO)
// ---------------------------------------------------------------------------

/// LAN discovery stub.
///
/// TODO(discovery-lan):
///   1. Enumerate addresses in [subnet].0/24.
///   2. For each address, attempt Socket.connect(addr, 9100) with 300 ms timeout.
///   3. If connection succeeds, add [DiscoveredPrinter] with [isReachable] = true.
///   4. Run all probes concurrently with Future.wait for speed.
class LanPrinterDiscovery extends PrinterDiscovery {
  /// e.g. '192.168.1' to scan 192.168.1.1–254.
  final String subnet;

  const LanPrinterDiscovery({required this.subnet});

  @override
  Future<List<DiscoveredPrinter>> discover() async {
    debugPrint(
      '[LanPrinterDiscovery] LAN scan for subnet $subnet.x '
      'not yet implemented. Returning empty list.',
    );
    // TODO(discovery-lan): implement TCP probe loop.
    return const [];
  }
}

// ---------------------------------------------------------------------------
// WindowsUsbPrinterDiscovery (stub — TODO)
// ---------------------------------------------------------------------------

/// Windows USB printer discovery stub.
///
/// TODO(discovery-usb):
///   1. Call win32 EnumPrinters(PRINTER_ENUM_LOCAL, ...) via FFI / win32 package.
///   2. Map each PRINTER_INFO_2 entry to a [DiscoveredPrinter].
///   3. Filter to printers that are not in error state.
class WindowsUsbPrinterDiscovery extends PrinterDiscovery {
  const WindowsUsbPrinterDiscovery();

  @override
  Future<List<DiscoveredPrinter>> discover() async {
    debugPrint(
      '[WindowsUsbPrinterDiscovery] EnumPrinters not yet implemented. '
      'Returning empty list.',
    );
    // TODO(discovery-usb): call win32 EnumPrinters via FFI.
    return const [];
  }
}
