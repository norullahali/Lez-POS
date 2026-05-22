import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/report_permissions.dart';
import '../models/report_date_preset.dart';
import '../models/report_filter_model.dart';

enum ReportFilterBarMode { singleDate, dateRange, yearOnly }

class ReportFilterBar extends ConsumerWidget {
  const ReportFilterBar({
    super.key,
    required this.filter,
    required this.onFilterChanged,
    this.mode = ReportFilterBarMode.dateRange,
    this.onRefresh,
    this.onExport,
    this.showExport = true,
    this.presets,
  });

  final ReportFilterModel filter;
  final ValueChanged<ReportFilterModel> onFilterChanged;
  final ReportFilterBarMode mode;
  final VoidCallback? onRefresh;
  final VoidCallback? onExport;
  final bool showExport;
  final List<ReportDatePreset>? presets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canExport = ref.watch(canExportReportsProvider);
    final presetList = presets ?? ReportDatePresetX.rangePresets;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (mode != ReportFilterBarMode.yearOnly)
            ...presetList.map((p) => _PresetChip(
                  label: p.labelAr,
                  selected: filter.preset == p,
                  onTap: () => onFilterChanged(filter.copyWith(preset: p, clearRange: p != ReportDatePreset.custom)),
                )),
          if (mode == ReportFilterBarMode.singleDate) _buildSingleDatePicker(context),
          if (mode == ReportFilterBarMode.dateRange) _buildRangePicker(context),
          if (mode == ReportFilterBarMode.yearOnly) _buildYearPicker(context),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              filter.summaryAr(),
              style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (onRefresh != null)
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: onRefresh,
            ),
          if (showExport)
            OutlinedButton.icon(
              onPressed: canExport ? onExport : null,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(canExport ? 'تصدير' : 'تصدير (غير مصرح)'),
            ),
        ],
      ),
    );
  }

  Widget _buildSingleDatePicker(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today_rounded, size: 18),
      label: Text(_fmt(filter.resolveSingleDate())),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: filter.resolveSingleDate(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          onFilterChanged(filter.copyWith(singleDate: picked, preset: ReportDatePreset.custom));
        }
      },
    );
  }

  Widget _buildRangePicker(BuildContext context) {
    if (filter.preset != ReportDatePreset.custom) return const SizedBox.shrink();
    return OutlinedButton.icon(
      icon: const Icon(Icons.date_range_rounded, size: 18),
      label: const Text('اختر الفترة'),
      onPressed: () async {
        final current = filter.resolveRange();
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          initialDateRange: current,
        );
        if (picked != null) {
          onFilterChanged(filter.copyWith(preset: ReportDatePreset.custom, range: picked));
        }
      },
    );
  }

  Widget _buildYearPicker(BuildContext context) {
    final year = filter.resolveYear();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => onFilterChanged(filter.copyWith(year: year - 1)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('سنة $year', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: year >= DateTime.now().year ? null : () => onFilterChanged(filter.copyWith(year: year + 1)),
        ),
      ],
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      checkmarkColor: AppColors.primary,
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 13,
      ),
    );
  }
}