class OtherIncomeSummary {
  const OtherIncomeSummary({
    required this.activeCount,
    required this.totalAmount,
    required this.voidedCount,
    required this.categoryCount,
  });

  final int activeCount;
  final double totalAmount;
  final int voidedCount;
  final int categoryCount;
}
