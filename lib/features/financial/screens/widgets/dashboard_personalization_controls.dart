import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/dashboard_personalization.dart';

/// Local presentation controls for Financial Dashboard personalization (Phase 5.3.6).
///
/// **Ownership:** opened from [FinancialDashboardScreen] header tune button.
///
/// **Live apply:** each toggle/density change invokes [onChanged] immediately so
/// the dashboard reflects preferences without waiting for dialog close.
///
/// **Read-only policy:** adjusts layout visibility and spacing only — does not
/// mutate financial data, filters, or provider state.
///
/// **Callback boundary:** [onChanged] updates screen-local [DashboardPersonalization]
/// via [_updatePersonalization] — persistence is handled by the screen (Phase 5.3.9),
/// not by this widget. No providers or repository access.
class DashboardPersonalizationControls extends StatelessWidget {
  const DashboardPersonalizationControls({
    super.key,
    required this.personalization,
    required this.onChanged,
  });

  final DashboardPersonalization personalization;
  final ValueChanged<DashboardPersonalization> onChanged;

  static Future<void> show({
    required BuildContext context,
    required DashboardPersonalization personalization,
    required ValueChanged<DashboardPersonalization> onChanged,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => _DashboardPersonalizationDialog(
        initial: personalization,
        onApply: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('\u062a\u062e\u0635\u064a\u0635 \u0627\u0644\u0648\u062d\u0629'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '\u0627\u0644\u0623\u0642\u0633\u0627\u0645 \u0627\u0644\u0627\u062e\u062a\u064a\u0627\u0631\u064a\u0629',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '\u0627\u0644\u062a\u062d\u0644\u064a\u0644\u0627\u062a \u0627\u0644\u0645\u0627\u0644\u064a\u0629',
              ),
              value: personalization.showAnalyticsCharts,
              onChanged: (value) =>
                  onChanged(personalization.copyWith(showAnalyticsCharts: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('\u0631\u0624\u0649 \u0645\u0627\u0644\u064a\u0629'),
              value: personalization.showInsights,
              onChanged: (value) =>
                  onChanged(personalization.copyWith(showInsights: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('\u062a\u0646\u0628\u064a\u0647\u0627\u062a \u0645\u0627\u0644\u064a\u0629'),
              value: personalization.showAlerts,
              onChanged: (value) =>
                  onChanged(personalization.copyWith(showAlerts: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('\u0622\u062e\u0631 \u0627\u0644\u062d\u0631\u0643\u0627\u062a'),
              value: personalization.showRecentActivity,
              onChanged: (value) =>
                  onChanged(personalization.copyWith(showRecentActivity: value)),
            ),
            const SizedBox(height: 16),
            const Text(
              '\u0643\u062b\u0627\u0641\u0629 \u0627\u0644\u0639\u0631\u0636',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<DashboardDisplayDensity>(
              segments: const [
                ButtonSegment(
                  value: DashboardDisplayDensity.comfortable,
                  label: Text('\u0645\u0631\u064a\u062d'),
                ),
                ButtonSegment(
                  value: DashboardDisplayDensity.compact,
                  label: Text('\u0645\u0636\u063a\u0648\u0637'),
                ),
              ],
              selected: {personalization.displayDensity},
              onSelectionChanged: (selection) => onChanged(
                personalization.copyWith(displayDensity: selection.first),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('\u0625\u063a\u0644\u0627\u0642'),
        ),
      ],
    );
  }
}

/// Dialog shell that mirrors live preference changes to the dashboard (Phase 5.3.6).
class _DashboardPersonalizationDialog extends StatefulWidget {
  const _DashboardPersonalizationDialog({
    required this.initial,
    required this.onApply,
  });

  final DashboardPersonalization initial;
  final ValueChanged<DashboardPersonalization> onApply;

  @override
  State<_DashboardPersonalizationDialog> createState() =>
      _DashboardPersonalizationDialogState();
}

class _DashboardPersonalizationDialogState
    extends State<_DashboardPersonalizationDialog> {
  late DashboardPersonalization _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  void _update(DashboardPersonalization next) {
    setState(() => _draft = next);
    widget.onApply(next);
  }

  @override
  Widget build(BuildContext context) {
    return DashboardPersonalizationControls(
      personalization: _draft,
      onChanged: _update,
    );
  }
}