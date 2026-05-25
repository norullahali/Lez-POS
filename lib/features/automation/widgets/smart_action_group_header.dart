import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../governance/smart_action_grouping_service.dart';
import '../models/smart_action_group.dart';

class SmartActionGroupHeader extends StatelessWidget {
  const SmartActionGroupHeader({super.key, required this.section});
  final SmartActionGroupedSection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            section.group.labelAr,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Chip(
            label: Text('${section.items.length}'),
            visualDensity: VisualDensity.compact,
            backgroundColor: AppColors.primary.withValues(alpha: 0.08),
          ),
        ],
      ),
    );
  }
}