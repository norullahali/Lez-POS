/// Cash Ledger v1 — read-only event types derived from operational tables.
enum CashLedgerEventType {
  saleCash('SALE_CASH', 'بيع نقدي', true),
  customerPayment('CUSTOMER_PAYMENT', 'تحصيل عميل', true),
  purchaseCash('PURCHASE_CASH', 'دفع مشتريات', false),
  supplierPayment('SUPPLIER_PAYMENT', 'دفع مورد', false),
  returnRefund('RETURN_REFUND', 'مرتجع نقدي', false),

  /// Operational expense — outflow from expense_records (Phase 3.3).
  /// Color hint: warning/orange. Source of truth: expense_records.is_voided = 0.
  expense('EXPENSE', '\u0645\u0635\u0631\u0648\u0641', false);

  const CashLedgerEventType(this.code, this.labelAr, this.isInflow);

  final String code;
  final String labelAr;
  final bool isInflow;

  static CashLedgerEventType? fromCode(String? code) {
    if (code == null) return null;
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}