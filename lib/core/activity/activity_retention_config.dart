// lib/core/activity/activity_retention_config.dart
//
// Future-ready retention policy placeholders. No cleanup is enabled yet.
class ActivityRetentionConfig {
  ActivityRetentionConfig._();

  /// Default hot-storage retention window (days) before archive eligibility.
  static const int defaultRetentionDays = 365;

  /// Optional cold archive window (days) — placeholder for future export/archive.
  static const int archiveAfterDays = 730;

  /// Master switch for automated cleanup (must remain false until explicitly implemented).
  static const bool enableAutoCleanup = false;

  /// Placeholder for future batch archive size limits.
  static const int archiveBatchSize = 500;

  /// Placeholder strategy identifiers for future implementations.
  static const String strategyLocalArchive = 'local_archive';
  static const String strategyCloudExport = 'cloud_export';
  static const String strategyForensicHold = 'forensic_hold';
}