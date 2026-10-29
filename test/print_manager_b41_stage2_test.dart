import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/printing/adapters/pdf_printer_adapter.dart';
import 'package:lez_pos/core/printing/adapters/usb_thermal_printer_adapter.dart';
import 'package:lez_pos/core/printing/print_manager.dart';
import 'package:lez_pos/core/printing/print_outcome.dart';
import 'package:lez_pos/core/printing/print_outcome_messages.dart';
import 'package:lez_pos/core/printing/printer_capabilities.dart';
import 'package:lez_pos/core/printing/printer_config.dart';
import 'package:lez_pos/core/printing/thermal/thermal_printer_adapter.dart';
import 'package:lez_pos/features/pos/models/invoice_models.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

InvoiceData _minimalInvoice() => InvoiceData(
      invoiceNumber: 'T-1',
      storeName: 'Test Store',
      items: [
        InvoiceItem(name: 'Item', qty: 1, unitPrice: 1000, lineTotal: 1000),
      ],
      total: 1000,
    );

InvoiceData _emptyItemsInvoice() => InvoiceData(
      invoiceNumber: 'T-0',
      storeName: 'Test Store',
      items: const [],
      total: 0,
    );

class _HarnessThermal extends ThermalPrinterAdapter {
  _HarnessThermal(super.config, this._sendImpl);

  final Future<void> Function(Uint8List bytes) _sendImpl;

  @override
  PrinterCapabilities get capabilities => PrinterCapabilities.thermal80Usb;

  @override
  Future<void> sendBytes(Uint8List bytes) => _sendImpl(bytes);

  @override
  Future<bool> isAvailable() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfPrinterAdapter outcomes', () {
    tearDown(() {
      pdfLayoutPdfInvoker = ({
        required LayoutCallback onLayout,
        String name = 'Document',
      }) =>
          Printing.layoutPdf(onLayout: onLayout, name: name);
    });

    test('empty invoice maps to pdf_build_failed', () async {
      final adapter =
          PdfPrinterAdapter(const PrinterConfig(type: PrinterType.pdf));
      final outcome = await adapter.print(_emptyItemsInvoice());
      expect(outcome.kind, PrintOutcomeKind.failed);
      expect(outcome.code, 'pdf_build_failed');
    });

    test('layoutPdf false maps to cancelled', () async {
      pdfLayoutPdfInvoker = ({
        required LayoutCallback onLayout,
        String name = 'Document',
      }) async =>
          false;

      final adapter =
          PdfPrinterAdapter(const PrinterConfig(type: PrinterType.pdf));
      final outcome = await adapter.print(_minimalInvoice());
      expect(outcome.kind, PrintOutcomeKind.cancelled);
    });

    test('layoutPdf true maps to submitted pdfDialog', () async {
      pdfLayoutPdfInvoker = ({
        required LayoutCallback onLayout,
        String name = 'Document',
      }) async {
        await onLayout(PdfPageFormat.standard);
        return true;
      };

      final adapter =
          PdfPrinterAdapter(const PrinterConfig(type: PrinterType.pdf));
      final outcome = await adapter.print(_minimalInvoice());
      expect(outcome.kind, PrintOutcomeKind.submitted);
      expect(outcome.deliveryKind, PrintDeliveryKind.pdfDialog);
    });

    test('layoutPdf throw maps to failed pdf_layout_failed', () async {
      pdfLayoutPdfInvoker = ({
        required LayoutCallback onLayout,
        String name = 'Document',
      }) async {
        throw StateError('dialog failed');
      };

      final adapter =
          PdfPrinterAdapter(const PrinterConfig(type: PrinterType.pdf));
      final outcome = await adapter.print(_minimalInvoice());
      expect(outcome.kind, PrintOutcomeKind.failed);
      expect(outcome.code, 'pdf_layout_failed');
    });
  });

  group('ThermalPrinterAdapter outcomes', () {
    test('successful send maps to submitted usbRawSpooler', () async {
      final adapter = _HarnessThermal(
        const PrinterConfig(type: PrinterType.usbThermal),
        (_) async {},
      );
      final outcome = await adapter.print(_minimalInvoice());
      expect(outcome.kind, PrintOutcomeKind.submitted);
      expect(outcome.deliveryKind, PrintDeliveryKind.usbRawSpooler);
    });

    test('PrinterWriteException maps to printer_write_failed', () async {
      final adapter = _HarnessThermal(
        const PrinterConfig(type: PrinterType.usbThermal),
        (_) async {
          throw const PrinterWriteException('write failed', win32Code: 5);
        },
      );
      final outcome = await adapter.print(_minimalInvoice());
      expect(outcome.kind, PrintOutcomeKind.failed);
      expect(outcome.code, 'printer_write_failed');
    });

    test('PrinterNotFoundException maps to printer_not_found', () async {
      final adapter = _HarnessThermal(
        const PrinterConfig(type: PrinterType.usbThermal),
        (_) async {
          throw const PrinterNotFoundException('missing');
        },
      );
      final outcome = await adapter.print(_minimalInvoice());
      expect(outcome.kind, PrintOutcomeKind.failed);
      expect(outcome.code, 'printer_not_found');
    });
  });

  group('PrintManager unsupported config', () {
    test('returns unsupportedConfig for lanThermal', () async {
      final outcome = await PrintManager(
        const PrinterConfig(type: PrinterType.lanThermal),
      ).print(_minimalInvoice());
      expect(outcome.code, 'unsupported_config');
      expect(outcome.kind, PrintOutcomeKind.unsupportedConfig);
    });
  });

  group('Print outcome messages', () {
    test('unsupported config uses Arabic type message', () {
      final msg = printFailureMessageAr(
        PrintOutcome.unsupportedConfig(PrinterType.lanThermal),
      );
      expect(msg, contains('LAN'));
    });

    test('checkout message mentions Ctrl+P', () {
      final msg = checkoutPrintFailureMessageAr(
        PrintOutcome.failed(code: 'printer_not_found'),
      );
      expect(msg, contains('Ctrl+P'));
    });

    test('checkout message empty for cancellation', () {
      expect(
        checkoutPrintFailureMessageAr(PrintOutcome.cancelled()),
        '',
      );
    });

    test('test print success wording for PDF', () {
      expect(
        testPrintSuccessMessageAr(PrintDeliveryKind.pdfDialog),
        contains('نافذة'),
      );
    });
  });
}
