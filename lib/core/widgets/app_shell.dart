// lib/core/widgets/app_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/activity/providers/activity_context_provider.dart';
import '../../features/operations/providers/operations_providers.dart';
import '../../features/automation/providers/automation_providers.dart';
import '../../features/operations/widgets/notification_bell.dart';
import '../theme/app_colors.dart';
import 'side_nav.dart';
import 'package:go_router/go_router.dart';

class AppShell extends ConsumerWidget {
  final Widget child;
  final String currentRoute;
  final String? title;

  const AppShell(
      {super.key, required this.child, required this.currentRoute, this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(activityContextSyncProvider);
    ref.watch(operationsStartupProvider);
    ref.watch(automationStartupProvider);
    debugPrint('CURRENT ROUTE: $currentRoute');
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          SideNav(currentRoute: currentRoute),
          Expanded(
            child: Column(
              children: [
                _TopBar(currentRoute: currentRoute, title: title),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String currentRoute;
  final String? title;
  const _TopBar({required this.currentRoute, this.title});

  String _getTitle(String route) {
    if (route.startsWith('/customers/profile')) return 'ملف العميل';
    if (route.startsWith('/backup/settings')) return 'إعدادات النسخ التلقائي';
    if (route.startsWith('/purchases/new')) return 'فاتورة شراء جديدة';
    if (route.startsWith('/purchases/edit')) return 'تعديل فاتورة شراء';

    const titles = {
      '/dashboard': 'لوحة التحكم',
      '/pos': 'نقطة البيع',
      '/products': 'المنتجات',
      '/categories': 'الفئات',
      '/customers': 'إدارة العملاء',
      '/suppliers': 'الموردون',
      '/purchases': 'المشتريات',
      '/opening-stock': 'الرصيد الافتتاحي',
      '/inventory': 'المخزن',
      '/returns': 'المرتجعات',
      '/pricing': 'العروض والأسعار',
      '/reports': 'التقارير',
      '/financial': 'الماليات — دفتر النقدية',
      '/expenses': 'إدارة المصروفات',
      '/invoice-history': 'سجل الفواتير',
      '/users': 'إدارة المستخدمين',
      '/roles': 'الأدوار والصلاحيات',
      '/backup': 'النسخ الاحتياطي',
      '/activity': 'سجل النشاط',
      '/activity/timeline': 'الجدول الزمني',
      '/operations/notifications': 'مركز الإشعارات',
      '/automation/actions': 'مركز الإجراءات',
    };
    return titles[route] ?? 'Lez POS';
  }

  @override
  Widget build(BuildContext context) {
    // 🧠 نحدد هل نظهر زر الرجوع أم لا
    final showBack = currentRoute.startsWith('/suppliers/') ||
        currentRoute.startsWith('/customers/') ||
        currentRoute.startsWith('/purchases/');

    return Container(
      height: 56,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.textPrimary),

              // 🚀 الرجوع الصحيح (بدون pop نهائياً)
              onPressed: () {
                if (currentRoute == '/pos') {
                  context.go('/dashboard'); // مهم جداً
                } else if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/dashboard');
                }
              },
            ),
          const SizedBox(width: 8),
          Text(
            title ?? _getTitle(currentRoute),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
          ),
          const Spacer(),
          const NotificationBell(),
          const SizedBox(width: 8),
          Text(
            'Lez POS',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textHint,
                ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
