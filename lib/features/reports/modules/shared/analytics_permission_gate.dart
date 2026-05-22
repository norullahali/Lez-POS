import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/report_permissions.dart';
import '../../core/widgets/report_error_view.dart';

class AnalyticsPermissionGate extends ConsumerWidget {
  const AnalyticsPermissionGate({
    super.key,
    required this.requiresFinancial,
    required this.requiresInventory,
    required this.requiresExecutive,
    required this.child,
  });

  final bool requiresFinancial;
  final bool requiresInventory;
  final bool requiresExecutive;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.watch(canViewAnalyticsProvider);
    if (!canView) {
      return const ReportErrorView(message: 'ليس لديك صلاحية عرض التحليلات المتقدمة');
    }
    if (requiresExecutive && !ref.watch(canViewExecutiveAnalyticsProvider)) {
      return const ReportErrorView(message: 'ليس لديك صلاحية عرض لوحة الإدارة التنفيذية');
    }
    if (requiresFinancial && !ref.watch(canViewFinancialAnalyticsProvider)) {
      return const ReportErrorView(message: 'ليس لديك صلاحية عرض التحليلات المالية');
    }
    if (requiresInventory && !ref.watch(canViewInventoryAnalyticsProvider)) {
      return const ReportErrorView(message: 'ليس لديك صلاحية عرض تحليلات المخزون');
    }
    return child;
  }
}