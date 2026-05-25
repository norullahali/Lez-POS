import '../cache/automation_cache.dart';
import '../governance/recommendation_governance_service.dart';
import '../models/automation_audit_context.dart';
import '../models/business_guidance_item.dart';
import '../repositories/automation_repository.dart';
import '../rules/operations_rules.dart';
import '../../operations/repositories/operations_intelligence_repository.dart';
import '../../operations/services/operational_evaluation_cache.dart';

class BusinessAssistantService {
  BusinessAssistantService(
    this._repo,
    this._opsRepo, {
    RecommendationGovernanceService? governance,
  }) : _governance = governance ?? RecommendationGovernanceService();

  final AutomationRepository _repo;
  final OperationsIntelligenceRepository _opsRepo;
  final RecommendationGovernanceService _governance;

  Future<List<BusinessGuidanceItem>> buildGuidance() async {
    return AutomationCache.memo('business_guidance_v1', () async {
      final items = <BusinessGuidanceItem>[];
      final now = DateTime.now();

      final week = await _repo.fetchSalesWeekComparison();
      final thisWeek = (week['this_week'] as num?)?.toDouble() ?? 0;
      final prevWeek = (week['prev_week'] as num?)?.toDouble() ?? 0;
      if (prevWeek > 100 && thisWeek < prevWeek * OperationsRules.weakSalesDropRatio) {
        final drop = ((prevWeek - thisWeek) / prevWeek * 100).clamp(0, 999);
        items.add(BusinessGuidanceItem(
          id: 'sales_down_week',
          whatHappened: 'المبيعات انخفضت مقارنة بالأسبوع الماضي',
          whyDetected:
              'انخفاض ~${drop.toStringAsFixed(0)}% — مبيعات هذا الأسبوع (${thisWeek.toStringAsFixed(0)}) أقل من ${(OperationsRules.weakSalesDropRatio * 100).toInt()}% من الأسبوع السابق',
          nextStep: 'راجع التقارير وحدد الفئات الضعيفة',
          severity: GuidanceSeverity.warning,
          actionRoute: '/reports',
          fingerprint: 'assistant|sales_down_week',
          lastRefreshedAt: now,
          audit: AutomationAuditContext(
            whyGenerated: 'مبيعات الأسبوع الحالي أقل من ${OperationsRules.weakSalesDropRatio * 100}% من السابق',
            sourceEngine: AutomationSourceEngine.assistant,
            heuristicExplanation: 'مقارنة rolling 7-day sales',
            triggerSource: 'weakSalesDropRatio',
            sourceMetrics: {
              'thisWeek': thisWeek,
              'prevWeek': prevWeek,
              'financialImpact': prevWeek - thisWeek,
            },
            confidence: HeuristicConfidence.high,
          ),
        ));
      } else if (thisWeek > prevWeek * 1.1 && prevWeek > 0) {
        final gain = ((thisWeek - prevWeek) / prevWeek * 100).clamp(0, 999);
        items.add(BusinessGuidanceItem(
          id: 'sales_up_week',
          whatHappened: 'المبيعات تحسنت مقارنة بالأسبوع الماضي',
          whyDetected: 'ارتفاع ~${gain.toStringAsFixed(0)}% عن الأسبوع السابق',
          nextStep: 'حافظ على المنتجات الأكثر مبيعاً',
          severity: GuidanceSeverity.positive,
          actionRoute: '/reports',
          fingerprint: 'assistant|sales_up_week',
          lastRefreshedAt: now,
          audit: AutomationAuditContext(
            whyGenerated: 'مبيعات الأسبوع الحالي أعلى من السابق',
            sourceEngine: AutomationSourceEngine.assistant,
            heuristicExplanation: 'مقارنة rolling 7-day sales',
            triggerSource: 'salesImprovement',
            sourceMetrics: {'thisWeek': thisWeek, 'prevWeek': prevWeek},
            confidence: HeuristicConfidence.medium,
          ),
        ));
      }

      final returnRate =
          await OperationalEvaluationCache.memo('return_rate', () => _opsRepo.fetchReturnRateComparison());
      final todayReturns = (returnRate['today_returns'] as num?)?.toDouble() ?? 0;
      final avgDaily = (returnRate['avg_daily_returns'] as num?)?.toDouble() ?? 0;
      if (avgDaily > 0 && todayReturns > avgDaily * 1.5) {
        items.add(BusinessGuidanceItem(
          id: 'returns_spike',
          whatHappened: 'يوجد ارتفاع غير طبيعي في المرتجعات',
          whyDetected:
              'مرتجعات اليوم (${todayReturns.toStringAsFixed(0)}) أعلى من المتوسط (${avgDaily.toStringAsFixed(0)})',
          nextStep: 'راجع تحليلات المرتجعات والكاشير',
          severity: GuidanceSeverity.warning,
          actionRoute: '/return-analytics',
          fingerprint: 'assistant|returns_spike',
          lastRefreshedAt: now,
          audit: AutomationAuditContext(
            whyGenerated: 'مرتجعات اليوم > 150% من المتوسط اليومي',
            sourceEngine: AutomationSourceEngine.assistant,
            heuristicExplanation: 'return rate comparison heuristic',
            triggerSource: 'returnsSpike',
            sourceMetrics: {'todayReturns': todayReturns, 'avgDailyReturns': avgDaily},
            confidence: HeuristicConfidence.high,
          ),
        ));
      }

      return _governance.governGuidance(items);
    });
  }
}
