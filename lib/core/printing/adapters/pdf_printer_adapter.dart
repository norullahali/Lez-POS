// lib/core/printing/adapters/pdf_printer_adapter.dart
//
// Delivers invoices as PDF via the operating system print dialog.
// Uses InvoicePdfBuilderClean for layout and package:printing for delivery.
// Works on Windows, macOS, and Linux without any manual driver configuration.

import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import '../../../features/pos/models/invoice_models.dart';
import '../../utils/invoice_pdf_builder_clean.dart';
import '../printer_adapter.dart';
import '../printer_config.dart';

class PdfPrinterAdapter extends PrinterAdapter {
  final PrinterConfig _config;
  final InvoicePdfBuilderClean _builder = InvoicePdfBuilderClean();

  PdfPrinterAdapter(this._config);

  @override
  Future<void> print(InvoiceData data) async {
    try {
      debugPrint('STEP 1: START PDF BUILD');

      final pdfBytes = await _builder.buildInvoice(
        data,
        paperSize: _config.paperSize,
      );

      debugPrint('STEP 2: PDF GENERATED (${pdfBytes.length} bytes)');

      await Printing.layoutPdf(
        onLayout: (format) async {
          debugPrint('STEP 3: onLayout CALLED');
          return pdfBytes;
        },
        name: 'Lez POS Invoice',
      );

      debugPrint('STEP 4: PRINT FINISHED');
    } catch (e, s) {
      debugPrint('PDF PRINT ERROR: $e');
      debugPrint('$s');
    }
  }

  @override
  Future<bool> isAvailable() async {
    return true;
  }
}
