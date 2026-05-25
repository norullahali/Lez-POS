enum LoyaltyInsightType { vip, inactive, repeat, retention }

class LoyaltyInsight {
  const LoyaltyInsight({
    required this.customerId,
    required this.customerName,
    required this.type,
    required this.message,
    required this.recommendation,
    required this.priorityScore,
    this.lifetimeValueEstimate,
    this.actionRoute,
  });
  final int customerId;
  final String customerName;
  final LoyaltyInsightType type;
  final String message;
  final String recommendation;
  final int priorityScore;
  final double? lifetimeValueEstimate;
  final String? actionRoute;
}