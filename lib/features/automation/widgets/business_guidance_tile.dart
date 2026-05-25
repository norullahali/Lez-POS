import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../operations/services/operations_navigation.dart';
import '../models/business_guidance_item.dart';

class BusinessGuidanceTile extends StatelessWidget {
  const BusinessGuidanceTile({super.key, required this.item});
  final BusinessGuidanceItem item;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.severity) {
      GuidanceSeverity.positive => AppColors.success,
      GuidanceSeverity.warning => AppColors.warning,
      GuidanceSeverity.info => AppColors.info,
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(Icons.tips_and_updates, color: color, size: 20),
        ),
        title: Text(item.whatHappened),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('لماذا: ${item.whyDetected}'),
            Text('الخطوة التالية: ${item.nextStep}'),
            if (item.audit != null)
              Text(
                'P${item.priorityScore} • ${item.audit!.triggerSource}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textHint),
              ),
          ],
        ),
        trailing: item.actionRoute != null
            ? IconButton(
                icon: const Icon(Icons.arrow_forward, size: 18),
                onPressed: () => OperationsNavigation.navigate(context, item.actionRoute),
              )
            : null,
      ),
    );
  }
}