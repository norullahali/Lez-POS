import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/users_provider.dart';
import '../widgets/user_form_dialog.dart';

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersListProvider);
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
                'قائمة المستخدمين',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('مستخدم جديد'),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const UserFormDialog(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: usersAsync.when(
              data: (users) => rolesAsync.when(
                data: (roles) {
                  final roleMap = {for (var r in roles) r.id: r.roleName};

                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: AppColors.border,
                          ),
                          child: DataTable(
                            headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                            columns: const [
                              DataColumn(label: Text('الاسم')),
                              DataColumn(label: Text('اسم المستخدم')),
                              DataColumn(label: Text('الدور')),
                              DataColumn(label: Text('الحالة')),
                              DataColumn(label: Text('تاريخ الإضافة')),
                              DataColumn(label: Text('الإجراءات')),
                            ],
                            rows: users.map((user) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.w600))),
                                  DataCell(Text(user.username)),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withAlpha(25),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        roleMap[user.roleId] ?? 'غير معروف',
                                        style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: user.isActive ? Colors.green.withAlpha(25) : Colors.red.withAlpha(25),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        user.isActive ? 'نشط' : 'غير نشط',
                                        style: TextStyle(
                                          color: user.isActive ? Colors.green[700] : Colors.red[700],
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(user.createdAt.toString().substring(0, 10))),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.edit_rounded, color: AppColors.textSecondary),
                                      tooltip: 'تعديل',
                                      onPressed: () => showDialog(
                                        context: context,
                                        builder: (_) => UserFormDialog(user: user),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('خطأ في تحميل الأدوار: $e')),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('خطأ في تحميل المستخدمين: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
