import 'package:intl/intl.dart';

/// Display formatting for receipt amounts — matches invoice detail UI
/// ([InvoiceDetailsDialog._money] / `NumberFormat('#,##0.##')`).
class ReceiptMoneyFormat {
  ReceiptMoneyFormat._();

  static final NumberFormat _money = NumberFormat('#,##0.##');

  static NumberFormat get moneyFormat => _money;

  static String formatAmount(num value) => _money.format(value);

  /// Formatted amount followed by IQD suffix (as on printed receipts).
  static String formatIqd(num value) => '${formatAmount(value)} د.ع';
}