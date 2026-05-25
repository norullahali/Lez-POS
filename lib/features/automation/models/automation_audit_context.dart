enum AutomationSourceEngine {
  reorder,
  purchase,
  restock,
  debt,
  loyalty,
  cashier,
  alert,
  workflow,
  assistant,
  scheduler,
}

enum HeuristicConfidence { low, medium, high }

class AutomationAuditContext {
  const AutomationAuditContext({
    required this.whyGenerated,
    required this.sourceEngine,
    required this.heuristicExplanation,
    required this.triggerSource,
    this.sourceMetrics = const {},
    this.confidence = HeuristicConfidence.medium,
  });

  final String whyGenerated;
  final AutomationSourceEngine sourceEngine;
  final Map<String, dynamic> sourceMetrics;
  final String heuristicExplanation;
  final String triggerSource;
  final HeuristicConfidence confidence;
}