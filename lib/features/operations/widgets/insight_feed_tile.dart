import 'package:flutter/material.dart';

import '../models/operational_insight.dart';
import '../services/operations_navigation.dart';
import 'notification_bell.dart';

class InsightFeedTile extends StatelessWidget {
  const InsightFeedTile({super.key, required this.insight});

  final OperationalInsight insight;

  static const _categoryLabels = {
    'returns': 'مرتجعات',
    'inventory': 'مخزون',
    'cashier': 'كاشير',
    'sales': 'مبيعات',
    'alerts': 'تنبيهات',
  };

  @override
  Widget build(BuildContext context) {
    final color = severityColor(insight.severity);
    final categoryLabel = _categoryLabels[insight.category] ?? insight.category;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(Icons.insights, size: 18, color: color),
      ),
      title: Text(insight.message),
      subtitle: Wrap(
        spacing: 6,
        children: [
          if (categoryLabel != null)
            Chip(
              label: Text(categoryLabel, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          Chip(
            label: Text('P${insight.priorityScore}', style: const TextStyle(fontSize: 11)),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
      trailing: insight.actionRoute != null
          ? IconButton(
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () => OperationsNavigation.navigate(context, insight.actionRoute),
            )
          : null,
    );
  }
}