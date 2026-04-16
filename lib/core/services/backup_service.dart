// lib/core/services/backup_service.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart' hide TextDirection;
import '../database/app_database.dart';

class BackupService {
  /// Ensures the backup directory exists and returns its path
  static Future<String> getBackupDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(docsDir.path, 'LezPOS', 'Backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir.path;
  }

  /// Creates a manual or automated backup of the database
  static Future<File> performBackup({bool isAuto = false}) async {
    // 1. Get current DB path
    final customPath = await AppDatabase.getCustomPath();
    String dbPath;
    if (customPath != null && customPath.isNotEmpty) {
      dbPath = customPath;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      dbPath = p.join(appDir.path, 'LezPOS', 'lez_pos.db');
    }
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception('ملف قاعدة البيانات غير موجود. لا يمكن إنشاء نسخة احتياطية.');
    }

    // 2. Prepare destination
    final backupDirPath = await getBackupDirectory();
    final now = DateTime.now();
    final timestamp = DateFormat('yyyy_MM_dd_HH_mm').format(now);
    final prefix = isAuto ? 'auto_backup' : 'lez_backup';
    final destinationPath = p.join(backupDirPath, '${prefix}_$timestamp.db');

    // 3. Copy file
    final backupFile = await dbFile.copy(destinationPath);
    
    // 4. Prune old backups (Keep last 14)
    await _pruneOldBackups();

    return backupFile;
  }

  /// Keeps only the 14 most recent backups in the default backup folder
  static Future<void> _pruneOldBackups() async {
    final backupDirPath = await getBackupDirectory();
    final backupDir = Directory(backupDirPath);
    
    final List<FileSystemEntity> files = await backupDir.list().toList();
    final dbFiles = files.whereType<File>().where((f) => f.path.endsWith('.db')).toList();

    if (dbFiles.length <= 14) return; // Nothing to prune

    // Sort ascending by modified time (oldest first)
    dbFiles.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

    // Delete the oldest files until only 14 remain
    final filesToDeleteCount = dbFiles.length - 14;
    for (int i = 0; i < filesToDeleteCount; i++) {
      try {
        await dbFiles[i].delete();
      } catch (e) {
        // Log silently
      }
    }
  }

  /// Restores a database file to the active location
  static Future<void> restoreBackup(String backupFilePath) async {
    final backupFile = File(backupFilePath);
    if (!await backupFile.exists()) {
      throw Exception('ملف النسخة الاحتياطية غير موجود!');
    }

    // 1. Get current DB Path
    final customPath = await AppDatabase.getCustomPath();
    String activeDbPath;
    if (customPath != null && customPath.isNotEmpty) {
      activeDbPath = customPath;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      activeDbPath = p.join(appDir.path, 'LezPOS', 'lez_pos.db');
    }
    final activeDbFile = File(activeDbPath);

    // 2. Create emergency safety backup before replacing
    if (await activeDbFile.exists()) {
      final backupDirPath = await getBackupDirectory();
      final emergencyPath = p.join(backupDirPath, 'emergency_restore_backup_${DateTime.now().millisecondsSinceEpoch}.db');
      await activeDbFile.copy(emergencyPath);
    }

    // 3. Overwrite active DB
    AppDatabase.instance.close(); // Attempt to release lock
    await backupFile.copy(activeDbPath);
  }
}
