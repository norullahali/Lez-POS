// lib/core/printing/printer_adapter.dart
//
// Abstract contract that every printer adapter must implement.
// Callers always go through PrintManager, never through adapters directly.

import '../../features/pos/models/invoice_models.dart';

/// Base class for all printer adapters.
///
/// Each concrete adapter handles exactly one [PrinterType] and encapsulates all
/// protocol-specific I/O (PDF rendering, TCP socket, USB port write, BT stream).
abstract class PrinterAdapter {
  const PrinterAdapter();

  /// Prints [data] on the configured printer.
  ///
  /// Throws on unrecoverable errors so callers can show user-visible feedback.
  Future<void> print(InvoiceData data);

  /// Returns true when the printer is currently reachable.
  ///
  /// - [PdfPrinterAdapter]: always true (OS handles availability).
  /// - Thermal adapters: should ping or attempt connection.
  Future<bool> isAvailable();
}
