import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/permissions/permission_keys.dart';
import '../../../auth/providers/permission_provider.dart';
import '../models/report_drill_down.dart';
import '../providers/report_permissions.dart';
import 'report_drill_down_service.dart';

/// Consistent drill-down row handlers for report tables.
class ReportDrillDownActions {
  ReportDrillDownActions._();

  static const MouseCursor drillCursor = SystemMouseCursors.click;

  static ValueChanged<bool?>? rowHandler(
    BuildContext context,
    WidgetRef ref, {
    required ReportDrillDownTarget? target,
  }) {
    if (target == null) return null;
    if (!_canNavigate(ref, target.type)) {
      return (_) => _unauthorized(context);
    }
    return (_) => ReportDrillDownService.open(context, ref, target);
  }

  static DataRow interactiveRow({
    required List<DataCell> cells,
    ValueChanged<bool?>? onSelectChanged,
  }) {
    return DataRow(
      onSelectChanged: onSelectChanged,
      color: onSelectChanged != null
          ? WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return AppColors.primary.withValues(alpha: 0.05);
              }
              if (states.contains(WidgetState.selected)) {
                return AppColors.primary.withValues(alpha: 0.08);
              }
              return null;
            })
          : null,
      cells: cells,
    );
  }

  static bool _canNavigate(WidgetRef ref, ReportDrillDownEntityType type) {
    if (!ref.read(canViewReportsProvider)) return false;
    return switch (type) {
      ReportDrillDownEntityType.product => ref.read(canViewProductsForReportsProvider),
      ReportDrillDownEntityType.supplier => ref.read(canViewPurchasesForReportsProvider),
      ReportDrillDownEntityType.customer ||
      ReportDrillDownEntityType.invoice ||
      ReportDrillDownEntityType.invoiceHistory =>
        ref.read(canViewReportsProvider),
      ReportDrillDownEntityType.user =>
        ref.read(permissionProvider(PermissionKeys.auditView)),
    };
  }

  static void _unauthorized(BuildContext context) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('ليس لديك صلاحية للانتقال إلى هذا السجل'),
        backgroundColor: AppColors.warning,
      ),
    );
  }
}