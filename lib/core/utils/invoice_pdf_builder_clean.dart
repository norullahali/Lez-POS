import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

enum ReceiptPaperSize { thermal58, thermal80, a4 }

class InvoiceItem {
  const InvoiceItem({
    required this.name,
    required this.quantity,
    required this.price,
  });

  final String name;
  final int quantity;
  final double price;
}

class InvoiceData {
  const InvoiceData({
    required this.invoiceNumber,
    required this.date,
    required this.items,
  });

  final String invoiceNumber;
  final String date;
  final List<InvoiceItem> items;
}

class InvoicePdfBuilderClean {
  Future<Uint8List> buildInvoice(
    InvoiceData data, {
    ReceiptPaperSize paperSize = ReceiptPaperSize.a4,
  }) async {
    final pdf = pw.Document();

    pw.Font? arabicFont;
    pw.Font? arabicBoldFont;

    try {
      arabicFont = await PdfGoogleFonts.cairoRegular();
      arabicBoldFont = await PdfGoogleFonts.cairoBold();
    } catch (_) {
      arabicFont = null;
      arabicBoldFont = null;
    }

    final baseStyle = pw.TextStyle(font: arabicFont);

    final headerStyle = pw.TextStyle(
      font: arabicBoldFont ?? arabicFont,
      fontSize: 24,
      fontWeight: pw.FontWeight.bold,
    );

    final totalStyle = pw.TextStyle(
      font: arabicBoldFont ?? arabicFont,
      fontWeight: pw.FontWeight.bold,
    );

    final grandTotal = data.items.fold<double>(
      0,
      (sum, item) => sum + (item.quantity * item.price),
    );

    if (paperSize == ReceiptPaperSize.a4) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.DefaultTextStyle(
                style: baseStyle,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Center(
                      child: pw.Text('فاتورة', style: headerStyle),
                    ),
                    pw.SizedBox(height: 16),

                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text('رقم الفاتورة: ${data.invoiceNumber}'),
                    ),

                    pw.SizedBox(height: 4),

                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text('التاريخ: ${data.date}'),
                    ),

                    pw.SizedBox(height: 16),

                    ...data.items.map((item) {
                      final lineTotal = item.quantity * item.price;

                      return pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 6),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Expanded(
                              flex: 3,
                              child: pw.Align(
                                alignment: pw.Alignment.centerRight,
                                child: pw.Text(item.name),
                              ),
                            ),
                            pw.Expanded(
                              flex: 2,
                              child: pw.Align(
                                alignment: pw.Alignment.center,
                                child: pw.Text(
                                  '${item.quantity} x ${item.price.toStringAsFixed(2)}',
                                ),
                              ),
                            ),
                            pw.Expanded(
                              flex: 2,
                              child: pw.Align(
                                alignment: pw.Alignment.centerLeft,
                                child: pw.Text(
                                  lineTotal.toStringAsFixed(2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    pw.Divider(),

                    pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        'الإجمالي: ${grandTotal.toStringAsFixed(2)}',
                        style: totalStyle,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } else {
      final is58mm = paperSize == ReceiptPaperSize.thermal58;
      final pageFormat = PdfPageFormat(
        (is58mm ? 58 : 80) * PdfPageFormat.mm,
        PdfPageFormat.a4.height,
        marginAll: (is58mm ? 3 : 4) * PdfPageFormat.mm,
      );

      final thermalBaseStyle = baseStyle.copyWith(fontSize: is58mm ? 8 : 9);
      final thermalHeaderStyle = headerStyle.copyWith(fontSize: is58mm ? 12 : 14);
      final thermalTotalStyle = totalStyle.copyWith(fontSize: is58mm ? 9 : 10);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: pageFormat,
          build: (context) {
            return [
              pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.DefaultTextStyle(
                  style: thermalBaseStyle,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Center(
                        child: pw.Text('فاتورة', style: thermalHeaderStyle),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text('رقم الفاتورة: ${data.invoiceNumber}'),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text('التاريخ: ${data.date}'),
                      ),
                      pw.SizedBox(height: 8),
                      ...data.items.map((item) {
                        final lineTotal = item.quantity * item.price;

                        return pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 6),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                            children: [
                              pw.Text(
                                item.name,
                                maxLines: 3,
                              ),
                              pw.SizedBox(height: 2),
                              pw.Row(
                                children: [
                                  pw.Expanded(
                                    child: pw.Align(
                                      alignment: pw.Alignment.centerLeft,
                                      child: pw.Text(lineTotal.toStringAsFixed(2)),
                                    ),
                                  ),
                                  pw.Expanded(
                                    child: pw.Align(
                                      alignment: pw.Alignment.centerRight,
                                      child: pw.Text(
                                        '${item.quantity} x ${item.price.toStringAsFixed(2)}',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                      pw.Divider(),
                      pw.Align(
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Text(
                          'الإجمالي: ${grandTotal.toStringAsFixed(2)}',
                          style: thermalTotalStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ];
          },
        ),
      );
    }

    return pdf.save();
  }
}