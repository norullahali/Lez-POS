import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Allocates POS sales invoice numbers atomically inside a sale transaction.
class InvoiceNumberService {
  final AppDatabase db;

  InvoiceNumberService(this.db);

  /// Builds the daily prefix (`YYYYMMDD`) for [date].
  static String dayPrefixFor(DateTime date) {
    return '${date.year}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// Formats a daily sequence value as `YYYYMMDD-NNNN`.
  static String formatInvoiceNumber(String dayPrefix, int sequenceNumber) {
    return '$dayPrefix-${sequenceNumber.toString().padLeft(4, '0')}';
  }

  /// Parses the numeric suffix from a conforming `YYYYMMDD-NNNN` invoice number.
  /// Returns null when the value does not match the supported legacy format.
  static int? parseConformingSuffix(String invoiceNumber) {
    if (invoiceNumber.length < 10) return null;
    if (invoiceNumber[8] != '-') return null;
    final prefix = invoiceNumber.substring(0, 8);
    if (!RegExp(r'^\d{8}$').hasMatch(prefix)) return null;
    final suffix = invoiceNumber.substring(9);
    if (!RegExp(r'^\d+$').hasMatch(suffix)) return null;
    return int.tryParse(suffix);
  }

  /// Atomically allocates the next invoice number for [date].
  ///
  /// Must run inside an enclosing database transaction on the same connection
  /// as the subsequent `sales_invoices` insert.
  Future<String> allocateNextInTransaction({DateTime? date}) async {
    final dayPrefix = dayPrefixFor(date ?? DateTime.now());

    await db.customStatement(
      '''
      INSERT INTO sales_invoice_daily_sequences (day_prefix, last_number)
      VALUES (?, 1)
      ON CONFLICT(day_prefix) DO UPDATE SET last_number = last_number + 1
      ''',
      [dayPrefix],
    );

    final row = await db.customSelect(
      'SELECT last_number FROM sales_invoice_daily_sequences WHERE day_prefix = ?',
      variables: [Variable.withString(dayPrefix)],
      readsFrom: {db.salesInvoiceDailySequences},
    ).getSingle();

    final sequenceNumber = row.read<int>('last_number');
    return formatInvoiceNumber(dayPrefix, sequenceNumber);
  }
}