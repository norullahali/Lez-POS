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

    // pw.Table does NOT honour ambient Directionality — columns always render
    // in LTR order regardless of pw.Directionality(rtl) wrapping.
    // We rebuild the table as a Column of pw.Row(textDirection: rtl) widgets
    // so each row's children are physically placed right-to-left:
    //
    //   children order → [المادة, العدد, السعر, المجموع]
    //   with textDirection:rtl  →  المادة lands on the RIGHT,
    //                              المجموع lands on the LEFT.
    //
    // Visual left-to-right on paper:  [المجموع][السعر][العدد][المادة]
    // Arabic reader (RTL):            [المادة][العدد][السعر][المجموع]  ✓

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // ── Header row ──────────────────────────────────────────────────
        // pw.Row inherits RTL from the parent pw.Directionality(rtl).
        // First child → RIGHT, last child → LEFT.
        // Children order [المادة, العدد, السعر, المجموع]:
        //   المادة (first)  → RIGHT  ✓
        //   المجموع (last)  → LEFT   ✓
        pw.Row(
          children: [
            pw.Expanded(flex: 4, child: _headerCell('المادة',  align: pw.TextAlign.right)),
            pw.Expanded(flex: 2, child: _headerCell('العدد')),
            pw.Expanded(flex: 2, child: _headerCell('السعر')),
            pw.Expanded(flex: 3, child: _headerCell('المجموع', align: pw.TextAlign.left)),
          ],
        ),
        pw.Divider(thickness: 0.8),
        // ── Data rows ───────────────────────────────────────────────────
        ...items.map(
          (item) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1),
            child: pw.Row(
              children: [
                pw.Expanded(flex: 4, child: _cell(_safeArabic(item.name), align: pw.TextAlign.right)),
                pw.Expanded(flex: 2, child: _cell(_safe(item.qty))),
                pw.Expanded(flex: 2, child: _cell(_safe(item.unitPrice))),
                pw.Expanded(flex: 3, child: _cell(_safe(item.lineTotal),  align: pw.TextAlign.left)),
              ],
            ),
          ),
        ),
        pw.Divider(thickness: 0.3),
      ],
    );
  }

  // TOTALS

  pw.Widget _buildTotalSection(InvoiceData data) {
    final subtotal = data.items.fold(0.0, (s, i) => s + i.lineTotal);
    final tax      = data.showTax ? subtotal * 0.15 : 0.0;
    final total    = data.showTax ? subtotal + tax : data.total;

    // All total rows use _infoRow: label on RIGHT, value on LEFT — same as
    // info rows. Arabic accounting places the label on the right side.
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _infoRow('المجموع الفرعي', '${subtotal.toStringAsFixed(0)} د.ع'),
        if (data.showTax)
          _infoRow('ضريبة 15%', '${tax.toStringAsFixed(0)} د.ع'),
        _infoRow('الإجمالي', '${total.toStringAsFixed(0)} د.ع', bold: true),
        if (data.paid != null)
          _infoRow('المدفوع', '${data.paid!.toStringAsFixed(0)} د.ع'),
        if (data.change != null && data.change! > 0)
          _infoRow('الباقي', '${data.change!.toStringAsFixed(0)} د.ع'),
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

  pw.Widget _headerCell(String text, {pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          font: boldFont,
          fontSize: 9,
        ),
      ),
    );
  }

  pw.Widget _cell(String text, {pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(
        vertical: 2,
        horizontal: 4,
      ),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          font: regularFont,
          fontSize: 8,
        ),
      ),
    );
  }

  // ── Row helpers ──────────────────────────────────────────────────────────
  //
  // We set textDirection: rtl EXPLICITLY on every Row so we do NOT rely on
  // the ambient pw.Directionality — some pdf widget types ignore it.
  //
  // In pw.Row(textDirection: rtl):
  //   first child  → placed on the RIGHT  →  use for LABEL
  //   second child → placed on the LEFT   →  use for VALUE
  //
  // Arabic accounting convention:
  //   الإجمالي:          2500 د.ع
  //   (label RIGHT)       (value LEFT)

  /// All label/value rows — label: RIGHT, value LEFT — Arabic convention.
  /// Used for: invoice info rows AND totals (same layout for both).
  ///
  /// pw.Row inherits RTL from the ancestor pw.Directionality(rtl) that
  /// wraps the entire page.  First child → RIGHT, second → LEFT.
  pw.Widget _infoRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      font: bold ? boldFont : regularFont,
      fontSize: 9,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('$label:', style: style),   // first child → RIGHT ✓
        pw.Text(value,     style: style),   // second child → LEFT ✓
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
