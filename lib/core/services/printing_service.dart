// lib/core/services/printing_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../database/app_database.dart';
import 'settings_service.dart';

class ReceiptData {
  final String invoiceNumber;
  final DateTime date;
  final List<ReceiptItem> items;
  final double subtotal;
  final double discount;
  final double total;
  final String paymentMethod;
  final double cashPaid;
  final double change;
  
  // New properties for detailed receipts
  final String cashierName;
  final String? customerName;
  final double? currentDebt;
  final double? pointsBefore;
  final double? pointsEarned;
  final double? pointsAfter;

  const ReceiptData({
    required this.invoiceNumber,
    required this.date,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paymentMethod,
    required this.cashPaid,
    required this.change,
    required this.cashierName,
    this.customerName,
    this.currentDebt,
    this.pointsBefore,
    this.pointsEarned,
    this.pointsAfter,
  });
}

class ReceiptItem {
  final String name;
  final double qty;
  final double unitPrice;
  final double discount;
  final double total;

  const ReceiptItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.discount,
    required this.total,
  });
}

class PrintingService {
  static final _df = DateFormat('yyyy/MM/dd HH:mm');
  static final _nf = NumberFormat('#,##0.##');

  static Future<void> printReceipt(ReceiptData data) async {
    final pdf = await _buildReceiptPdf(data);
    await Printing.layoutPdf(
      onLayout: (_) async => pdf,
      name: 'receipt_${data.invoiceNumber}',
    );
  }

  static Future<void> previewReceipt(BuildContext context, ReceiptData data) async {
    final pdf = await _buildReceiptPdf(data);
    await Printing.sharePdf(bytes: pdf, filename: 'receipt_${data.invoiceNumber}.pdf');
  }

  static Future<Uint8List> _buildReceiptPdf(ReceiptData data) async {
    final db = AppDatabase.instance;
    final settingsService = SettingsService(db);
    
    final storeName = await settingsService.getStoreName();
    final storeLogoPath = await settingsService.getStoreLogoPath();
    final phone = await settingsService.getPhone();
    final address = await settingsService.getAddress();
    final loyaltyEnabled = await settingsService.isLoyaltyEnabled();

    final pdf = pw.Document();
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();

    pw.MemoryImage? logoImage;
    if (storeLogoPath != null && storeLogoPath.isNotEmpty) {
      try {
        final file = File(storeLogoPath);
        if (file.existsSync()) {
          logoImage = pw.MemoryImage(file.readAsBytesSync());
        }
      } catch (e) {
        debugPrint('[PrintingService] Error loading logo: $e');
      }
    }

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm),
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Header Section
            if (logoImage != null) ...[
              pw.Center(child: pw.Image(logoImage, height: 60)),
              pw.SizedBox(height: 8),
            ],
            pw.Text(storeName, style: pw.TextStyle(font: fontBold, fontSize: 18), textAlign: pw.TextAlign.center),
            if (address != null && address.isNotEmpty)
              pw.Text(address, style: pw.TextStyle(font: font, fontSize: 10), textAlign: pw.TextAlign.center),
            if (phone != null && phone.isNotEmpty)
              pw.Text('هاتف: $phone', style: pw.TextStyle(font: font, fontSize: 10), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 4),
            pw.Divider(),

            // Info Row Section
            pw.Text('رقم الفاتورة: ${data.invoiceNumber}', style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Text('التاريخ: ${_df.format(data.date)}', style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Text('الكاشير: ${data.cashierName}', style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Divider(),

            // Customer Section
            pw.Text(
              data.customerName != null ? 'العميل: ${data.customerName}' : 'زبون نقدي', 
              style: pw.TextStyle(font: fontBold, fontSize: 11)
            ),
            if (loyaltyEnabled && data.customerName != null && data.pointsAfter != null) ...[
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('★', style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.amber700)),
                  pw.SizedBox(width: 4),
                  pw.Text('إجمالي النقاط: ${_nf.format(data.pointsAfter)}', style: pw.TextStyle(font: font, fontSize: 10)),
                ]
              )
            ],
            pw.Divider(),

            // Items Table
            ...data.items.map((item) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(item.name, style: pw.TextStyle(font: fontBold, fontSize: 11)),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('${_nf.format(item.qty)} × ${_nf.format(item.unitPrice)}', style: pw.TextStyle(font: font, fontSize: 10)),
                    pw.Text(_nf.format(item.total), style: pw.TextStyle(font: fontBold, fontSize: 10)),
                  ],
                ),
                if (item.discount > 0)
                  pw.Text('خصم: ${_nf.format(item.discount)}', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.red700)),
                pw.SizedBox(height: 3),
              ],
            )),
            pw.Divider(),

            // Totals Section
            _receiptRow('المجموع الفرعي:', _nf.format(data.subtotal), font, fontBold),
            if (data.discount > 0)
              _receiptRow('الخصم:', _nf.format(data.discount), font, fontBold),
            _receiptRow('الإجمالي:', _nf.format(data.total), font, fontBold, large: true),
            pw.SizedBox(height: 4),

            // Payment Section
            _receiptRow('طريقة الدفع:', data.paymentMethod == 'CASH' ? 'نقدي' : data.paymentMethod == 'CARD' ? 'بطاقة' : data.paymentMethod == 'DEBT' ? 'آجل' : 'مختلط', font, fontBold),
            if (data.cashPaid > 0) _receiptRow('المدفوع:', _nf.format(data.cashPaid), font, fontBold),
            if (data.change > 0) _receiptRow('الباقي:', _nf.format(data.change), font, fontBold),
            if (data.currentDebt != null && data.currentDebt! > 0)
              _receiptRow('المتبقي (دين):', _nf.format(data.currentDebt), font, fontBold),
            pw.Divider(),

            // Loyalty Section
            if (loyaltyEnabled && data.customerName != null && data.pointsBefore != null) ...[
              pw.Text('برنامج الولاء', style: pw.TextStyle(font: fontBold, fontSize: 10), textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 2),
              _receiptRow('النقاط السابقة:', _nf.format(data.pointsBefore), font, font, small: true),
              _receiptRow('النقاط المكتسبة/المستخدمة:', _nf.format(data.pointsEarned ?? 0), font, font, small: true),
              _receiptRow('الرصيد الحالي للعضو:', _nf.format(data.pointsAfter), font, fontBold, small: true),
              pw.Divider(),
            ],

            // Footer
            pw.Text('شكراً لتسوقكم معنا', style: pw.TextStyle(font: font, fontSize: 10), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 8),
            pw.Text('Powered by Birtij Software', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700), textAlign: pw.TextAlign.center),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  static pw.Widget _receiptRow(String label, String value, pw.Font font, pw.Font fontBold, {bool large = false, bool small = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: large ? 13 : small ? 9 : 11)),
        pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: large ? 13 : small ? 9 : 11)),
      ],
    );
  }
}
