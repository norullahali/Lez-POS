// lib/core/services/activity_retention_service.dart
//
// Skeleton only — NO destructive cleanup operations.
import 'package:flutter/foundation.dart';
import '../activity/activity_retention_config.dart';
import '../database/app_database.dart';

class ActivityRetentionService {
  ActivityRetentionService(this._db);

  final AppDatabase _db;

  /// Estimates rows older than [before] that would be eligible for archive.
  /// Placeholder: returns 0 until archive pipeline exists.
  Future<int> estimateEligibleForArchive(DateTime before) async {
    debugPrint(
      '[ActivityRetention] estimateEligibleForArchive(before=$before, schema=${_db.schemaVersion}) — not implemented',
    );
    return 0;
  }

  /// Placeholder archive hook — intentionally disabled.
  Future<void> archiveLogsBefore(DateTime before) async {
    if (!ActivityRetentionConfig.enableAutoCleanup) {
      debugPrint(
        '[ActivityRetention] archiveLogsBefore skipped — auto cleanup disabled',
      );
      return;
    }
    throw UnimplementedError(
      'Activity log archive is not enabled. Configure retention pipeline first.',
    );
  }

  /// Placeholder purge hook — intentionally disabled.
  Future<void> purgeArchivedLogsBefore(DateTime before) async {
    debugPrint(
      '[ActivityRetention] purgeArchivedLogsBefore blocked — destructive ops disabled',
    );
  }
}