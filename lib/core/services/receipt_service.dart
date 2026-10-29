// lib/core/services/receipt_service.dart

import 'package:flutter/foundation.dart';

import '../../features/invoices/repositories/invoice_history_repository.dart';
import '../../features/pos/models/invoice_models.dart';
import '../database/app_database.dart';
import '../printing/print_manager.dart';
import '../printing/print_outcome.dart';
import 'receipt_invoice_mapper.dart';
import 'settings_service.dart';

Future<InvoiceData> loadPersistedReceiptData(
  int invoiceId,
  AppDatabase db,
) async {
  final detail =
      await InvoiceHistoryRepository(db).fetchInvoiceDetail(invoiceId);
  return ReceiptInvoiceMapper.buildFromDetail(detail, SettingsService(db));
}

Future<PrintOutcome> printInvoiceById(int invoiceId) async {
  debugPrint('[ReceiptService] printInvoiceById($invoiceId)');

  final db = AppDatabase.instance;
  final settings = SettingsService(db);
  final invoiceData = await loadPersistedReceiptData(invoiceId, db);

  final config = await settings.getPrinterConfig();
  final manager = PrintManager(config);

  debugPrint(
      '[ReceiptService] Delegating to PrintManager (${config.type.name})...');
  final outcome = await manager.print(invoiceData);
  debugPrint(
      '[ReceiptService] printInvoiceById finished — ${outcome.kind.name}/${outcome.code}');
  return outcome;
}
