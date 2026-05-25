enum DebtPartyType { customer, supplier }
enum DebtRiskLevel { low, medium, high, critical }

class DebtFollowUpItem {
  const DebtFollowUpItem({
    required this.partyId,
    required this.partyName,
    required this.partyType,
    required this.balance,
    required this.riskLevel,
    required this.priorityScore,
    required this.suggestedFollowUpAr,
    required this.explanation,
    this.actionRoute,
  });
  final int partyId;
  final String partyName;
  final DebtPartyType partyType;
  final double balance;
  final DebtRiskLevel riskLevel;
  final int priorityScore;
  final String suggestedFollowUpAr;
  final String explanation;
  final String? actionRoute;
}