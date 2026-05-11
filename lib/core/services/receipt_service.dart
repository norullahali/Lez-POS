import 'dart:io';
import 'dart:typed_data';
import 'package:printing/printing.dart';

import '../../features/pos/models/invoice_models.dart';
import '../utils/invoice_pdf_builder_clean.dart';
import '../database/app_database.dart';
import 'settings_service.dart';
import 'thermal_printer_service.dart';

Future<void> printSale({
  double? paid,
  double? change,
  double? loyaltyPoints,
  required String invoiceNumber,
  required List<InvoiceItem> items,
  String? customerName,
}) async {
  final settings = SettingsService(AppDatabase.instance);

  // 🧪 DEBUG
  print("PRINT FUNCTION CALLED");

  // ── Load store settings ─────────────────────────
  final storeName = await settings.getStoreName();
  final phone = await settings.getPhone();
  final address = await settings.getAddress();
  final logoPath = await settings.getStoreLogoPath();

  final footer = await settings.getInvoiceFooter();
  final showTax = await settings.getShowTax();

  // ── Load logo if exists ─────────────────────────
  Uint8List? logoBytes;

  if (logoPath != null) {
    final file = File(logoPath);
    if (await file.exists()) {
      logoBytes = await file.readAsBytes();
    }
  }

  // ── Calculate total ─────────────────────────
  final total = items.fold(0.0, (sum, e) => sum + e.lineTotal);

  // ── Build invoice data ─────────────────────────
  final pdfData = InvoiceData(
    invoiceNumber: invoiceNumber,
    items: items,
    storeName: storeName,
    total: total,
    customerName: customerName,
    phone: phone,
    address: address,
    logoBytes: logoBytes,
    paid: paid,
    change: change,
    loyaltyPoints: loyaltyPoints,
    footer: footer,
    showTax: showTax,
  );

  // ── Build PDF ─────────────────────────
  final builder = InvoicePdfBuilderClean();

  final pdfBytes = await builder.buildInvoice(
    pdfData,
    paperSize: ReceiptPaperSize.thermal80,
  );

  // ── Print ─────────────────────────
  try {
    final printerType = await settings.getPrinterType();

    if (printerType == 'pdf') {
      // 💾 حفظ ملف PDF مؤقت
      final file = File('${Directory.systemTemp.path}/invoice.pdf');
      await file.writeAsBytes(pdfBytes);

      // 🖨️ طباعة مباشرة عبر Windows
      await Process.run(
        'powershell',
        ['-Command', 'Start-Process -FilePath "${file.path}" -Verb Print'],
      );

      print("Printed via Windows");
    } else {
      // 🔥 Thermal
      final thermal = ThermalPrinterService();
      await thermal.printInvoice(pdfData);
    }
  } catch (e) {
    print('PRINT ERROR: $e');
  }
}
