enum RecommendationInvalidatesOn {
  stockRefresh,
  debtPayment,
  salesRecovery,
  manualDismiss,
  ttl,
}

class RecommendationExpiryPolicy {
  const RecommendationExpiryPolicy({
    required this.ttl,
    this.invalidatesOn = const [],
  });

  final Duration ttl;
  final List<RecommendationInvalidatesOn> invalidatesOn;

  static const reorder = RecommendationExpiryPolicy(
    ttl: Duration(days: 7),
    invalidatesOn: [RecommendationInvalidatesOn.stockRefresh, RecommendationInvalidatesOn.ttl],
  );

  static const debt = RecommendationExpiryPolicy(
    ttl: Duration(days: 14),
    invalidatesOn: [RecommendationInvalidatesOn.debtPayment, RecommendationInvalidatesOn.ttl],
  );

  static const sales = RecommendationExpiryPolicy(
    ttl: Duration(days: 7),
    invalidatesOn: [RecommendationInvalidatesOn.salesRecovery, RecommendationInvalidatesOn.ttl],
  );

  static const defaultPolicy = RecommendationExpiryPolicy(ttl: Duration(days: 5));
}