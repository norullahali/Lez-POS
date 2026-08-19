/// Cash Ledger v1 — read-only event types derived from operational tables.
enum CashLedgerEventType {
  saleCash('SALE_CASH', 'بيع نقدي', true),
  customerPayment('CUSTOMER_PAYMENT', 'تحصيل عميل', true),

  /// Cash paid to customer against accumulated credit (Phase C Step 2.2).
  /// Source of truth: customer_transactions WHERE type = 'REFUND'.
  customerRefund('CUSTOMER_REFUND', 'استرداد نقدي للعميل', false),

  purchaseCash('PURCHASE_CASH', 'دفع مشتريات', false),
  supplierPayment('SUPPLIER_PAYMENT', 'دفع مورد', false),

  /// Cash received from supplier against supplier credit (SR.3.3).
  /// Source of truth: supplier_transactions WHERE type = 'REFUND'.
  supplierRefund('SUPPLIER_REFUND', 'استرداد من مورد', true),

  returnRefund('RETURN_REFUND', 'مرتجع نقدي', false),

  /// Operational expense — outflow from expense_records (Phase 3.3).
  /// Color hint: warning/orange. Source of truth: expense_records.is_voided = 0.
  expense('EXPENSE', '\u0645\u0635\u0631\u0648\u0641', false),

  /// Other income — inflow from other_income_records (Phase 4.3).
  /// Color hint: success/green. Source of truth: other_income_records.is_voided = 0.
  otherIncome('OTHER_INCOME',
      '\u0625\u064a\u0631\u0627\u062f \u0622\u062e\u0631', true);

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
