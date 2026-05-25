import '../models/automation_audit_context.dart';
import '../models/recommendation_invalidation.dart';
import '../models/workflow_lifecycle_state.dart';
import '../stores/recommendation_lifecycle_store.dart';
import 'recommendation_expiry_service.dart';
import 'recommendation_fingerprint.dart';

class RecommendationMergeResult {
  const RecommendationMergeResult({
    required this.record,
    required this.suppressed,
    required this.merged,
  });

  final RecommendationRecord record;
  final bool suppressed;
  final bool merged;
}

class RecommendationDeduplicationService {
  RecommendationDeduplicationService._();

  static Future<RecommendationMergeResult> merge({
    required String fingerprint,
    required String kind,
    required AutomationSourceEngine sourceEngine,
    required String whyGenerated,
    required String heuristicExplanation,
    required String triggerSource,
    required RecommendationExpiryPolicy policy,
    Map<String, dynamic> sourceMetrics = const {},
    HeuristicConfidence confidence = HeuristicConfidence.medium,
    String? titleSnapshot,
    String? entityType,
    int? entityId,
  }) async {
    final records = await RecommendationLifecycleStore.load();
    final now = DateTime.now();
    final existing = records[fingerprint];

    if (existing != null) {
      if (RecommendationExpiryService.shouldExpire(record: existing, liveMetrics: sourceMetrics)) {
        final expired = existing.copyWith(lifecycleState: WorkflowLifecycleState.expired);
        records[fingerprint] = expired;
        await RecommendationLifecycleStore.save(records);
      } else if (!existing.lifecycleState.allowsRefresh) {
        return RecommendationMergeResult(record: existing, suppressed: !existing.lifecycleState.isVisible, merged: false);
      } else if (existing.lifecycleState == WorkflowLifecycleState.ignored) {
        return RecommendationMergeResult(record: existing, suppressed: true, merged: false);
      }
    }

    final expiresAt = RecommendationExpiryService.computeExpiresAt(policy: policy, from: now);
    final record = existing == null || existing.lifecycleState == WorkflowLifecycleState.expired
        ? RecommendationRecord(
            fingerprint: fingerprint,
            kind: kind,
            sourceEngine: sourceEngine,
            lifecycleState: WorkflowLifecycleState.pending,
            generatedAt: now,
            lastRefreshedAt: now,
            occurrenceCount: 1,
            whyGenerated: whyGenerated,
            sourceMetrics: sourceMetrics,
            heuristicExplanation: heuristicExplanation,
            triggerSource: triggerSource,
            confidence: confidence,
            expiresAt: expiresAt,
            invalidatesOn: policy.invalidatesOn,
            titleSnapshot: titleSnapshot,
            entityType: entityType,
            entityId: entityId,
          )
        : existing.copyWith(
            lastRefreshedAt: now,
            occurrenceCount: existing.occurrenceCount + 1,
            whyGenerated: whyGenerated,
            sourceMetrics: sourceMetrics,
            expiresAt: expiresAt,
            titleSnapshot: titleSnapshot ?? existing.titleSnapshot,
          );

    await RecommendationLifecycleStore.upsert(record);
    return RecommendationMergeResult(record: record, suppressed: false, merged: existing != null);
  }

  static RecommendationExpiryPolicy policyForEngine(AutomationSourceEngine engine) => switch (engine) {
        AutomationSourceEngine.reorder => RecommendationExpiryPolicy.reorder,
        AutomationSourceEngine.purchase => RecommendationExpiryPolicy.reorder,
        AutomationSourceEngine.restock => RecommendationExpiryPolicy.reorder,
        AutomationSourceEngine.debt => RecommendationExpiryPolicy.debt,
        AutomationSourceEngine.assistant => RecommendationExpiryPolicy.sales,
        _ => RecommendationExpiryPolicy.defaultPolicy,
      };

  static String fingerprintFor({
    required AutomationSourceEngine engine,
    required String kind,
    String? entityType,
    int? entityId,
  }) =>
      RecommendationFingerprint.forKind(
        engine: engine,
        kind: kind,
        entityType: entityType,
        entityId: entityId,
      );
}