// lib/core/utils/invoice_pdf_builder_clean.dart

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/pos/models/invoice_models.dart';
import 'receipt_paper_size.dart';

export 'receipt_paper_size.dart' show ReceiptPaperSize;

class InvoicePdfBuilderClean {
  late final pw.Font regularFont;
  late final pw.Font boldFont;

  Future<Uint8List> buildInvoice(
    InvoiceData data, {
    ReceiptPaperSize paperSize = ReceiptPaperSize.thermal80,
  }) async {
    if (data.items.isEmpty) {
      throw Exception('No items to print');
    }

    // Arabic fonts
    final regularFontData =
        await rootBundle.load('assets/fonts/Cairo-Regular.ttf');

    regularFont = pw.Font.ttf(regularFontData);

    final boldFontData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');

    boldFont = pw.Font.ttf(boldFontData);

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: paperSize.toPageFormat(),
        build: (context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _buildHeader(data),
                pw.SizedBox(height: 6),
                _buildInvoiceInfo(data),
                pw.SizedBox(height: 6),
                _buildTable(data),
                pw.SizedBox(height: 6),
                pw.Divider(),
                _buildTotalSection(data),
                pw.SizedBox(height: 6),
                _buildFooterSection(data),
                pw.SizedBox(height: 6),
                pw.Center(
                  child: pw.Text(
                    'Lez POS by Birtij Software 07502721622',
                    style: pw.TextStyle(
                      font: regularFont,
                      fontSize: 7,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  // HEADER

  pw.Widget _buildHeader(InvoiceData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (data.logoBytes != null)
          pw.Image(
            pw.MemoryImage(data.logoBytes!),
            height: 50,
          ),
        pw.SizedBox(height: 4),
        pw.Text(
          _safeArabic(data.storeName),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            font: boldFont,
            fontSize: 16,
          ),
        ),
        if (data.phone != null)
          pw.Text(
            _safeArabic(data.phone!),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: regularFont,
              fontSize: 9,
            ),
          ),
        if (data.address != null)
          pw.Text(
            _safeArabic(data.address!),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: regularFont,
              fontSize: 9,
            ),
          ),
        pw.SizedBox(height: 4),
        pw.Divider(),
      ],
    );
  }

  // INVOICE INFO

  pw.Widget _buildInvoiceInfo(InvoiceData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _kvRow('رقم الفاتورة', data.invoiceNumber),
        _kvRow(
          'التاريخ',
          _formatDate(data.date),
        ),
        if (data.customerName != null)
          _kvRow(
            'العميل',
            _safeArabic(data.customerName!),
          ),
        if (data.cashierName != null)
          _kvRow(
            'الكاشير',
            _safeArabic(data.cashierName!),
          ),
      ],
    );
  }

  // TABLE

  pw.Widget _buildTable(InvoiceData data) {
    final items = data.items.where((e) => e.name.trim().isNotEmpty).toList();

    if (items.isEmpty) {
      return pw.Center(
        child: pw.Text(
          'لا توجد عناصر',
          style: pw.TextStyle(
            font: boldFont,
            fontSize: 10,
          ),
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: const pw.BorderSide(width: 0.2),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1.5),
        3: pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(width: 0.8),
            ),
          ),
          children: [
            _headerCell('المادة'),
            _headerCell('عدد'),
            _headerCell('السعر'),
            _headerCell('المجموع'),
          ],
        ),
        ...items.map(
          (item) => pw.TableRow(
            children: [
              _cell(_safeArabic(item.name)),
              _cell(_safe(item.qty)),
              _cell(_safe(item.unitPrice)),
              _cell(_safe(item.lineTotal)),
            ],
          ),
        ),
      ],
    );
  }

  // TOTALS

  pw.Widget _buildTotalSection(InvoiceData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _kvRow(
          'الإجمالي',
          '${data.total.toStringAsFixed(0)} د.ع',
          bold: true,
        ),
        if (data.paid != null)
          _kvRow(
            'المدفوع',
            '${data.paid!.toStringAsFixed(0)} د.ع',
          ),
        if (data.change != null && data.change! > 0)
          _kvRow(
            'الباقي',
            '${data.change!.toStringAsFixed(0)} د.ع',
          ),
      ],
    );
  }

  // FOOTER

  pw.Widget _buildFooterSection(InvoiceData data) {
    final hasFooter1 = data.footer  != null && data.footer!.isNotEmpty;
    final hasFooter2 = data.footer2 != null && data.footer2!.isNotEmpty;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (hasFooter1)
          pw.Text(
            _safeArabic(data.footer!),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: regularFont, fontSize: 9),
          ),
        if (hasFooter1 && hasFooter2) pw.SizedBox(height: 3),
        if (hasFooter2)
          pw.Text(
            _safeArabic(data.footer2!),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: regularFont, fontSize: 8),
          ),
        if (data.showQr) ...[
          pw.SizedBox(height: 8),
          _buildQr(data),
        ],
      ],
    );
  }

  // QR (only rendered when InvoiceData.showQr == true)

  pw.Widget _buildQr(InvoiceData data) {
    final qrData =
        '${data.invoiceNumber}|${data.total}|${data.date.toIso8601String()}';

    return pw.Center(
      child: pw.BarcodeWidget(
        barcode: pw.Barcode.qrCode(),
        data: qrData,
        width: 72,
        height: 72,
      ),
    );
  }

  // HELPERS

  pw.Widget _headerCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: boldFont,
          fontSize: 9,
        ),
      ),
    );
  }

  pw.Widget _cell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(
        vertical: 2,
        horizontal: 4,
      ),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: regularFont,
          fontSize: 8,
        ),
      ),
    );
  }

  pw.Widget _kvRow(
    String label,
    String value, {
    bool bold = false,
  }) {
    final style = pw.TextStyle(
      font: bold ? boldFont : regularFont,
      fontSize: 9,
    );

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(value, style: style),
        pw.Text('$label:', style: style),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, "0")}'
        '/${date.day.toString().padLeft(2, "0")} '
        '${date.hour.toString().padLeft(2, "0")}:'
        '${date.minute.toString().padLeft(2, "0")}';
  }
}

String _safeArabic(String text) {
  return text.replaceAll('ي', 'ﻱ').replaceAll('ك', 'ﻙ');
}

String _safe(num? value) {
  return (value ?? 0).toStringAsFixed(0);
}
