import '../../features/pos/models/invoice_models.dart';

/// Receipt totals aligned with [InvoiceDetailData] / invoice detail UI semantics.
class ReceiptFinancials {
  ReceiptFinancials._();

  static double subtotal(InvoiceData data) =>
      data.headerSubtotal ??
      data.items.fold(0.0, (sum, item) => sum + item.lineTotal);

  static double headerDiscount(InvoiceData data) =>
      data.headerDiscountTotal ?? 0;

  static double netBeforeTax(InvoiceData data) =>
      (subtotal(data) - headerDiscount(data)).clamp(0.0, double.infinity);

  static double taxDisplayAmount(InvoiceData data) =>
      data.showTax ? netBeforeTax(data) * 0.15 : 0;

  /// Authoritative grand total — never includes display-only tax.
  static double grandTotal(InvoiceData data) => data.total;
}
