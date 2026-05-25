import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/automation_audit_context.dart';
import '../models/business_guidance_item.dart';
import '../models/reorder_suggestion.dart';
import '../models/smart_action_group.dart';
import '../models/smart_action_item.dart';
import '../models/workflow_lifecycle_state.dart';

class OperationalSeverityStyle {
  const OperationalSeverityStyle({
    required this.color,
    required this.background,
    required this.label,
    required this.icon,
  });

  final Color color;
  final Color background;
  final String label;
  final IconData icon;
}

class AutomationUiHelpers {
  AutomationUiHelpers._();

  static OperationalSeverityStyle severityStyle(SmartActionSeverity severity) =>
      switch (severity) {
        SmartActionSeverity.critical => const OperationalSeverityStyle(
            color: AppColors.error,
            background: AppColors.errorLight,
            label: 'حرج',
            icon: Icons.priority_high_rounded,
          ),
        SmartActionSeverity.warning => const OperationalSeverityStyle(
            color: AppColors.warning,
            background: AppColors.warningLight,
            label: 'مرتفع',
            icon: Icons.warning_amber_rounded,
          ),
        SmartActionSeverity.info => const OperationalSeverityStyle(
            color: AppColors.info,
            background: AppColors.infoLight,
            label: 'معلومة',
            icon: Icons.info_outline_rounded,
          ),
      };

  static OperationalSeverityStyle guidanceStyle(GuidanceSeverity severity) =>
      switch (severity) {
        GuidanceSeverity.warning => severityStyle(SmartActionSeverity.warning),
        GuidanceSeverity.positive => const OperationalSeverityStyle(
            color: AppColors.success,
            background: AppColors.successLight,
            label: 'إيجابي',
            icon: Icons.trending_up_rounded,
          ),
        GuidanceSeverity.info => severityStyle(SmartActionSeverity.info),
      };

  static OperationalSeverityStyle reorderUrgencyStyle(ReorderUrgency urgency) =>
      switch (urgency) {
        ReorderUrgency.critical => severityStyle(SmartActionSeverity.critical),
        ReorderUrgency.urgent => severityStyle(SmartActionSeverity.warning),
        ReorderUrgency.warning => const OperationalSeverityStyle(
            color: AppColors.warning,
            background: AppColors.warningLight,
            label: 'متوسط',
            icon: Icons.schedule_rounded,
          ),
        ReorderUrgency.safe => severityStyle(SmartActionSeverity.info),
      };

  static String categoryLabel(SmartActionCategory category) => switch (category) {
        SmartActionCategory.reorder => 'إعادة طلب',
        SmartActionCategory.purchase => 'شراء',
        SmartActionCategory.restock => 'تخزين',
        SmartActionCategory.debt => 'ذمم',
        SmartActionCategory.loyalty => 'ولاء',
        SmartActionCategory.cashier => 'كاشير',
        SmartActionCategory.sales => 'مبيعات',
        SmartActionCategory.workflow => 'سير عمل',
      };

  static IconData groupIcon(SmartActionGroup group) => switch (group) {
        SmartActionGroup.inventory => Icons.inventory_2_outlined,
        SmartActionGroup.finance => Icons.account_balance_wallet_outlined,
        SmartActionGroup.operations => Icons.settings_suggest_outlined,
        SmartActionGroup.cashier => Icons.point_of_sale_outlined,
        SmartActionGroup.loyalty => Icons.loyalty_outlined,
        SmartActionGroup.alerts => Icons.notifications_active_outlined,
      };

  static String confidenceShort(HeuristicConfidence confidence) => switch (confidence) {
        HeuristicConfidence.high => 'ثقة عالية',
        HeuristicConfidence.medium => 'ثقة متوسطة',
        HeuristicConfidence.low => 'ثقة منخفضة',
      };

  static String lifecycleShort(WorkflowLifecycleState state) => switch (state) {
        WorkflowLifecycleState.pending => 'معلق',
        WorkflowLifecycleState.reviewed => 'تمت المراجعة',
        WorkflowLifecycleState.accepted => 'مقبول',
        WorkflowLifecycleState.ignored => 'متجاهل',
        WorkflowLifecycleState.expired => 'منتهي',
        WorkflowLifecycleState.completed => 'مكتمل',
      };

  static String relativeTimeAr(DateTime? time) {
    if (time == null) return '-';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return 'منذ ${diff.inMinutes} د';
    if (diff.inDays < 1) return 'منذ ${diff.inHours} س';
    if (diff.inDays < 30) return 'منذ ${diff.inDays} ي';
    return 'منذ ${(diff.inDays / 30).floor()} ش';
  }

  static bool isFresh(DateTime? time) {
    if (time == null) return false;
    return DateTime.now().difference(time).inHours < 6;
  }

  static List<({String label, String value})> metricsForAction(SmartActionItem action) {
    final metrics = action.audit?.sourceMetrics ?? {};
    final rows = <({String label, String value})>[];

    void add(String key, String label, {String Function(num v)? fmt}) {
      final raw = metrics[key];
      if (raw is! num) return;
      rows.add((label: label, value: fmt != null ? fmt(raw) : raw.toStringAsFixed(0)));
    }

    add('balance', 'الرصيد', fmt: (v) => v.toStringAsFixed(0));
    add('count', 'العدد');
    add('thisWeek', 'مبيعات الأسبوع', fmt: (v) => v.toStringAsFixed(0));
    add('todayReturns', 'مرتجعات اليوم', fmt: (v) => v.toStringAsFixed(0));
    add('financialImpact', 'التأثير', fmt: (v) => v.toStringAsFixed(0));
    rows.add((label: 'الأولوية', value: 'P${action.priorityScore}'));
    if (action.expiresAt != null) {
      rows.add((label: 'الصلاحية', value: relativeTimeAr(action.expiresAt)));
    }
    return rows.take(4).toList();
  }
}