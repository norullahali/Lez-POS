abstract class OperationsInsightEngine {
  Future<List<String>> generateSmartInsights();
}

abstract class OperationsAnomalyScorer {
  Future<double> scoreCashier(int userId);
}

abstract class PredictiveOrderingEngine {
  Future<Map<int, double>> suggestReorderQuantities();
}

abstract class OperationsAiAnomalyScorer {
  Future<double> scoreAlertFingerprint(String fingerprint);
}

abstract class SmartPurchasingEngine {
  Future<Map<int, double>> recommendPurchaseOrders();
}

abstract class AutomatedRecommendationsEngine {
  Future<List<String>> buildRecommendations();
}