import '../cache/automation_cache.dart';
import '../models/debt_follow_up_item.dart';
import '../repositories/automation_repository.dart';
import '../rules/operations_rules.dart';

class DebtFollowUpService {
  DebtFollowUpService(this._repo);
  final AutomationRepository _repo;

  Future<List<DebtFollowUpItem>> generate() async {
    return AutomationCache.memo('debt_follow_up', () async {
      final customers = await _repo.fetchCustomerDebts(minBalance: OperationsRules.overdueDebtBalance);
      final suppliers = await _repo.fetchSupplierDebts(minBalance: OperationsRules.overdueDebtBalance);
      final items = <DebtFollowUpItem>[];
      for (final row in customers) {
        final balance = (row['balance'] as num).toDouble();
        final id = row['id'] as int;
        final risk = _risk(balance);
        items.add(DebtFollowUpItem(
          partyId: id,
          partyName: row['name'] as String? ?? 'عميل',
          partyType: DebtPartyType.customer,
          balance: balance,
          riskLevel: risk,
          priorityScore: _score(risk, balance),
          suggestedFollowUpAr: risk == DebtRiskLevel.critical ? 'متابعة عاجلة' : 'تذكير بالسداد',
          explanation: 'رصيد ${balance.toStringAsFixed(0)} ≥ ${OperationsRules.overdueDebtBalance.toInt()}',
          actionRoute: '/customers/profile/$id',
        ));
      }
      for (final row in suppliers.take(10)) {
        final balance = (row['balance'] as num).toDouble();
        items.add(DebtFollowUpItem(
          partyId: row['id'] as int,
          partyName: row['name'] as String? ?? 'مورد',
          partyType: DebtPartyType.supplier,
          balance: balance,
          riskLevel: _risk(balance),
          priorityScore: _score(_risk(balance), balance) - 10,
          suggestedFollowUpAr: 'مراجعة مستحقات المورد',
          explanation: 'ذمة مورد ${balance.toStringAsFixed(0)}',
          actionRoute: '/suppliers/profile/${row['id']}',
        ));
      }
      items.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
      return items;
    });
  }

  DebtRiskLevel _risk(double balance) {
    if (balance >= OperationsRules.overdueDebtCritical) return DebtRiskLevel.critical;
    if (balance >= 200) return DebtRiskLevel.high;
    if (balance >= 100) return DebtRiskLevel.medium;
    return DebtRiskLevel.low;
  }

  int _score(DebtRiskLevel risk, double balance) => switch (risk) {
        DebtRiskLevel.critical => 90,
        DebtRiskLevel.high => 75,
        DebtRiskLevel.medium => 55,
        DebtRiskLevel.low => 35,
      } + (balance / 100).clamp(0, 20).toInt();
}