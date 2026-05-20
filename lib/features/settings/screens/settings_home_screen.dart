import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/permissions/route_permissions.dart';
import '../../auth/providers/permission_provider.dart';

class SettingsHomeScreen extends ConsumerWidget {
  const SettingsHomeScreen({super.key});

  static const _items = [
    ('إعدادات الفاتورة', '/settings/invoice'),
    ('النسخ الاحتياطي', '/backup'),
    ('المستخدمين', '/users'),
    ('الصلاحيات', '/roles'),
    ('نقاط الولاء', '/loyalty-settings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    final visibleItems = _items.where((item) {
      final required = permissionForRoute(item.$2);
      if (required == null) return true;
      return permissions.hasPermissionSync(required);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الإعدادات',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          if (visibleItems.isEmpty)
            const Text('لا توجد إعدادات متاحة لصلاحياتك الحالية.')
          else
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: visibleItems
                  .map((item) => _SettingsTile(title: item.$1, route: item.$2))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.title, required this.route});
  final String title;
  final String route;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(route),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(title),
      ),
    );
  }
}