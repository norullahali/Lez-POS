// lib/core/services/receipt_service.dart
//
// Public print entry points for Lez POS.
//
// This file is intentionally thin: it collects invoice data from settings +
// arguments, assembles an InvoiceData object, then hands it off to
// PrintManager. All adapter selection, PDF building, and delivery logic lives
// in lib/core/printing/.

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import '../../features/pos/models/invoice_models.dart';
import '../database/app_database.dart';
import '../printing/print_manager.dart';
import 'settings_service.dart';

/// Prints a POS sale receipt.
///
/// Parameters mirror the fields of [InvoiceData] that are known at the
/// call site (pos_screen.dart). Store info and printer config are loaded
/// from [SettingsService] automatically.
///
/// Throws on unrecoverable print errors; the caller is responsible for
/// showing user-visible feedback (e.g. SnackBar).
Future<void> printSale({
  required String invoiceNumber,
  required List<InvoiceItem> items,
  double? paid,
  double? change,
  double? loyaltyPoints,
  String? customerName,
  String? cashierName,
  // ── Return metadata ─────────────────────────────────────────────────────
  bool isReturned = false,
  DateTime? returnDate,
  String? returnNote,
  String? returnedByName,
}) async {
  debugPrint('[ReceiptService] printSale() called — invoice: $invoiceNumber');

  final settings = SettingsService(AppDatabase.instance);

  // ── Load store & invoice settings (all from DB via SettingsService) ───────
  final storeName = await settings.getStoreName();
  final phone     = await settings.getPhone();
  final address   = await settings.getAddress();
  final logoPath  = await settings.getStoreLogoPath();
  final footer    = await settings.getInvoiceFooter();
  final footer2   = await settings.getInvoiceFooter2();
  final showTax   = await settings.getShowTax();
  final showQr    = await settings.getShowQr();

  // ── Load logo bytes if a logo file is configured ───────────────────────────
  Uint8List? logoBytes;
  if (logoPath != null) {
    final file = File(logoPath);
    if (await file.exists()) logoBytes = await file.readAsBytes();
  }

  // ── Calculate total ────────────────────────────────────────────────────────
  final total = items.fold(0.0, (sum, e) => sum + e.lineTotal);

  // ── Build invoice data ─────────────────────────────────────────────────────
  final invoiceData = InvoiceData(
    invoiceNumber: invoiceNumber,
    items: items,
    storeName: storeName,
    total: total,
    customerName: customerName,
    cashierName: cashierName,
    phone: phone,
    address: address,
    logoBytes: logoBytes,
    paid: paid,
    change: change,
    loyaltyPoints: loyaltyPoints,
    footer: footer,
    footer2: footer2,
    showTax: showTax,
    showQr: showQr,
    isReturned: isReturned,
    returnDate: returnDate,
    returnNote: returnNote,
    returnedByName: returnedByName,
  );

  // ── Route to the correct printer via PrintManager ──────────────────────────
  final config  = await settings.getPrinterConfig();
  final manager = PrintManager(config);

  debugPrint('[ReceiptService] Delegating to PrintManager (${config.type.name})...');
  await manager.print(invoiceData);
  debugPrint('[ReceiptService] printSale() completed.');
}
