import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
  Future<Uint8List> buildInvoice(InvoiceData data) async {
    final pdf = pw.Document();
    final grandTotal = data.items.fold<double>(
      0,
      (sum, item) => sum + (item.quantity * item.price),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'Invoice',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text('Invoice #: ${data.invoiceNumber}'),
              pw.SizedBox(height: 4),
              pw.Text('Date: ${data.date}'),
              pw.SizedBox(height: 16),
              ...data.items.map((item) {
                final lineTotal = item.quantity * item.price;
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(child: pw.Text(item.name)),
                      pw.Text('${item.quantity} x ${item.price.toStringAsFixed(2)}'),
                      pw.SizedBox(width: 12),
                      pw.Text(lineTotal.toStringAsFixed(2)),
                    ],
                  ),
                );
              }),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text(
                    'Total: ${grandTotal.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}
