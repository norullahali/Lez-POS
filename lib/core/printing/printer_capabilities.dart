// lib/core/printing/printer_capabilities.dart
//
// Describes what a specific printer hardware unit can and cannot do.
// Passed from PrintManager → ThermalPrinterAdapter → EscPosBuilder so
// the byte stream is tailored to the actual hardware.

// ---------------------------------------------------------------------------
// ConnectionType
// ---------------------------------------------------------------------------

/// Physical transport channel between the host and the printer.
enum ConnectionType {
  /// OS PDF pipeline — no direct hardware access.
  pdf,

  /// USB cable, Windows RAW port (WritePrinter API).
  usb,

  /// TCP/IP socket, typically port 9100.
  lan,

  /// Bluetooth RFCOMM serial profile.
  bluetooth,
}

// ---------------------------------------------------------------------------
// PrinterCapabilities
// ---------------------------------------------------------------------------

/// Describes a printer's static hardware features.
///
/// Used by [EscPosBuilder] to emit the correct command variants and by
/// [PrintManager] to validate whether a job can be fulfilled.
///
/// Create a [PrinterCapabilities] from the active [PrinterConfig] via the
/// [PrinterCapabilities.fromConfig] factory.
class PrinterCapabilities {
  /// Physical connection used to reach this printer.
  final ConnectionType connectionType;

  /// Human-readable paper width label, e.g. '58mm', '80mm', 'A4'.
  final String paperWidth;

  /// Number of printable characters per line at the default font size.
  ///
  /// Standard values:
  ///   58 mm paper → 32 chars
  ///   80 mm paper → 48 chars
  ///   A4 PDF      → 80 chars (logical, not hardware)
  final int charsPerLine;

  /// Whether the printer has a physical paper cutter.
  final bool supportsCut;

  /// Whether the printer has a cash-drawer kick port.
  final bool supportsDrawerKick;

  /// Whether the printer can print greyscale images (uncommon on thermal).
  final bool supportsGrayscale;

  /// ESC/POS code page identifier understood by the printer firmware.
  ///
  /// Common values:
  ///   0   = PC437 (USA/Standard Latin)
  ///   17  = PC864 (Arabic)
  ///   33  = CP1256 (Windows Arabic)
  ///   255 = UTF-8 (newer Epson/Star firmware)
  ///
  /// null = use printer default (PC437).
  final int? codePageId;

  const PrinterCapabilities({
    required this.connectionType,
    required this.paperWidth,
    required this.charsPerLine,
    this.supportsCut = false,
    this.supportsDrawerKick = false,
    this.supportsGrayscale = false,
    this.codePageId,
  });

  // -- Named presets --------------------------------------------------------

  /// Typical 58 mm USB thermal printer (e.g. XP-58).
  static const PrinterCapabilities thermal58Usb = PrinterCapabilities(
    connectionType: ConnectionType.usb,
    paperWidth: '58mm',
    charsPerLine: 32,
    supportsCut: true,
    codePageId: 33, // CP1256 Arabic
  );

  /// Typical 80 mm USB thermal printer (e.g. Epson TM-T20, XP-80).
  static const PrinterCapabilities thermal80Usb = PrinterCapabilities(
    connectionType: ConnectionType.usb,
    paperWidth: '80mm',
    charsPerLine: 48,
    supportsCut: true,
    supportsDrawerKick: true,
    codePageId: 33, // CP1256 Arabic
  );

  /// Typical 80 mm LAN thermal printer.
  static const PrinterCapabilities thermal80Lan = PrinterCapabilities(
    connectionType: ConnectionType.lan,
    paperWidth: '80mm',
    charsPerLine: 48,
    supportsCut: true,
    supportsDrawerKick: true,
    codePageId: 33,
  );

  /// Typical 58 mm Bluetooth thermal printer (e.g. Goojprt PT-200).
  static const PrinterCapabilities thermal58Bt = PrinterCapabilities(
    connectionType: ConnectionType.bluetooth,
    paperWidth: '58mm',
    charsPerLine: 32,
    supportsCut: false,
    codePageId: 33,
  );

  /// PDF output — virtual capabilities (layout engine handles everything).
  static const PrinterCapabilities pdfVirtual = PrinterCapabilities(
    connectionType: ConnectionType.pdf,
    paperWidth: 'A4',
    charsPerLine: 80,
    supportsGrayscale: true,
  );

  // -- Debug ----------------------------------------------------------------

  @override
  String toString() =>
      'PrinterCapabilities(conn=${connectionType.name}, paper=$paperWidth, '
      'cols=$charsPerLine, cut=$supportsCut, drawer=$supportsDrawerKick, '
      'cp=$codePageId)';
}
