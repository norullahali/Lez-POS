import '../rules/operations_rules.dart';

class RuleEvaluation {
  const RuleEvaluation({required this.ruleId, required this.passed, required this.detail});
  final String ruleId;
  final bool passed;
  final String detail;
}

class RulesEngineService {
  RulesEngineService._();

  static List<RuleEvaluation> evaluateReorder({required double daysRemaining, required double dailyRate}) {
    return [
      RuleEvaluation(
        ruleId: 'reorder_critical_days',
        passed: daysRemaining <= OperationsRules.reorderCriticalDays,
        detail: 'متبقي ${daysRemaining.toStringAsFixed(1)} يوم',
      ),
      RuleEvaluation(
        ruleId: 'reorder_min_rate',
        passed: dailyRate >= OperationsRules.reorderMinDailyRate,
        detail: 'معدل ${dailyRate.toStringAsFixed(2)}/يوم',
      ),
    ];
  }

  static bool passesDebtFollowUp(double balance) => balance >= OperationsRules.overdueDebtBalance;
  static bool passesRefundSpike(int count, double amount) =>
      count >= OperationsRules.refundSpikeCount.toInt() || amount >= OperationsRules.refundSpikeAmount;
}