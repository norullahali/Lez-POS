class OperationsThresholds {
  OperationsThresholds._();

  static const deadStockDays = 30;
  static const deadStockInsightDays = 45;
  static const overstockMinMultiplier = 3.0;
  static const overstockSalesRatio = 0.1;
  static const overstockLookbackDays = 14;
  static const lowStockDisplayLimit = 10;
  static const deadStockDisplayLimit = 8;
  static const overstockDisplayLimit = 5;

  static const velocityDays = 7;
  static const criticalDaysRemaining = 3;
  static const urgentDaysRemaining = 7;
  static const warningDaysRemaining = 14;

  static const suspiciousRefundCount = 3;
  static const suspiciousRefundCriticalCount = 5;
  static const suspiciousRefundAmount = 100.0;
  static const suspiciousRefundCriticalAmount = 500.0;
  static const returnSpikeRatio = 1.5;
  static const returnSpikeMinAmount = 50.0;

  static const suspiciousActionMinCount = 3;
  static const suspiciousActionCriticalCount = 5;
  static const criticalActivitySpikeCount = 5;

  static const weakSalesMinYesterday = 100.0;
  static const weakSalesRatio = 0.6;
  static const weakSalesCriticalDropPercent = 50.0;

  static const overdueDebtMinBalance = 50.0;
  static const overdueDebtCriticalBalance = 500.0;
  static const sessionMismatchMinDiff = 5.0;
  static const sessionMismatchCriticalDiff = 50.0;

  static const discountInvoiceRatio = 0.4;
  static const shortSessionMinutes = 15.0;

  static const alertCooldownMinutes = 30;
  static const groupAlertsMinCount = 3;

  static const jobMaxRetries = 1;
  static const jobStartupDelaySeconds = 2;

  static const maxStoredSnapshots = 30;
}