import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum ReceiptPaperSize { thermal58, thermal80, a4 }

class InvoiceItem {
  const InvoiceItem({
    required this.name,
    double? qty,
    double? unitPrice,
    this.lineDiscount = 0,
    double? lineTotal,
    @Deprecated('Use qty instead') int? quantity,
    @Deprecated('Use unitPrice instead') double? price,
  })  : qty = qty ?? quantity?.toDouble() ?? 0,
        unitPrice = unitPrice ?? price ?? 0,
        lineTotal = lineTotal ??
            ((qty ?? quantity?.toDouble() ?? 0) * (unitPrice ?? price ?? 0));

  final String name;
  final double qty;
  final double unitPrice;
  final double lineDiscount;
  final double lineTotal;

  // Backward-compatibility accessors for existing call sites.
  @Deprecated('Use qty instead')
  double get quantity => qty;
  @Deprecated('Use unitPrice instead')
  double get price => unitPrice;
}

class InvoiceData {
  const InvoiceData({
    required this.invoiceNumber,
    required Object date,
    required this.items,
    this.cashierName,
    this.customerName,
    this.storeName,
    this.phone,
    this.address,
    this.logoBytes,
    double? subtotal,
    this.discount = 0,
    double? total,
    double? paid,
    double? remaining,
    this.paymentMethod = 'CASH',
    this.loyaltyEnabled = false,
    this.pointsBefore,
    this.pointsEarned,
    this.pointsAfter,
    @Deprecated('Use pointsAfter instead') this.loyaltyPoints,
  })  : date = date is DateTime
            ? date
            : DateTime.tryParse(date.toString()) ?? DateTime.now(),
        subtotal = subtotal ??
            items.fold<double>(0, (sum, item) => sum + item.lineTotal),
        total = total ??
            ((subtotal ??
                    items.fold<double>(0, (sum, item) => sum + item.lineTotal)) -
                discount),
        paid = paid ??
            (total ??
                ((subtotal ??
                        items.fold<double>(
                          0,
                          (sum, item) => sum + item.lineTotal,
                        )) -
                    discount)),
        remaining = remaining ??
            (((total ??
                        ((subtotal ??
                                items.fold<double>(
                                  0,
                                  (sum, item) => sum + item.lineTotal,
                                )) -
                            discount)) -
                    (paid ??
                        (total ??
                            ((subtotal ??
                                    items.fold<double>(
                                      0,
                                      (sum, item) => sum + item.lineTotal,
                                    )) -
                                discount))))
                .clamp(0, double.infinity)
                .toDouble());

  final String invoiceNumber;
  final DateTime date;
  final String? cashierName;
  final List<InvoiceItem> items;

  final String? customerName;
  @Deprecated('Use pointsAfter instead')
  final int? loyaltyPoints;

  final String? storeName;
  final String? phone;
  final String? address;

  final double subtotal;
  final double discount;
  final double total;
  final double paid;
  final double remaining;

  final String paymentMethod;

  final bool loyaltyEnabled;
  final double? pointsBefore;
  final double? pointsEarned;
  final double? pointsAfter;

  final Uint8List? logoBytes; // ✅ تم إضافة اللوقو
}

class InvoicePdfBuilderClean {
  Future<Uint8List> buildInvoice(
    InvoiceData data, {
    ReceiptPaperSize paperSize = ReceiptPaperSize.a4,
  }) async {
    final pdf = pw.Document();

    // TODO: Use Cairo font for reliable Arabic rendering.
    // TODO: Improve RTL typography rules section-by-section.
    // TODO: Optimize layout specifically for thermal receipt output.

    final isThermal = paperSize != ReceiptPaperSize.a4;

    final pageFormat = isThermal
        ? PdfPageFormat(
            (paperSize == ReceiptPaperSize.thermal58 ? 58 : 80) *
                PdfPageFormat.mm,
            double.infinity,
            marginAll: (paperSize == ReceiptPaperSize.thermal58 ? 3 : 4) *
                PdfPageFormat.mm,
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
                // 🔥 LOGO
                if (data.logoBytes != null)
                  pw.Center(
                    child: pw.Image(
                      pw.MemoryImage(data.logoBytes!),
                      height: isThermal ? 40 : 60,
                    ),
                  ),

                // 🏪 STORE
                pw.Center(
                  child: pw.Text(
                    data.storeName ?? 'Store',
                    style: pw.TextStyle(
                      fontSize: isThermal ? 10 : 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),

                if (data.phone != null)
                  pw.Center(child: pw.Text(data.phone!)),

                if (data.address != null)
                  pw.Center(child: pw.Text(data.address!)),

                pw.SizedBox(height: 8),

                // 🧾 TITLE
                pw.Center(
                  child: pw.Text(
                    'فاتورة',
                    style: pw.TextStyle(
                      fontSize: isThermal ? 12 : 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),

                pw.SizedBox(height: 6),

                // 📄 INFO
                _kvRow('رقم الفاتورة', data.invoiceNumber),
                _kvRow('التاريخ', _formatDate(data.date)),
                if (data.cashierName != null)
                  _kvRow('الكاشير', data.cashierName!),

                // 👤 CUSTOMER
                if (data.customerName != null)
                  _kvRow(
                    'العميل',
                    data.customerName!,
                  ),

                pw.SizedBox(height: 8),

                // 🛒 ITEMS
                ...data.items.map(_itemBlock),

                _solid(),

                // 💰 TOTAL
                _kvRow(
                  'الإجمالي',
                  data.total.toStringAsFixed(2),
                  bold: true,
                ),

                if (data.discount > 0)
                  _kvRow('الخصم', data.discount.toStringAsFixed(2)),

                pw.SizedBox(height: 6),

                if (data.loyaltyEnabled &&
                    (data.pointsAfter != null || data.loyaltyPoints != null))
                  _dashed(),

                // 🧾 FOOTER
                pw.Center(child: pw.Text('شكراً لتعاملكم معنا')),
                pw.Center(
                  child: pw.Text(
                    'Powered by Birtij Software',
                    style: pw.TextStyle(fontSize: 7),
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

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$y/$m/$d $hh:$mm';
  }

  pw.Widget _kvRow(
    String label,
    String value, {
    bool bold = false,
  }) {
    final style = pw.TextStyle(
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Text(
            value,
            textAlign: pw.TextAlign.left,
            style: style,
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Text('$label:', style: style),
      ],
    );
  }

  pw.Widget _dashed() => pw.Center(
        child: pw.Text(
          '- - - - - - - - - - - - - - -',
          style: const pw.TextStyle(fontSize: 8),
        ),
      );

  pw.Widget _solid() => pw.Divider();

  pw.Widget _itemBlock(InvoiceItem item) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(item.name, maxLines: 3),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                item.lineTotal.toStringAsFixed(2),
                textAlign: pw.TextAlign.left,
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                '${item.qty} x ${item.unitPrice}',
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
        if (item.lineDiscount > 0)
          pw.Text(
            'خصم: ${item.lineDiscount.toStringAsFixed(2)}',
          ),
        pw.SizedBox(height: 4),
      ],
    );
  }
}