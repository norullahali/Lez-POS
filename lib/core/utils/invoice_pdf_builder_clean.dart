import '../../features/pos/models/invoice_models.dart';

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';

enum ReceiptPaperSize { thermal58, thermal80, a4 }

class InvoicePdfBuilderClean {
  Future<Uint8List> buildInvoice(
    InvoiceData data, {
    ReceiptPaperSize paperSize = ReceiptPaperSize.thermal80,
  }) async {
    if (data.items.isEmpty) {
      throw Exception("No items to print");
    }

    final fontData =
        await rootBundle.load("assets/fonts/NotoSansArabic-Regular.ttf");
    final font = pw.Font.ttf(fontData);

    final pdf = pw.Document();

    final isThermal = paperSize != ReceiptPaperSize.a4;

    final pageFormat = isThermal
        ? PdfPageFormat(
            (paperSize == ReceiptPaperSize.thermal58 ? 58 : 80) *
                PdfPageFormat.mm,
            double.infinity,
            marginAll: 4 * PdfPageFormat.mm,
          )
        : PdfPageFormat.a4;

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _buildHeader(data, font),

                _buildInvoiceInfo(data, font),

                pw.SizedBox(height: 2),

                /// 🧾 TABLE
                _buildTable(data, font),

                pw.SizedBox(height: 2),
                pw.Divider(),

                /// 💰 الإجمالي
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'الإجمالي',
                      style: pw.TextStyle(
                        font: font,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      '${data.total.toStringAsFixed(0)} د.ع',
                      style: pw.TextStyle(
                        font: font,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                pw.SizedBox(height: 2),

                /// 💵 الدفع
                if (data.paid != null)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('المدفوع', style: pw.TextStyle(font: font)),
                      pw.Text('${data.paid!.toStringAsFixed(0)}',
                          style: pw.TextStyle(font: font)),
                    ],
                  ),

                if (data.change != null)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('الباقي', style: pw.TextStyle(font: font)),
                      pw.Text('${data.change!.toStringAsFixed(0)}',
                          style: pw.TextStyle(font: font)),
                    ],
                  ),

                /// 💰 PAYMENT + FOOTER
                _buildPayment(data, font),
                pw.Center(
                  child: pw.Text(
                    'Lez POS by Birtij Software',
                    style: pw.TextStyle(font: font, fontSize: 8),
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

  pw.Widget _buildHeader(InvoiceData data, pw.Font font) {
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
          data.storeName,
          style: pw.TextStyle(
            font: font,
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        if (data.phone != null)
          pw.Text(
            data.phone!,
            style: pw.TextStyle(font: font, fontSize: 9),
          ),
        if (data.address != null)
          pw.Text(
            data.address!,
            style: pw.TextStyle(font: font, fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
        pw.SizedBox(height: 4),
        pw.Divider(),
      ],
    );
  }

  pw.Widget _buildInvoiceInfo(InvoiceData data, pw.Font font) {
    return pw.Column(
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

  /// TABLE
  pw.Widget _buildTable(InvoiceData data, pw.Font font) {
    final items = data.items.where((e) => e.name.trim().isNotEmpty).toList();

    if (items.isEmpty) {
      return pw.Center(
        child: pw.Text('لا توجد عناصر', style: pw.TextStyle(font: font)),
      );
    }

    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(width: 0.2),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(3), // اسم المنتج
        1: const pw.FlexColumnWidth(1), // الكمية
        2: const pw.FlexColumnWidth(1.5), // السعر
        3: const pw.FlexColumnWidth(1.5), // المجموع
      },
      children: [
        /// HEADER
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(width: 0.8),
            ),
          ),
          children: [
            _headerCell("المادة", font),
            _headerCell("عدد", font),
            _headerCell("السعر", font),
            _headerCell("المجموع", font),
          ],
        ),

        /// ITEMS
        ...items.map((item) => pw.TableRow(
              children: [
                _cell(item.name, font),
                _cell(_safe(item.qty), font),
                _cell(_safe(item.unitPrice), font),
                _cell(_safe(item.lineTotal), font),
              ],
            )),
      ],
    );
  }

  pw.Widget _buildTotals(InvoiceData data, pw.Font font) {
    final subtotal = data.items.fold(0.0, (sum, e) => sum + e.lineTotal);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _buildPayment(data, font),
        pw.SizedBox(height: 2),
        pw.Divider(),
        _buildHeader(data, font),
        pw.SizedBox(height: 18),
        _buildInvoiceInfo(data, font),
        pw.SizedBox(height: 2),
        _buildTable(data, font),
        pw.SizedBox(height: 2),
        pw.Divider(),
      ],
    );
  }

  pw.Widget _buildPayment(InvoiceData data, pw.Font font) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 3),
        if (data.footer != null && data.footer!.isNotEmpty)
          pw.Column(
            children: [
              pw.SizedBox(height: 3),
              pw.Divider(),
              pw.SizedBox(height: 5),
              pw.Text(
                data.footer!,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 10),
              ),
            ],
          ),
        _buildQr(data),
        pw.SizedBox(height: 3),
        if (data.paid != null) _kvRow('المدفوع', _safe(data.paid), font),
        if (data.change != null && data.change! > 0)
          _kvRow('الباقي', _safe(data.change), font),
        if (data.loyaltyPoints != null && data.loyaltyPoints! > 0)
          _kvRow('نقاط مستخدمة', _safe(data.loyaltyPoints), font),
      ],
    );
  }

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
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(font: font, fontSize: 8),
      ),
    );
  }

  pw.Widget _kvRow(
    String label,
    String value,
    pw.Font font, {
    bool bold = false,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(value,
            style: pw.TextStyle(
                font: font,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text("$label:",
            style: pw.TextStyle(
                font: font,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return "${date.year}/${date.month}/${date.day} ${date.hour}:${date.minute}";
  }

  String _safe(num? value) {
    return (value ?? 0).toStringAsFixed(0);
  }
}

pw.Widget _buildFooter(pw.Font font) {
  return pw.Column(
    children: [
      pw.Center(
        child: pw.Text(
          'شكراً لتعاملكم معنا',
          style: pw.TextStyle(font: font),
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Center(
        child: pw.Text(
          'Powered by Lez POS',
          style: pw.TextStyle(font: font, fontSize: 8),
        ),
      ),
    ],
  );
}

pw.Widget _buildQr(InvoiceData data) {
  final qrData =
      '${data.invoiceNumber}|${data.total}|${data.date.toIso8601String()}';

  return pw.Center(
    child: pw.BarcodeWidget(
      barcode: pw.Barcode.qrCode(),
      data: qrData,
      width: 80,
      height: 80,
    ),
  );
}
