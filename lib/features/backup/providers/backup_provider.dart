// lib/features/backup/providers/backup_provider.dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/database/app_database.dart';
import '../../auth/providers/auth_provider.dart';

// --- State Model ---
class BackupSettings {
  final bool isAutoBackupEnabled;
  final String backupFrequency; // 'DAILY', 'WEEKLY'
  final String? customBackupFolder;

  const BackupSettings({
    this.isAutoBackupEnabled = true,
    this.backupFrequency = 'DAILY',
    this.customBackupFolder,
  });

  BackupSettings copyWith({
    bool? isAutoBackupEnabled,
    String? backupFrequency,
    String? customBackupFolder,
  }) {
    return BackupSettings(
      isAutoBackupEnabled: isAutoBackupEnabled ?? this.isAutoBackupEnabled,
      backupFrequency: backupFrequency ?? this.backupFrequency,
      customBackupFolder: customBackupFolder ?? this.customBackupFolder,
    );
  }
}

// --- Provider Notifier ---
class BackupSettingsNotifier extends AsyncNotifier<BackupSettings> {
  late SharedPreferences _prefs;

  @override
  Future<BackupSettings> build() async {
    _prefs = await SharedPreferences.getInstance();
    return BackupSettings(
      isAutoBackupEnabled: _prefs.getBool('auto_backup_enabled') ?? true,
      backupFrequency: _prefs.getString('backup_frequency') ?? 'DAILY',
      customBackupFolder: _prefs.getString('backup_folder'),
    );
  }

  Future<void> toggleAutoBackup(bool enabled) async {
    await _prefs.setBool('auto_backup_enabled', enabled);
    state = AsyncData(state.value!.copyWith(isAutoBackupEnabled: enabled));
  }

  Future<void> setFrequency(String freq) async {
    await _prefs.setString('backup_frequency', freq);
    state = AsyncData(state.value!.copyWith(backupFrequency: freq));
  }

  Future<void> setCustomFolder(String folderPath) async {
    await _prefs.setString('backup_folder', folderPath);
    state = AsyncData(state.value!.copyWith(customBackupFolder: folderPath));
  }

  // --- Auto Backup Logic ---
  Future<void> checkAndPerformAutoBackup() async {
    final settings = state.valueOrNull;
    if (settings == null || !settings.isAutoBackupEnabled) return;

    final lastBackupStr = _prefs.getString('last_auto_backup_time');
    final lastBackup = lastBackupStr != null ? DateTime.parse(lastBackupStr) : null;
    final now = DateTime.now();

    bool shouldBackup = false;
    if (lastBackup == null) {
      shouldBackup = true;
    } else {
      final diff = now.difference(lastBackup).inDays;
      if (settings.backupFrequency == 'DAILY' && diff >= 1) {
        shouldBackup = true;
      } else if (settings.backupFrequency == 'WEEKLY' && diff >= 7) {
        shouldBackup = true;
      }
    }

    if (shouldBackup) {
      try {
        final file = await BackupService.performBackup(isAuto: true);
        await _prefs.setString('last_auto_backup_time', now.toIso8601String());
        
        // Log it via DAO
        await AppDatabase.instance.logsDao.insertLog(
          userId: null,
          actionType: 'auto_backup_created',
          details: 'تم إجراء نسخة احتياطية تلقائية: ${file.path}',
        );
        
        ref.invalidate(recentLogsProvider);
      } catch (e) {
        // Silently fail for auto-backup
        try {
          await AppDatabase.instance.logsDao.insertLog(
            userId: null,
            actionType: 'auto_backup_failed',
            details: 'فشل النسخ التلقائي: $e',
          );
        } catch (_) {}
      }
    }
  }

  // --- Actions ---
  Future<void> createManualBackup() async {
    // 1. Verify Permission
    final authState = ref.read(authProvider).valueOrNull;
    if (authState == null || !authState.hasPermission('backup_database')) {
      throw Exception('عذراً، ليس لديك صلاحية أخذ نسخة احتياطية.');
    }

    // 2. Perform Backup
    final file = await BackupService.performBackup(isAuto: false);

    // 3. Log Action
    await AppDatabase.instance.logsDao.insertLog(
      userId: authState.user?.id,
      actionType: 'backup_created',
      details: 'تم إنشاء نسخة احتياطية يدوياً: ${file.path}',
    );
    
    // Refresh log stream
    ref.invalidate(recentLogsProvider);
  }

  Future<void> restoreFromBackup(String filePath) async {
    // 1. Verify Permission
    final authState = ref.read(authProvider).valueOrNull;
    if (authState == null || !authState.hasPermission('backup_database')) {
      throw Exception('عذراً، ليس لديك صلاحية استعادة النظام.');
    }

    // 2. Log intention
    await AppDatabase.instance.logsDao.insertLog(
      userId: authState.user?.id,
      actionType: 'backup_restored',
      details: 'تمت استعادة نسخة احتياطية: $filePath',
    );

    // 3. Restore Db (Will throw if missing)
    await BackupService.restoreBackup(filePath);
    
    // Note: After restore, the DB connection is closed and the file is replaced.
    // The application MUST restart to re-open the database with new content correctly.
  }
  
  Future<List<File>> getExistingBackups() async {
    final defaultDir = await BackupService.getBackupDirectory();
    final dir = Directory(defaultDir);
    if (!await dir.exists()) return [];
    
    final files = await dir.list().toList();
    final dbFiles = files.whereType<File>().where((f) => f.path.endsWith('.db')).toList();
    dbFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync())); // Newest first
    return dbFiles;
  }
}

final backupSettingsProvider = AsyncNotifierProvider<BackupSettingsNotifier, BackupSettings>(
  BackupSettingsNotifier.new,
);

final recentLogsProvider = StreamProvider((ref) {
  return AppDatabase.instance.logsDao.watchRecentLogs(limit: 20);
});
