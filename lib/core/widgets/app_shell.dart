// lib/core/widgets/app_shell.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'side_nav.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  final String currentRoute;
  final String? title;

  const AppShell({super.key, required this.child, required this.currentRoute, this.title});

  @override
  Widget build(BuildContext context) {
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
      '/users': 'إدارة المستخدمين',
      '/roles': 'الأدوار والصلاحيات',
      '/backup': 'النسخ الاحتياطي',
    };
    return titles[route] ?? 'ليز POS';
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return Container(
      height: 56,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
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
          Text(
            'ليز POS',
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
