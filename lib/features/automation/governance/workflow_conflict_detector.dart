import '../models/smart_action_group.dart';
import '../models/smart_action_item.dart';
import '../models/workflow_conflict.dart';

class WorkflowConflictDetector {
  WorkflowConflictDetector._();

  static List<WorkflowConflict> detect(List<SmartActionItem> actions) {
    final conflicts = <WorkflowConflict>[];
    final byEntity = <String, List<SmartActionItem>>{};
    for (final a in actions) {
      if (a.entityType == null || a.entityId == null) continue;
      final key = '${a.entityType}:${a.entityId}';
      byEntity.putIfAbsent(key, () => []).add(a);
    }

    for (final entry in byEntity.entries) {
      final items = entry.value;
      final reorder = items.where((i) => i.category == SmartActionCategory.reorder).toList();
      final restockDead = items.where((i) => i.category == SmartActionCategory.restock && i.reason.contains('30')).toList();
      if (reorder.isNotEmpty && restockDead.isNotEmpty) {
        conflicts.add(WorkflowConflict(
          id: 'conflict_reorder_dead_${entry.key}',
          titleAr: 'تعارض مخزني',
          descriptionAr: 'يوجد توصية إعادة طلب وتحذير راكد لنفس المنتج',
          resolutionHintAr: 'راجع velocity الفعلي قبل الشراء',
          severity: WorkflowConflictSeverity.warning,
          fingerprintA: reorder.first.fingerprint ?? reorder.first.id,
          fingerprintB: restockDead.first.fingerprint ?? restockDead.first.id,
        ));
      }
    }

    final aggressiveRestock = actions.where((a) => a.group == SmartActionGroup.inventory && a.priorityScore >= 85).length;
    final weakSales = actions.where((a) => a.category == SmartActionCategory.sales).length;
    if (aggressiveRestock >= 2 && weakSales > 0) {
      final restock = actions.firstWhere((a) => a.group == SmartActionGroup.inventory && a.priorityScore >= 85);
      final sales = actions.firstWhere((a) => a.category == SmartActionCategory.sales);
      conflicts.add(WorkflowConflict(
        id: 'conflict_restock_sales',
        titleAr: 'تعارض تشغيلي',
        descriptionAr: 'إعادة تخزين عدوانية مقابل ضعف مبيعات',
        resolutionHintAr: 'قلل كميات الشراء وركز على المنتجات الأسرع حركة',
        severity: WorkflowConflictSeverity.critical,
        fingerprintA: restock.fingerprint ?? restock.id,
        fingerprintB: sales.fingerprint ?? sales.id,
      ));
    }

    return conflicts;
  }

  static List<WorkflowConflict> forAction(String fingerprint, List<WorkflowConflict> all) =>
      all.where((c) => c.fingerprintA == fingerprint || c.fingerprintB == fingerprint).toList();
}