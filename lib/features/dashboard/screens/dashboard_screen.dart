// lib/features/dashboard/screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/stat_card.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../../reports/providers/reports_provider.dart';
import '../../backup/providers/backup_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Trigger auto-backup check on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(backupSettingsProvider.notifier).checkAndPerformAutoBackup();
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dailyAsync = ref.watch(reportDailySalesProvider(today));
    final topProductsAsync = ref.watch(reportTopProductsProvider(DateTimeRange(
      start: DateTime(today.year, today.month, today.day),
      end: today,
    )));
    final lowStockAsync = ref.watch(lowStockProvider);
    final expiringAsync = ref.watch(expiringProductsProvider);
    final nfInt = NumberFormat('#,##0');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards
          dailyAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => const SizedBox.shrink(),
            data: (data) {
              final total = (data['total'] as num?)?.toDouble() ?? 0;
              final count = (data['count'] as num?)?.toInt() ?? 0;
              final profit = (data['profit'] as num?)?.toDouble() ?? 0;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 2.0,
                children: [
                  StatCard(
                    title: 'مبيعات اليوم',
                    value: '${nfInt.format(total)} د.ع',
                    icon: Icons.point_of_sale_rounded,
                    color: AppColors.primary,
                    onTap: () => context.go('/reports'),
                  ),
                  StatCard(
                    title: 'عدد الفواتير',
                    value: '$count فاتورة',
                    icon: Icons.receipt_long_rounded,
                    color: AppColors.info,
                    onTap: () => context.go('/reports'),
                  ),
                  StatCard(
                    title: 'ربح اليوم',
                    value: '${nfInt.format(profit)} د.ع',
                    icon: Icons.trending_up_rounded,
                    color: AppColors.success,
                  ),
                  StatCard(
                    title: 'ابدأ البيع',
                    value: 'اضغط للدخول',
                    icon: Icons.point_of_sale_outlined,
                    color: AppColors.accent,
                    onTap: () => context.go('/pos'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          // Alerts row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Low stock alert
              Expanded(
                child: lowStockAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (items) => items.isEmpty
                      ? const SizedBox.shrink()
                      : _AlertCard(
                          title: 'تنبيه: مخزون منخفض (${items.length})',
                          icon: Icons.warning_rounded,
                          color: AppColors.warning,
                          onTap: () => context.go('/inventory'),
                          children: items.take(5).map((item) => _AlertItem(
                            name: item['name'] as String? ?? '',
                            detail: 'المتبقي: ${(item['current_stock'] as num?)?.toStringAsFixed(1) ?? '0'}',
                          )).toList(),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              // Expiring soon alert
              Expanded(
                child: expiringAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (items) => items.isEmpty
                      ? const SizedBox.shrink()
                      : _AlertCard(
                          title: 'منتجات تقترب صلاحيتها (${items.length})',
                          icon: Icons.schedule_rounded,
                          color: AppColors.error,
                          onTap: () => context.go('/inventory'),
                          children: items.take(5).map((item) {
                            final expiry = item['expiry_date'] as DateTime?;
                            final days = expiry?.difference(DateTime.now()).inDays ?? 0;
                            return _AlertItem(
                              name: item['product_name'] as String? ?? '',
                              detail: days < 0 ? 'منتهي الصلاحية' : 'خلال $days يوم',
                            );
                          }).toList(),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Top products today
          topProductsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (products) => products.isEmpty
                ? Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Icon(Icons.bar_chart_rounded, size: 48, color: AppColors.textHint),
                          const SizedBox(height: 12),
                          const Text('لا توجد مبيعات اليوم بعد', style: TextStyle(color: AppColors.textHint)),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.point_of_sale_rounded),
                            label: const Text('افتح شاشة البيع'),
                            onPressed: () => context.go('/pos'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(children: [
                            const Icon(Icons.star_rounded, color: AppColors.accent),
                            const SizedBox(width: 8),
                            Text('أكثر المنتجات مبيعاً اليوم', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          ]),
                        ),
                        const Divider(height: 1),
                        ...products.take(10).toList().asMap().entries.map((e) {
                          final i = e.key;
                          final p = e.value;
                          final revenue = (p['total_revenue'] as num?)?.toDouble() ?? 0;
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: i < 3 ? AppColors.accent : AppColors.primary.withValues(alpha: 0.1),
                              child: Text('${i + 1}', style: TextStyle(color: i < 3 ? Colors.white : AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                            title: Text(p['name'] as String? ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${nfInt.format(p['total_qty'] ?? 0)} وحدة مباعة'),
                            trailing: Text('${nfInt.format(revenue)} د.ع', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                          );
                        }),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final List<Widget> children;

  const _AlertCard({required this.title, required this.icon, required this.color, required this.onTap, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700))),
                Icon(Icons.arrow_forward_ios_rounded, color: color.withValues(alpha: 0.5), size: 14),
              ]),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertItem extends StatelessWidget {
  final String name;
  final String detail;

  const _AlertItem({required this.name, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13), overflow: TextOverflow.ellipsis)),
          Text(detail, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
