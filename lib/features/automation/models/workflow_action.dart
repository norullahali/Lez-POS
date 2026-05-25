enum WorkflowActionKind {
  suggestReorder,
  reviewCashier,
  followUpDebt,
  reviewInventory,
  reviewReports,
  engageCustomer,
  planPurchase,
}

class WorkflowAction {
  const WorkflowAction({
    required this.kind,
    required this.labelAr,
    required this.route,
    this.requiresApproval = true,
  });
  final WorkflowActionKind kind;
  final String labelAr;
  final String route;
  final bool requiresApproval;
}