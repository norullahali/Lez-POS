import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/users_provider.dart';

class RoleFormDialog extends ConsumerStatefulWidget {
  final Role? role;
  const RoleFormDialog({super.key, this.role});

  @override
  ConsumerState<RoleFormDialog> createState() => _RoleFormDialogState();
}

class _RoleFormDialogState extends ConsumerState<RoleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  final Set<String> _selectedPermissions = {};
  bool _isLoading = false;
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.role?.roleName);
    _descCtrl = TextEditingController(text: widget.role?.description);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(List<Permission> allPerms) async {
    if (!_formKey.currentState!.validate()) return;
    
    // System roles can be edited for permissions, but name shouldn't ideally be changed, but we allow it for now or disable name.
    if (_selectedPermissions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار صلاحية واحدة على الأقل')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final selectedIds = allPerms
          .where((p) => _selectedPermissions.contains(p.permissionKey))
          .map((p) => p.id)
          .toList();

      final notifier = ref.read(usersProvider);
      final isSystem = widget.role?.isSystem ?? false;
      
      await notifier.saveRole(
        RolesCompanion(
          id: widget.role != null ? drift.Value(widget.role!.id) : const drift.Value.absent(),
          roleName: drift.Value(_nameCtrl.text.trim()),
          description: drift.Value(_descCtrl.text.trim()),
          isSystem: drift.Value(isSystem),
        ),
        selectedIds,
      );

      ref.invalidate(rolesProvider); // refresh list
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permsAsync = ref.watch(permissionsProvider);
    final rolePermsAsync = widget.role != null ? ref.watch(rolePermissionsProvider(widget.role!.id)) : const AsyncData<List<String>>([]);

    final isSystem = widget.role?.isSystem ?? false;

    return AlertDialog(
      title: Text(widget.role == null ? 'إضافة دور جديد' : 'تعديل الدور'),
      content: SizedBox(
        width: 500,
        height: 600,
        child: permsAsync.when(
          data: (allPerms) {
            return rolePermsAsync.when(
              data: (rolePerms) {
                // Initialize selection once
                if (!_isInit && widget.role != null) {
                  _selectedPermissions.addAll(rolePerms);
                  _isInit = true;
                }

                return Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: 'اسم الدور', border: OutlineInputBorder()),
                        validator: (v) => v!.isEmpty ? 'مطلوب' : null,
                        readOnly: isSystem, // protect system roles core name
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descCtrl,
                        decoration: const InputDecoration(labelText: 'الوصف', border: OutlineInputBorder()),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text('الصلاحيات الممنوحة:', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            itemCount: allPerms.length,
                            itemBuilder: (context, index) {
                              final p = allPerms[index];
                              final isSelected = _selectedPermissions.contains(p.permissionKey);
                              return CheckboxListTile(
                                title: Text(p.description),
                                subtitle: Text(p.permissionKey, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                                value: isSelected,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedPermissions.add(p.permissionKey);
                                    } else {
                                      _selectedPermissions.remove(p.permissionKey);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('خطأ: $e')),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('خطأ: $e')),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        if (_isLoading)
          const CircularProgressIndicator()
        else
          permsAsync.maybeWhen(
            data: (allPerms) => FilledButton(
              onPressed: () => _submit(allPerms),
              child: const Text('حفظ'),
            ),
            orElse: () => const SizedBox(),
          ),
      ],
    );
  }
}
