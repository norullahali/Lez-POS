import 'dart:io';
import 'dart:typed_data';

import '../../features/invoices/models/invoice_detail.dart';
import '../../features/pos/models/invoice_models.dart';
import 'settings_service.dart';

class ReceiptInvoiceMapper {
  ReceiptInvoiceMapper._();

  static String paymentMethodLabelAr(String method) {
    switch (method.toUpperCase()) {
      case 'CASH':
        return 'نقد';
      case 'CARD':
        return 'بطاقة';
      case 'MIXED':
        return 'نقد + بطاقة';
      case 'DEBT':
        return 'آجل';
      default:
        return method;
    }
  }

  static Future<InvoiceData> buildFromDetail(
    InvoiceDetailData detail,
    SettingsService settings,
  ) async {
    final storeName = await settings.getStoreName();
    final phone = await settings.getPhone();
    final address = await settings.getAddress();
    final logoPath = await settings.getStoreLogoPath();
    final footer = await settings.getInvoiceFooter();
    final footer2 = await settings.getInvoiceFooter2();
    final showQr = await settings.getShowQr();

    Uint8List? logoBytes;
    if (logoPath != null) {
      final file = File(logoPath);
      if (await file.exists()) {
        logoBytes = await file.readAsBytes();
      }
    }

    final header = detail.header;
    final meta = detail.returnMetadata;
    final paidTotal = header.cashPaid + header.cardPaid;
    final method = header.paymentMethod.trim();
    final showSplit = method.toUpperCase() == 'MIXED' ||
        (header.cashPaid > 0 && header.cardPaid > 0);

    return InvoiceData(
      invoiceNumber: header.invoiceNumber,
      date: header.saleDate,
      items: detail.lines
          .map(
            (line) => InvoiceItem(
              name: line.productName,
              qty: line.quantity,
              unitPrice: line.unitPrice,
              lineTotal: line.lineTotal,
              lineDiscount: line.discount,
            ),
          )
          .toList(),
      storeName: storeName,
      total: header.total,
      headerSubtotal: header.subtotal,
      headerDiscountTotal: header.discountTotal,
      paid: paidTotal > 0 ? paidTotal : null,
      change: header.changeAmount > 0 ? header.changeAmount : null,
      cashPaid: showSplit ? header.cashPaid : null,
      cardPaid: showSplit ? header.cardPaid : null,
      debtAmount: header.debtAmount > 0 ? header.debtAmount : null,
      paymentMethod:
          method.isNotEmpty ? paymentMethodLabelAr(method) : null,
      phone: phone,
      address: address,
      logoBytes: logoBytes,
      customerName: header.customerName == 'زبون عام'
          ? null
          : header.customerName,
      cashierName:
          header.cashierName == '—' ? null : header.cashierName,
      footer: footer,
      footer2: footer2,
      showTax: detail.showTax,
      showQr: showQr,
      isReturned: detail.isReturned,
      returnDate: meta?.returnDate,
      returnNote: meta?.returnNote,
      returnedByName: meta?.returnedByName,
    );
  }
}
