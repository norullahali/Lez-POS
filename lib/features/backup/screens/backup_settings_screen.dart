import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/backup_provider.dart';

class BackupSettingsScreen extends ConsumerStatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  ConsumerState<BackupSettingsScreen> createState() =>
      _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends ConsumerState<BackupSettingsScreen> {
  @override
  Widget build(BuildContext context) {
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
                    /// 🔄 Backup Settings
                    SwitchListTile(
                      title: const Text(
                        'تفعيل النسخ التلقائي',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'إجراء نسخة احتياطية دورية للنظام.',
                      ),
                      value: settings.isAutoBackupEnabled,
                      activeThumbColor: AppColors.success,
                      onChanged: (val) => notifier.toggleAutoBackup(val),
                    ),

                    const Divider(height: 32),

                    ListTile(
                      title: const Text(
                        'تكرار النسخ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: DropdownButton<String>(
                        value: settings.backupFrequency,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                              value: 'DAILY', child: Text('يومياً')),
                          DropdownMenuItem(
                              value: 'WEEKLY', child: Text('أسبوعياً')),
                        ],
                        onChanged: settings.isAutoBackupEnabled
                            ? (val) {
                                if (val != null) notifier.setFrequency(val);
                              }
                            : null,
                      ),
                    ),

                    const Divider(height: 32),

                    ListTile(
                      title: const Text(
                        'مجلد الحفظ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        settings.customBackupFolder ??
                            'المجلد الافتراضي: Documents/LezPOS/Backups/',
                        style: const TextStyle(color: AppColors.textSecondary),
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
