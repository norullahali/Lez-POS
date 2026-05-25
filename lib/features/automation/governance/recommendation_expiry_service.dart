import '../models/recommendation_invalidation.dart';
import '../stores/recommendation_lifecycle_store.dart';

class RecommendationExpiryService {
  RecommendationExpiryService._();

  static DateTime computeExpiresAt({
    required RecommendationExpiryPolicy policy,
    required DateTime from,
  }) =>
      from.add(policy.ttl);

  static bool shouldExpire({
    required RecommendationRecord record,
    Map<String, dynamic>? liveMetrics,
  }) {
    if (record.isStale) return true;
    final metrics = liveMetrics ?? record.sourceMetrics;
    for (final trigger in record.invalidatesOn) {
      if (_triggered(trigger, metrics, record)) return true;
    }
    return false;
  }

  static bool _triggered(
    RecommendationInvalidatesOn trigger,
    Map<String, dynamic> metrics,
    RecommendationRecord record,
  ) {
    return switch (trigger) {
      RecommendationInvalidatesOn.stockRefresh =>
        (metrics['currentStock'] as num?) != null &&
            (metrics['minStock'] as num?) != null &&
            (metrics['currentStock'] as num) > (metrics['minStock'] as num) * 2,
      RecommendationInvalidatesOn.debtPayment =>
        (metrics['balance'] as num?) != null && (metrics['balance'] as num) < 50,
      RecommendationInvalidatesOn.salesRecovery =>
        (metrics['salesRecovered'] as bool?) == true,
      RecommendationInvalidatesOn.manualDismiss => record.lifecycleState.name == 'ignored',
      RecommendationInvalidatesOn.ttl => record.isStale,
    };
  }
}