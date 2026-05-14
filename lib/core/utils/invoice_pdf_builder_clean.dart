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
        // Logo — centered, capped at 50 pt height, scaled to page width.
        if (data.logoBytes != null)
          pw.Image(
            pw.MemoryImage(data.logoBytes!),
            height: 50,
            fit: pw.BoxFit.contain,
          ),
        pw.SizedBox(height: 4),
        pw.Text(
          _safeArabic(data.storeName),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: boldFont, fontSize: 16),
        ),
        if (data.phone != null && data.phone!.isNotEmpty)
          pw.Text(
            _safeArabic('هاتف: ${data.phone!}'),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: regularFont, fontSize: 9),
          ),
        if (data.address != null && data.address!.isNotEmpty)
          pw.Text(
            _safeArabic('العنوان: ${data.address!}'),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: regularFont, fontSize: 9),
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
        // Info rows use _infoRow so the label appears on the RIGHT
        // and the value on the LEFT — matching the preview's _meta widget.
        _infoRow('رقم الفاتورة', data.invoiceNumber),
        _infoRow('التاريخ', _formatDate(data.date)),
        if (data.cashierName != null && data.cashierName!.isNotEmpty)
          _infoRow('الكاشير', _safeArabic(data.cashierName!)),
        if (data.customerName != null && data.customerName!.isNotEmpty)
          _infoRow('العميل', _safeArabic(data.customerName!)),
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
    final subtotal = data.items.fold(0.0, (s, i) => s + i.lineTotal);
    final tax      = data.showTax ? subtotal * 0.15 : 0.0;
    final total    = data.showTax ? subtotal + tax : data.total;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Subtotal row — always shown so the breakdown is visible.
        _kvRow('المجموع الفرعي', '${subtotal.toStringAsFixed(0)} د.ع'),
        // Tax row — only when showTax is enabled (matches preview).
        if (data.showTax)
          _kvRow('ضريبة 15%', '${tax.toStringAsFixed(0)} د.ع'),
        // Grand total — bold highlight, matches preview's grand-total box.
        _kvRow(
          'الإجمالي',
          '${total.toStringAsFixed(0)} د.ع',
          bold: true,
        ),
        if (data.paid != null)
          _kvRow('المدفوع', '${data.paid!.toStringAsFixed(0)} د.ع'),
        if (data.change != null && data.change! > 0)
          _kvRow('الباقي', '${data.change!.toStringAsFixed(0)} د.ع'),
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

  // ── Row helpers ──────────────────────────────────────────────────────────
  //
  // In pw.Directionality(rtl) the FIRST child of a Row appears on the RIGHT
  // and the LAST child on the LEFT.
  //
  //  _infoRow  — label: RIGHT, value LEFT  (mirrors preview _meta widget)
  //              Used for: invoice number, date, cashier, customer.
  //
  //  _kvRow    — label: LEFT,  value RIGHT (mirrors preview _trow widget)
  //              Used for: subtotal, tax, grand total, paid, change.

  /// Info row: `label: RIGHT` — `value LEFT`  (preview _meta style)
  pw.Widget _infoRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      font: bold ? boldFont : regularFont,
      fontSize: 9,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        // In RTL: first child → RIGHT  →  label: on the right ✓
        pw.Text('$label:', style: style),
        // second child → LEFT  →  value on the left ✓
        pw.Text(value, style: style),
      ],
    );
  }

  /// Total row: `label: LEFT` — `value RIGHT`  (preview _trow style)
  pw.Widget _kvRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      font: bold ? boldFont : regularFont,
      fontSize: 9,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        // In RTL: first child → RIGHT  →  value on the right ✓
        pw.Text(value, style: style),
        // second child → LEFT  →  label: on the left ✓
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
