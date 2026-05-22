import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class ReportSkeletonBox extends StatelessWidget {
  const ReportSkeletonBox({super.key, this.height = 16, this.width, this.borderRadius = 8});

  final double height;
  final double? width;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class ReportMetricSkeletonGrid extends StatelessWidget {
  const ReportMetricSkeletonGrid({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 2.2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(count, (_) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const ReportSkeletonBox(height: 52, width: 52, borderRadius: 14),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      ReportSkeletonBox(height: 12, width: 120),
                      SizedBox(height: 8),
                      ReportSkeletonBox(height: 22, width: 180),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class ReportChartSkeleton extends StatelessWidget {
  const ReportChartSkeleton({super.key, this.height = 280});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ReportSkeletonBox(height: 18, width: 180),
              const SizedBox(height: 24),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(
                    8,
                    (i) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                        child: ReportSkeletonBox(height: 40.0 + (i % 4) * 28),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReportTableSkeleton extends StatelessWidget {
  const ReportTableSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: List.generate(rows, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  ReportSkeletonBox(height: 14, width: 28 + (i * 3).toDouble()),
                  const Spacer(),
                  const ReportSkeletonBox(height: 14, width: 90),
                  const SizedBox(width: 24),
                  const ReportSkeletonBox(height: 14, width: 110),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}