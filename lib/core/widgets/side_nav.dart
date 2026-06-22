// lib/core/widgets/side_nav.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../../features/auth/permissions/permission_keys.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/providers/permission_provider.dart';

class NavItem {
  final String route;
  final IconData icon;
  final String label;
  final bool isPrimary;

  const NavItem({
    required this.route,
    required this.icon,
    required this.label,
    this.isPrimary = false,
    this.permissionKey,
  });
  final String? permissionKey;
}

const kNavItems = [
  NavItem(
      route: '/dashboard', icon: Icons.dashboard_rounded, label: 'الرئيسية'),
  NavItem(
      route: '/pos',
      icon: Icons.point_of_sale_rounded,
      label: 'نقطة البيع',
      isPrimary: true,
      permissionKey: PermissionKeys.posSell),
  NavItem(
      route: '/products',
      icon: Icons.inventory_2_rounded,
      label: 'المنتجات',
      permissionKey: PermissionKeys.productsView),
  NavItem(
      route: '/categories',
      icon: Icons.category_rounded,
      label: 'الفئات',
      permissionKey: PermissionKeys.productsView),
  NavItem(
      route: '/customers',
      icon: Icons.people_rounded,
      label: 'العملاء',
      permissionKey: PermissionKeys.posSell),
  NavItem(
      route: '/suppliers',
      icon: Icons.local_shipping_rounded,
      label: 'الموردون',
      permissionKey: PermissionKeys.purchasesView),
  NavItem(
      route: '/purchases',
      icon: Icons.receipt_long_rounded,
      label: 'المشتريات',
      permissionKey: PermissionKeys.purchasesView),
  NavItem(
      route: '/opening-stock',
      icon: Icons.start_rounded,
      label: 'الرصيد الافتتاحي',
      permissionKey: PermissionKeys.productsEdit),
  NavItem(
      route: '/inventory',
      icon: Icons.warehouse_rounded,
      label: 'المخزن',
      permissionKey: PermissionKeys.productsView),
  NavItem(
      route: '/supplier-returns',
      icon: Icons.local_shipping_rounded,
      label: 'مرتجعات الموردين',
      permissionKey: PermissionKeys.purchasesEdit),
  NavItem(
      route: '/pricing',
      icon: Icons.local_offer_rounded,
      label: 'العروض والأسعار',
      permissionKey: PermissionKeys.settingsEdit),
  //vItem(route: '/loyalty-settings', icon: Icons.star_rounded, label: 'إعدادات النقاط', permissionKey: 'settings.edit'),
  NavItem(
      route: '/invoice-history',
      icon: Icons.receipt_long_rounded,
      label: 'سجل الفواتير',
      permissionKey: PermissionKeys.reportsView),
  NavItem(
      route: '/reports',
      icon: Icons.bar_chart_rounded,
      label: 'التقارير',
      permissionKey: PermissionKeys.reportsView),
  NavItem(
      route: '/financial',
      icon: Icons.account_balance_wallet_rounded,
      label: 'الماليات',
      permissionKey: PermissionKeys.analyticsFinancial),
  NavItem(
      route: '/expenses',
      icon: Icons.receipt_long_rounded,
      label: 'المصروفات',
      permissionKey: PermissionKeys.financialExpensesView),
  NavItem(
      route: '/automation/actions',
      icon: Icons.auto_awesome_rounded,
      label: 'مركز الإجراءات',
      permissionKey: PermissionKeys.automationView),
  NavItem(
      route: '/return-analytics',
      icon: Icons.assignment_return_rounded,
      label: 'تحليلات المرتجعات',
      permissionKey: PermissionKeys.reportsView),

  NavItem(
      route: '/activity',
      icon: Icons.history_rounded,
      label: 'سجل النشاط',
      permissionKey: PermissionKeys.auditView),  //vItem(route: '/users', icon: Icons.manage_accounts_rounded, label: 'المستخدمون', permissionKey: 'users.manage'),
  //vItem(route: '/roles', icon: Icons.security_rounded, label: 'الصلاحيات', permissionKey: 'users.manage'),
  //vItem(route: '/backup', icon: Icons.backup_rounded, label: 'النسخ الاحتياطي', permissionKey: 'settings.edit'),
  NavItem(
    route: '/settings',
    icon: Icons.settings,
    label: 'الإعدادات',
    permissionKey: PermissionKeys.settingsEdit,
  ),
];

class SideNav extends ConsumerWidget {
  final String currentRoute;
  const SideNav({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    final authState = ref.watch(authProvider).valueOrNull;

    // Filter items by permission
    final visibleItems = kNavItems.where((item) {
      if (item.permissionKey == null) return true;
      return permissions.hasPermissionSync(item.permissionKey!);
    }).toList();

    return Container(
      width: 220,
      color: AppColors.primary,
      child: Column(
        children: [
          // Logo area
          Container(
            height: 80,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.point_of_sale,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Lez POS',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 8),
          // Nav Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              children: visibleItems
                  .map((item) => _NavTile(
                      item: item,
                      isActive: currentRoute == item.route ||
                          (item.route != '/dashboard' &&
                              currentRoute.startsWith(item.route))))
                  .toList(),
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          // User Info & Logout
          if (authState?.user != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.person_rounded,
                      color: Colors.white70, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      authState!.user!.fullName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded,
                        color: Colors.white70, size: 20),
                    tooltip: 'تسجيل الخروج',
                    onPressed: () {
                      ref.read(authProvider.notifier).logout();
                      context.go('/login');
                    },
                  ),
                ],
              ),
            ),
          // Bottom: version
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'v1.0.0',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final NavItem item;
  final bool isActive;
  const _NavTile({required this.item, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => context.go(item.route),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: isActive
                  ? (item.isPrimary
                      ? AppColors.accent
                      : Colors.white.withValues(alpha: 0.15))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  color: isActive ? Colors.white : Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
