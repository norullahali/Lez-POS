// lib/features/backup/screens/backup_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';
import '../providers/backup_provider.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final recentLogs = ref.watch(recentLogsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'إدارة النسخ الاحتياطي والبيانات',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.settings_rounded, color: AppColors.primary),
                tooltip: 'إعدادات النسخ التلقائي',
                onPressed: () => context.push('/backup/settings'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Side - Actions
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       const Text(
                        'النسخ اليدوي',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'قم بإنشاء نسخة احتياطية من جميع بيانات المتجر الآن لتأمينها.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          icon: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.backup_rounded),
                          label: Text(_isLoading ? 'جاري النسخ...' : 'إنشاء نسخة احتياطية الآن', style: const TextStyle(fontSize: 16)),
                          onPressed: _isLoading ? null : _createManualBackup,
                        ),
                      ),
                      const SizedBox(height: 48),
                      const Text(
                        'استعادة البيانات',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'استعن بنسخة احتياطية سابقة. (سيفقد النظام أي بيانات تمت إضافتها بعد تاريخ النسخة)',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.restore_page_rounded, color: AppColors.error),
                          label: const Text('استعادة من ملف', style: TextStyle(fontSize: 16, color: AppColors.error)),
                          style: OutlinedButton.styleFrom(side: BorderSide(color: AppColors.error.withValues(alpha: 0.5))),
                          onPressed: _isLoading ? null : _restoreBackup,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Right Side - Logs
                Expanded(
                  flex: 3,
                  child: Container(
                    margin: const EdgeInsets.only(right: 24),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Icon(Icons.history_rounded, color: AppColors.accent),
                              SizedBox(width: 12),
                              Text('سجل عمليات النسخ الاحتياطي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        Expanded(
                          child: recentLogs.when(
                            loading: () => const Center(child: CircularProgressIndicator()),
                            error: (e, _) => Center(child: Text('خطأ في تحميل السجل: $e')),
                            data: (logs) {
                              if (logs.isEmpty) {
                                return const Center(child: Text('لا توجد عمليات سابقة.', style: TextStyle(color: AppColors.textHint)));
                              }
                              return ListView.builder(
                                itemCount: logs.length,
                                itemBuilder: (context, index) {
                                  final log = logs[index];
                                  final isCreate = log.actionType == 'backup_created';
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isCreate ? AppColors.successLight.withValues(alpha: 0.2) : AppColors.warning.withValues(alpha: 0.2),
                                      child: Icon(
                                        isCreate ? Icons.download_done_rounded : Icons.restore_rounded,
                                        color: isCreate ? AppColors.success : AppColors.warning,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(log.details ?? log.actionType, style: const TextStyle(fontSize: 13)),
                                    subtitle: Text(
                                      DateFormat('yyyy-MM-dd HH:mm').format(log.timestamp),
                                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createManualBackup() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(backupSettingsProvider.notifier).createManualBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم أخذ النسخة الاحتياطية بنجاح!'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreBackup() async {
    // 1. Let user pick a file from standard directory
    final backups = await ref.read(backupSettingsProvider.notifier).getExistingBackups();
    
    if (!mounted) return;
    final selectedFile = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختر ملف الاستعادة'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: backups.isEmpty 
            ? const Center(child: Text('لا توجد نسخ احتياطية في المجلد الافتراضي.'))
            : ListView.builder(
                itemCount: backups.length,
                itemBuilder: (_, i) {
                  final f = backups[i];
                  return ListTile(
                    leading: const Icon(Icons.data_usage_rounded, color: AppColors.accent),
                    title: Text(f.uri.pathSegments.last),
                    subtitle: Text(DateFormat('yyyy-MM-dd HH:mm').format(f.lastModifiedSync())),
                    onTap: () => Navigator.pop(ctx, f.path),
                  );
                },
              ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        ],
      ),
    );

    if (selectedFile == null) return;

    // 2. Confirm Restoration intent (Dangerous)
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الاستعادة!', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
        content: const Text(
          'سيتم استبدال جميع البيانات الحالية بالنسخة الاحتياطية المختارة.\n\n'
          'تحذير: التطبيق سيغلق تلقائياً بعد العملية، ويجب إعادة تشغيله يدوياً لتفعيل البيانات الجديدة.'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد واستعادة'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 3. Perform Restore
    setState(() => _isLoading = true);
    try {
      await ref.read(backupSettingsProvider.notifier).restoreFromBackup(selectedFile);
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('تمت الاستعادة بنجاح', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
            content: const Text('تم استعادة البيانات بنجاح. سيتم إغلاق التطبيق الآن، يرجى إعادة تشغيله يدوياً.'),
            actions: [
              ElevatedButton(
                onPressed: () => exit(0), 
                child: const Text('إغلاق التطبيق الآن'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشلت الاستعادة: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
