class OperationRuleDefinition {
  const OperationRuleDefinition({
    required this.id,
    required this.labelAr,
    required this.threshold,
    required this.unit,
  });
  final String id;
  final String labelAr;
  final double threshold;
  final String unit;
}

class OperationsRules {
  OperationsRules._();

  static const reorderCriticalDays = 3.0;
  static const reorderUrgentDays = 7.0;
  static const reorderMinDailyRate = 0.5;
  static const refundSpikeCount = 3.0;
  static const refundSpikeAmount = 200.0;
  static const overdueDebtBalance = 50.0;
  static const overdueDebtCritical = 500.0;
  static const inactiveCustomerDays = 45.0;
  static const vipMinSpend = 1000.0;
  static const weakSalesDropRatio = 0.6;

  static const definitions = [
    OperationRuleDefinition(id: 'reorder_critical_days', labelAr: 'ايام نفاد حرجة', threshold: reorderCriticalDays, unit: 'days'),
    OperationRuleDefinition(id: 'refund_spike_count', labelAr: 'حد المرتجعات', threshold: refundSpikeCount, unit: 'count'),
    OperationRuleDefinition(id: 'overdue_debt_balance', labelAr: 'حد الذمة', threshold: overdueDebtBalance, unit: 'amount'),
    OperationRuleDefinition(id: 'inactive_customer_days', labelAr: 'ايام عدم النشاط', threshold: inactiveCustomerDays, unit: 'days'),
  ];
}