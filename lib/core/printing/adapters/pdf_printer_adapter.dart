// lib/core/printing/adapters/pdf_printer_adapter.dart
//
// Delivers invoices as PDF via the operating system print dialog.
// Uses InvoicePdfBuilderClean for layout and package:printing for delivery.
// Works on Windows, macOS, and Linux without any manual driver configuration.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import '../../../features/pos/models/invoice_models.dart';
import '../../utils/invoice_pdf_builder_clean.dart';
import '../print_outcome.dart';
import '../printer_adapter.dart';
import '../printer_config.dart';

/// Test seam: override in unit tests to simulate layout/cancel/errors.
@visibleForTesting
Future<bool> Function({
  required LayoutCallback onLayout,
  String name,
}) pdfLayoutPdfInvoker = ({
  required LayoutCallback onLayout,
  String name = 'Document',
}) =>
    Printing.layoutPdf(onLayout: onLayout, name: name);

class PdfPrinterAdapter extends PrinterAdapter {
  final PrinterConfig _config;
  final InvoicePdfBuilderClean _builder = InvoicePdfBuilderClean();

  PdfPrinterAdapter(this._config);

  @override
  Future<PrintOutcome> print(InvoiceData data) async {
    final Uint8List pdfBytes;
    try {
      debugPrint('[PdfPrinterAdapter] Building PDF...');
      pdfBytes = await _builder.buildInvoice(
        data,
        paperSize: _config.paperSize,
      );
      debugPrint(
          '[PdfPrinterAdapter] PDF generated (${pdfBytes.length} bytes)');
    } catch (e, s) {
      debugPrint('[PdfPrinterAdapter] PDF build failed: $e\n$s');
      return PrintOutcome.failed(
        code: 'pdf_build_failed',
        debugDetail: e.toString(),
      );
    }

    try {
      final printed = await pdfLayoutPdfInvoker(
        onLayout: (format) async => pdfBytes,
        name: 'Lez POS Invoice',
      );

      if (!printed) {
        debugPrint('[PdfPrinterAdapter] Print dialog cancelled by user');
        return PrintOutcome.cancelled();
      }

      debugPrint('[PdfPrinterAdapter] Print dialog completed (submitted)');
      return PrintOutcome.submitted(kind: PrintDeliveryKind.pdfDialog);
    } catch (e, s) {
      debugPrint('[PdfPrinterAdapter] layoutPdf failed: $e\n$s');
      return PrintOutcome.failed(
        code: 'pdf_layout_failed',
        debugDetail: e.toString(),
      );
    }
  }

  @override
  Future<bool> isAvailable() async {
    return true;
  }
}
