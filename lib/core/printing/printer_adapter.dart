// lib/core/printing/printer_adapter.dart
//
// Abstract contract that every printer adapter must implement.
// Callers always go through PrintManager, never through adapters directly.

import '../../features/pos/models/invoice_models.dart';
import 'print_outcome.dart';

/// Base class for all printer adapters.
///
/// Each concrete adapter handles exactly one [PrinterType] and encapsulates all
/// protocol-specific I/O (PDF rendering, TCP socket, USB port write, BT stream).
abstract class PrinterAdapter {
  const PrinterAdapter();

  /// Prints [data] on the configured printer.
  ///
  /// Returns a structured [PrintOutcome]; does not throw for expected failures.
  Future<PrintOutcome> print(InvoiceData data);

  /// Returns true when the printer is currently reachable.
  ///
  /// - [PdfPrinterAdapter]: always true (OS handles availability).
  /// - Thermal adapters: should ping or attempt connection.
  Future<bool> isAvailable();
}
