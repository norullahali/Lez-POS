import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/users_provider.dart';

import '../widgets/role_form_dialog.dart';

class RolesScreen extends ConsumerWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(rolesProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'الأدوار في النظام',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const RoleFormDialog(),
                ),
                icon: const Icon(Icons.add),
                label: const Text('إضافة دور'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: rolesAsync.when(
              data: (roles) {
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: roles.length,
                    separatorBuilder: (_, __) => const Divider(height: 32),
                    itemBuilder: (context, index) {
                      final role = roles[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withAlpha(25),
                          child: const Icon(Icons.shield_rounded, color: AppColors.primary),
                        ),
                        title: Row(
                          children: [
                            Text(role.roleName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            if (role.isSystem) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.red.withAlpha(25), borderRadius: BorderRadius.circular(4)),
                                child: const Text('أساسي', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ]
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(role.description ?? 'بدون وصف', style: const TextStyle(color: AppColors.textSecondary)),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_rounded, color: AppColors.primary),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => RoleFormDialog(role: role),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('خطأ: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
