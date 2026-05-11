import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsHomeScreen extends StatelessWidget {
  const SettingsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _item(context, 'إعدادات الفاتورة', '/settings/invoice'),
              _item(context, 'النسخ الاحتياطي', '/backup'),
              _item(context, 'المستخدمين', '/users'),
              _item(context, 'الصلاحيات', '/roles'),
              _item(context, 'نقاط الولاء', '/loyalty-settings'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, String title, String route) {
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
