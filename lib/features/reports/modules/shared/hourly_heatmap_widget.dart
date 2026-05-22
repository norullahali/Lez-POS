import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import 'advanced_analytics_models.dart';

/// Hourly sales heatmap with intensity scaling and peak/lowlight markers.
/// Designed to extend safely to weekday heatmaps in the future.
class HourlyHeatmapWidget extends StatelessWidget {
  const HourlyHeatmapWidget({super.key, required this.points, required this.nfInt});

  final List<HourlySalesPoint> points;
  final NumberFormat nfInt;

  @override
  Widget build(BuildContext context) {
    final maxSales = points.fold<double>(0, (m, p) => p.salesAmount > m ? p.salesAmount : m);
    final active = points.where((p) => p.salesAmount > 0 || p.invoiceCount > 0).toList();
    HourlySalesPoint? best;
    HourlySalesPoint? weakest;
    if (active.isNotEmpty) {
      best = active.reduce((a, b) => a.salesAmount >= b.salesAmount ? a : b);
      weakest = active.reduce((a, b) => a.salesAmount <= b.salesAmount ? a : b);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('خريطة المبيعات بالساعة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            if (best != null)
              _HourChip(label: 'الأكثر نشاطاً: ${_formatHour(best.hour)}', color: AppColors.success),
            if (weakest != null) ...[
              const SizedBox(width: 8),
              _HourChip(label: 'الأقل نشاطاً: ${_formatHour(weakest.hour)}', color: AppColors.warning),
            ],
          ],
        ),
        const SizedBox(height: 8),
        _IntensityLegend(maxLabel: maxSales > 0 ? nfInt.format(maxSales) : '0'),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth > 900 ? 8 : (c.maxWidth > 600 ? 6 : 4);
              return GridView.builder(
                key: const PageStorageKey('hourly_heatmap_grid'),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.35,
                ),
                itemCount: 24,
                itemBuilder: (context, index) {
                  final point = points[index];
                  final intensity = maxSales > 0 ? (point.salesAmount / maxSales).clamp(0.0, 1.0) : 0.0;
                  final color = Color.lerp(AppColors.border, AppColors.primary, intensity)!;
                  final isBest = best?.hour == point.hour;
                  final isWeakest = weakest?.hour == point.hour && active.length > 1;
                  return Tooltip(
                    message:
                        '${_formatHour(point.hour)}\n${nfInt.format(point.salesAmount)} د.ع\n${point.invoiceCount} فاتورة',
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isBest
                              ? AppColors.success
                              : isWeakest
                                  ? AppColors.warning
                                  : AppColors.border,
                          width: isBest || isWeakest ? 2 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_formatHour(point.hour),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                          Text('${point.invoiceCount}',
                              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                          if (point.salesAmount > 0)
                            Text(nfInt.format(point.salesAmount),
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatHour(int hour) {
    final h = hour % 24;
    final suffix = h < 12 ? 'ص' : 'م';
    final display = h % 12 == 0 ? 12 : h % 12;
    return '$display $suffix';
  }
}

class _HourChip extends StatelessWidget {
  const _HourChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _IntensityLegend extends StatelessWidget {
  const _IntensityLegend({required this.maxLabel});
  final String maxLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('الكثافة:', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(colors: [AppColors.border, AppColors.primary]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('حتى $maxLabel د.ع', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}
