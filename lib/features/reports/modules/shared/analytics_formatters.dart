import 'package:intl/intl.dart';

/// Centralized Arabic-friendly analytics formatting.
class AnalyticsFormatters {
  AnalyticsFormatters._();

  static final NumberFormat currency = NumberFormat('#,##0');
  static final NumberFormat percent = NumberFormat('#,##0.0');
  static final NumberFormat quantity = NumberFormat('#,##0.##');
  static final DateFormat exportTimestamp = DateFormat('yyyy/MM/dd HH:mm');

  static const String empty = '—';
  static const String currencySuffix = ' د.ع';

  static String money(double? value, {String ifEmpty = empty}) {
    if (value == null) return ifEmpty;
    return '${currency.format(value)}$currencySuffix';
  }

  static String pct(double? value, {String ifEmpty = empty, int decimals = 1}) {
    if (value == null) return ifEmpty;
    return '${value.toStringAsFixed(decimals)}%';
  }

  static String qty(num? value, {String ifEmpty = empty}) {
    if (value == null) return ifEmpty;
    return quantity.format(value);
  }

  static String label(String? value, {String ifEmpty = empty}) {
    if (value == null || value.trim().isEmpty) return ifEmpty;
    return value;
  }

  static String signedMoney(double delta) {
    final sign = delta > 0 ? '+' : '';
    return '$sign${money(delta)}';
  }

  static String signedPercent(double delta, {int decimals = 1}) {
    final sign = delta > 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(decimals)}%';
  }

  static String exportTime([DateTime? at]) => exportTimestamp.format(at ?? DateTime.now());
}
