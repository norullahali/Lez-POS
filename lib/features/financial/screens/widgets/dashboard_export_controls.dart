import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../reports/core/providers/report_permissions.dart';
import '../../models/dashboard_export.dart';
import '../../widgets/dashboard_export_helper.dart';

/// Export menu actions for the Financial Dashboard (B42 Stage 1).
enum DashboardExportAction {
  exportCsv,
  copySummary,
}

/// Header export menu for the Financial Dashboard.
class DashboardExportControls {
  DashboardExportControls._();

  static const _kMenuIconSize = 22.0;

  static void openMenu({
    required BuildContext context,
    required WidgetRef ref,
    required RelativeRect position,
    required DashboardExportDocument document,
  }) {
    showMenu<DashboardExportAction>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem(
          value: DashboardExportAction.exportCsv,
          child: ListTile(
            leading: Icon(Icons.table_chart_outlined, size: _kMenuIconSize),
            title: Text('\u062a\u0635\u062f\u064a\u0631 CSV'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: DashboardExportAction.copySummary,
          child: ListTile(
            leading: Icon(Icons.content_copy_outlined, size: _kMenuIconSize),
            title: Text('\u0646\u0633\u062e \u0627\u0644\u0645\u0644\u062e\u0635'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
    ).then((action) async {
      if (action == null || !context.mounted) return;
      await handleAction(
        context: context,
        ref: ref,
        action: action,
        document: document,
      );
    });
  }

  static Future<void> handleAction({
    required BuildContext context,
    required WidgetRef ref,
    required DashboardExportAction action,
    required DashboardExportDocument document,
  }) async {
    switch (action) {
      case DashboardExportAction.exportCsv:
        await DashboardExportHelper.exportCsv(
          context: context,
          ref: ref,
          document: document,
        );
      case DashboardExportAction.copySummary:
        await DashboardExportHelper.copySummary(
          context: context,
          ref: ref,
          document: document,
        );
    }
  }
}

/// Export icon button that opens [DashboardExportControls.openMenu].
class DashboardExportButton extends ConsumerWidget {
  const DashboardExportButton({
    super.key,
    required this.onPrepareDocument,
  });

  final DashboardExportDocument Function() onPrepareDocument;

  static const _kHeaderIconSize = 22.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canExport = ref.watch(canExportReportsProvider);

    return IconButton(
      tooltip: canExport ? '\u062a\u0635\u062f\u064a\u0631' : '\u062a\u0635\u062f\u064a\u0631 (\u063a\u064a\u0631 \u0645\u0635\u0631\u062d)',
      icon: const Icon(Icons.file_download_outlined, size: _kHeaderIconSize),
      color: AppColors.textSecondary,
      onPressed: canExport
          ? () {
              final document = onPrepareDocument();
              final box = context.findRenderObject() as RenderBox?;
              final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
              if (box == null || overlay == null) return;

              final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
              final bottomRight = box.localToGlobal(
                box.size.bottomRight(Offset.zero),
                ancestor: overlay,
              );

              DashboardExportControls.openMenu(
                context: context,
                ref: ref,
                document: document,
                position: RelativeRect.fromRect(
                  Rect.fromPoints(topLeft, bottomRight),
                  Offset.zero & overlay.size,
                ),
              );
            }
          : null,
    );
  }
}
