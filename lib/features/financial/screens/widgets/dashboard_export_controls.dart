import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/dashboard_export.dart';

/// Export menu actions (Phase 5.3.7 placeholders).
///
/// Future phases map each action to PDF, print, or clipboard pipelines.
enum DashboardExportAction {
  exportPdf,
  print,
  copySummary,
}

/// Header export menu for the Financial Dashboard (Phase 5.3.7).
///
/// **Ownership:** opened from [FinancialDashboardScreen] header via
/// [DashboardExportButton].
///
/// **Presentation boundary:** displays placeholder actions only — no PDF
/// generation, no print dialog, no file I/O. The export document is built
/// upstream from already-loaded snapshots.
///
/// **Menu lifecycle:** [openMenu] dismisses on selection or outside tap;
/// [handleAction] runs only when `context.mounted` after async menu close.
class DashboardExportControls {
  DashboardExportControls._();

  static const _kMenuIconSize = 22.0;

  /// Shows the export action popup anchored to [position].
  ///
  /// [document] must be pre-built by the caller — this class does not fetch data.
  static void openMenu({
    required BuildContext context,
    required RelativeRect position,
    required DashboardExportDocument document,
  }) {
    showMenu<DashboardExportAction>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem(
          value: DashboardExportAction.exportPdf,
          child: ListTile(
            leading: Icon(Icons.picture_as_pdf_outlined, size: _kMenuIconSize),
            title: Text('\u062a\u0635\u062f\u064a\u0631 PDF'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: DashboardExportAction.print,
          child: ListTile(
            leading: Icon(Icons.print_outlined, size: _kMenuIconSize),
            title: Text('\u0637\u0628\u0627\u0639\u0629'),
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
    ).then((action) {
      if (action == null || !context.mounted) return;
      handleAction(context: context, action: action, document: document);
    });
  }

  /// Placeholder handlers — SnackBar feedback only (no export side effects).
  static void handleAction({
    required BuildContext context,
    required DashboardExportAction action,
    required DashboardExportDocument document,
  }) {
    final message = switch (action) {
      DashboardExportAction.exportPdf =>
        '\u062a\u0635\u062f\u064a\u0631 PDF \u2014 \u0642\u0631\u064a\u0628\u0627\u064b (${document.sections.length} \u0623\u0642\u0633\u0627\u0645)',
      DashboardExportAction.print =>
        '\u0627\u0644\u0637\u0628\u0627\u0639\u0629 \u2014 \u0642\u0631\u064a\u0628\u0627\u064b (${document.filterSummary})',
      DashboardExportAction.copySummary =>
        '\u0646\u0633\u062e \u0627\u0644\u0645\u0644\u062e\u0635 \u2014 \u0642\u0631\u064a\u0628\u0627\u064b (${document.toPlainTextSummary().length} \u062d\u0631\u0641)',
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

/// Export icon button that opens [DashboardExportControls.openMenu].
///
/// **Callback boundary:** [onPrepareDocument] is invoked on press only — the
/// screen supplies snapshot collection; this widget does not read providers.
class DashboardExportButton extends StatelessWidget {
  const DashboardExportButton({
    super.key,
    required this.onPrepareDocument,
  });

  /// Builds the export snapshot on demand from already-loaded dashboard data.
  final DashboardExportDocument Function() onPrepareDocument;

  static const _kHeaderIconSize = 22.0;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '\u062a\u0635\u062f\u064a\u0631',
      icon: const Icon(Icons.file_download_outlined, size: _kHeaderIconSize),
      color: AppColors.textSecondary,
      onPressed: () {
        final document = onPrepareDocument();
        final box = context.findRenderObject() as RenderBox?;
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox?;
        if (box == null || overlay == null) return;

        final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
        final bottomRight = box.localToGlobal(
          box.size.bottomRight(Offset.zero),
          ancestor: overlay,
        );

        DashboardExportControls.openMenu(
          context: context,
          document: document,
          position: RelativeRect.fromRect(
            Rect.fromPoints(topLeft, bottomRight),
            Offset.zero & overlay.size,
          ),
        );
      },
    );
  }
}