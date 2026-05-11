// lib/core/utils/invoice_pdf_builder_clean.dart
//
// Single source of truth for PDF invoice generation in Lez POS.
// Used exclusively by PdfPrinterAdapter; never call directly from UI.
//
// Layout sections (top to bottom, RTL):
//   1. Header     — logo, store name, phone, address
//   2. Invoice info — number, date, customer, cashier
//   3. Items table — name | qty | unit price | total
//   4. Totals     — grand total (bold), paid, change
//   5. Footer     — custom text, QR code, Lez POS branding

import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/pos/models/invoice_models.dart';
import 'receipt_paper_size.dart'; // Single canonical source — no duplicate enum here.

export 'receipt_paper_size.dart' show ReceiptPaperSize;

class InvoicePdfBuilderClean {
  /// Builds a complete invoice PDF and returns the raw bytes.
  ///
  /// [paperSize] defaults to 80 mm thermal width.
  Future<Uint8List> buildInvoice(
    InvoiceData data, {
    ReceiptPaperSize paperSize = ReceiptPaperSize.thermal80,
  }) async {
    if (data.items.isEmpty) throw Exception('No items to print');

    final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');

    final font = pw.Font.ttf(fontData);

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        // Use the canonical extension from receipt_paper_size.dart.
        pageFormat: paperSize.toPageFormat(),
        build: (context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _buildHeader(data, font),
                _buildInvoiceInfo(data, font),
                pw.SizedBox(height: 4),
                _buildTable(data, font),
                pw.SizedBox(height: 4),
                pw.Divider(),
                _buildTotalSection(data, font),
                _buildFooterSection(data, font),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    'Lez POS by Birtij Software',
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
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

  // ── Header ───────────────────────────────────────────────────────────────

  pw.Widget _buildHeader(InvoiceData data, pw.Font font) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (data.logoBytes != null)
          pw.Image(pw.MemoryImage(data.logoBytes!), height: 50),
        pw.SizedBox(height: 4),
        pw.Text(
          data.storeName,
          style: pw.TextStyle(
            font: font,
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        if (data.phone != null)
          pw.Text(data.phone!,
              style: pw.TextStyle(
                  font: font, fontSize: 9, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center),
        if (data.address != null)
          pw.Text(data.address!,
              style: pw.TextStyle(
                  font: font, fontSize: 9, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 4),
        pw.Divider(),
      ],
    );
  }

  // ── Invoice metadata ─────────────────────────────────────────────────────

  pw.Widget _buildInvoiceInfo(InvoiceData data, pw.Font font) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _kvRow('رقم الفاتورة', data.invoiceNumber, font),
        _kvRow('التاريخ', _formatDate(data.date), font),
        if (data.customerName != null)
          _kvRow('العميل', data.customerName!, font),
        if (data.cashierName != null)
          _kvRow('الكاشير', data.cashierName!, font),
      ],
    );
  }

  // ── Items table ──────────────────────────────────────────────────────────

  pw.Widget _buildTable(InvoiceData data, pw.Font font) {
    final items = data.items.where((e) => e.name.trim().isNotEmpty).toList();

    if (items.isEmpty) {
      return pw.Center(
          child: pw.Text('لا توجد عناصر',
              style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold)));
    }

    return pw.Table(
      border: pw.TableBorder(horizontalInside: const pw.BorderSide(width: 0.2)),
      columnWidths: const {
        0: pw.FlexColumnWidth(3), // Product name
        1: pw.FlexColumnWidth(1), // Qty
        2: pw.FlexColumnWidth(1.5), // Unit price
        3: pw.FlexColumnWidth(1.5), // Line total
      },
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.8))),
          children: [
            _headerCell('المادة', font),
            _headerCell('عدد', font),
            _headerCell('السعر', font),
            _headerCell('المجموع', font),
          ],
        ),
        // Data rows
        ...items.map((item) => pw.TableRow(children: [
              _cell(item.name, font),
              _cell(_safe(item.qty), font),
              _cell(_safe(item.unitPrice), font),
              _cell(_safe(item.lineTotal), font),
            ])),
      ],
    );
  }

  // ── Totals section (grand total, paid, change) ───────────────────────────

  pw.Widget _buildTotalSection(InvoiceData data, pw.Font font) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _kvRow('الإجمالي', '${data.total.toStringAsFixed(0)} د.ع', font,
            bold: true),
        if (data.paid != null)
          _kvRow('المدفوع', '${data.paid!.toStringAsFixed(0)} د.ع', font),
        if (data.change != null && data.change! > 0)
          _kvRow('الباقي', '${data.change!.toStringAsFixed(0)} د.ع', font),
        if (data.loyaltyPoints != null && data.loyaltyPoints! > 0)
          _kvRow('نقاط مستخدمة', _safe(data.loyaltyPoints), font),
      ],
    );
  }

  // ── Footer section (custom text + QR) ───────────────────────────────────

  pw.Widget _buildFooterSection(InvoiceData data, pw.Font font) {
    final hasFooter = data.footer != null && data.footer!.isNotEmpty;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(height: 6),
        if (hasFooter) ...[
          pw.Divider(),
          pw.SizedBox(height: 4),
          pw.Text(
            data.footer!,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
                font: font, fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
        ],
        _buildQr(data),
        pw.SizedBox(height: 4),
        pw.Text(
          'شكراً لتعاملكم معنا',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              font: font, fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  // ── QR code ──────────────────────────────────────────────────────────────

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

  // ── Small helpers ────────────────────────────────────────────────────────

  pw.Widget _headerCell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: font,
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _cell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: pw.Text(text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              font: font, fontSize: 8, fontWeight: pw.FontWeight.bold)),
    );
  }

  pw.Widget _kvRow(
    String label,
    String value,
    pw.Font font, {
    bool bold = false,
  }) {
    final style = pw.TextStyle(
      font: font,
    );
    // value on left, label: on right (RTL layout)
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(value, style: style),
        pw.Text('$label:', style: style),
      ],
    );
  }

  String _formatDate(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, "0")}'
      '/${date.day.toString().padLeft(2, "0")} '
      '${date.hour.toString().padLeft(2, "0")}:${date.minute.toString().padLeft(2, "0")}';

  String _safe(num? value) => (value ?? 0).toStringAsFixed(0);
}
