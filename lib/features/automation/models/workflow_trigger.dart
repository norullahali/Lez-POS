enum WorkflowTriggerType {
  criticalStock,
  highVelocity,
  excessiveRefunds,
  overdueDebt,
  inactiveCustomer,
  deadStock,
  weakSales,
}

class WorkflowTrigger {
  const WorkflowTrigger({required this.type, required this.description, this.entityId, this.entityType});
  final WorkflowTriggerType type;
  final String description;
  final int? entityId;
  final String? entityType;
}