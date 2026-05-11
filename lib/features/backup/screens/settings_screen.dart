import 'package:flutter/material.dart';
import '../../settings/screens/invoice_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("الإعدادات")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          /// 🧾 إعدادات الفاتورة
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text("إعدادات الفاتورة"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const InvoiceSettingsScreen(),
                ),
              );
            },
          ),

          /// ⭐ النقاط
          ListTile(
            leading: const Icon(Icons.star),
            title: const Text("إعدادات النقاط"),
            onTap: () {},
          ),

          /// 👤 المستخدمين
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text("المستخدمون"),
            onTap: () {},
          ),

          /// 🔐 الصلاحيات
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text("الصلاحيات"),
            onTap: () {},
          ),

          /// 💾 النسخ الاحتياطي
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text("النسخ الاحتياطي"),
            onTap: () {
              // لاحقاً نربطها
            },
          ),
        ],
      ),
    );
  }
}
