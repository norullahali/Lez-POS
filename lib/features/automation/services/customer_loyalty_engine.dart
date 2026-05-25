import '../cache/automation_cache.dart';
import '../models/loyalty_insight.dart';
import '../repositories/automation_repository.dart';
import '../rules/operations_rules.dart';

class CustomerLoyaltyEngine {
  CustomerLoyaltyEngine(this._repo);
  final AutomationRepository _repo;

  Future<List<LoyaltyInsight>> generateInsights() async {
    return AutomationCache.memo('loyalty_insights', () async {
      final rows = await _repo.fetchLoyaltyCustomers();
      final now = DateTime.now();
      final insights = <LoyaltyInsight>[];
      for (final row in rows) {
        final id = row['id'] as int;
        final name = row['name'] as String? ?? 'عميل';
        final spend = (row['lifetime_spend'] as num).toDouble();
        final lastRaw = row['last_purchase'];
        DateTime? last;
        if (lastRaw is DateTime) last = lastRaw;
        if (lastRaw is String) last = DateTime.tryParse(lastRaw);
        final inactiveDays = last == null ? 999 : now.difference(last).inDays;

        if (spend >= OperationsRules.vipMinSpend) {
          insights.add(LoyaltyInsight(
            customerId: id,
            customerName: name,
            type: LoyaltyInsightType.vip,
            message: 'عميل VIP — إجمالي مشتريات ${spend.toStringAsFixed(0)}',
            recommendation: 'قدّم عناية خاصة أو عرض ولاء',
            priorityScore: 70,
            lifetimeValueEstimate: spend,
            actionRoute: '/customers/profile/$id',
          ));
        }
        if (inactiveDays >= OperationsRules.inactiveCustomerDays.toInt() && spend > 0) {
          insights.add(LoyaltyInsight(
            customerId: id,
            customerName: name,
            type: LoyaltyInsightType.inactive,
            message: 'غير نشط منذ $inactiveDays يوماً',
            recommendation: 'تواصل للاحتفاظ بالعميل',
            priorityScore: 50,
            lifetimeValueEstimate: spend,
            actionRoute: '/customers/profile/$id',
          ));
        }
        if (spend > 200 && inactiveDays < 14) {
          insights.add(LoyaltyInsight(
            customerId: id,
            customerName: name,
            type: LoyaltyInsightType.repeat,
            message: 'عميل متكرر نشط',
            recommendation: 'راقب رضاه وقدّم مكافآت',
            priorityScore: 40,
            lifetimeValueEstimate: spend,
            actionRoute: '/customers/profile/$id',
          ));
        }
      }
      insights.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
      return insights.take(20).toList();
    });
  }
}