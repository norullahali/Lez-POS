import '../models/smart_action_group.dart';
import '../models/smart_action_item.dart';

class SmartActionGroupedSection {
  const SmartActionGroupedSection({
    required this.group,
    required this.items,
  });

  final SmartActionGroup group;
  final List<SmartActionItem> items;

  SmartActionGroupedSection copyWith({List<SmartActionItem>? items}) {
    return SmartActionGroupedSection(group: group, items: items ?? this.items);
  }
}

class SmartActionGroupingService {
  SmartActionGroupingService._();

  static List<SmartActionGroupedSection> group(List<SmartActionItem> actions) {
    final buckets = <SmartActionGroup, List<SmartActionItem>>{};
    for (final action in actions) {
      final group = action.group ?? SmartActionGroupX.fromCategory(action.category);
      final resolved = action.group == null
          ? SmartActionItem(
              id: action.id,
              title: action.title,
              reason: action.reason,
              recommendation: action.recommendation,
              severity: action.severity,
              category: action.category,
              priorityScore: action.priorityScore,
              actionRoute: action.actionRoute,
              actionLabel: action.actionLabel,
              entityType: action.entityType,
              entityId: action.entityId,
              requiresApproval: action.requiresApproval,
              fingerprint: action.fingerprint,
              lifecycleState: action.lifecycleState,
              audit: action.audit,
              group: group,
              conflicts: action.conflicts,
              expiresAt: action.expiresAt,
              occurrenceCount: action.occurrenceCount,
              lastRefreshedAt: action.lastRefreshedAt,
            )
          : action;
      buckets.putIfAbsent(group, () => []).add(resolved);
    }

    const order = [
      SmartActionGroup.inventory,
      SmartActionGroup.finance,
      SmartActionGroup.operations,
      SmartActionGroup.cashier,
      SmartActionGroup.loyalty,
      SmartActionGroup.alerts,
    ];

    return order
        .where(buckets.containsKey)
        .map((g) => SmartActionGroupedSection(
              group: g,
              items: List<SmartActionItem>.from(buckets[g]!)..sort(SmartActionItem.compare),
            ))
        .toList();
  }
}