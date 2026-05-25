class CashierBehaviorRow {
  const CashierBehaviorRow({
    required this.userId,
    required this.name,
    required this.refundCount,
    required this.refundAmount,
    required this.invoiceCount,
    required this.averageInvoice,
    required this.discountInvoices,
    required this.sessionMismatchCount,
    required this.inactivityMinutes,
    required this.flags,
  });

  final int userId;
  final String name;
  final int refundCount;
  final double refundAmount;
  final int invoiceCount;
  final double averageInvoice;
  final int discountInvoices;
  final int sessionMismatchCount;
  final double inactivityMinutes;
  final List<String> flags;
}
