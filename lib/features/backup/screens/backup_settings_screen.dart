// lib/features/backup/screens/backup_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/backup_provider.dart';

class BackupSettingsScreen extends ConsumerWidget {
  const BackupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(backupSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('خطأ: $err')),
      data: (settings) {
        final notifier = ref.read(backupSettingsProvider.notifier);

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              color: AppColors.surface,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: const Text('تفعيل النسخ التلقائي',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text(
                          'إجراء نسخة احتياطية دورية للنظام (يحتفظ بآخر 14 نسخة فقط).'),
                      value: settings.isAutoBackupEnabled,
                      activeThumbColor: AppColors.success,
                      onChanged: (val) => notifier.toggleAutoBackup(val),
                    ),
                    const Divider(color: AppColors.border, height: 32),
                    ListTile(
                      title: const Text('تكرار النسخ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('كم مرة ترغب في أن يقوم النظام بنسخ البيانات؟'),
                      trailing: DropdownButton<String>(
                        value: settings.backupFrequency,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'DAILY', child: Text('يومياً')),
                          DropdownMenuItem(value: 'WEEKLY', child: Text('أسبوعياً')),
                        ],
                        onChanged: settings.isAutoBackupEnabled
                            ? (val) {
                                if (val != null) notifier.setFrequency(val);
                              }
                            : null,
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 32),
                    ListTile(
                      title: const Text('مجلد الحفظ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        settings.customBackupFolder ??
                            'المجلد الافتراضي: Documents/LezPOS/Backups/',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      trailing: ElevatedButton.icon(
                        icon: const Icon(Icons.folder_open_rounded, size: 20),
                        label: const Text('تغيير المسار (قريباً)'),
                        onPressed:
                            null, // Custom path feature could be expanded later via file_picker package
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
