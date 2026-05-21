// lib/core/services/activity_logger_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../activity/activity_categories.dart';
import '../activity/activity_context.dart';
import '../activity/activity_severity.dart';
import '../database/app_database.dart';

class ActivityLoggerService {
  ActivityLoggerService(this._db);

  final AppDatabase _db;

  Future<void> logInfo({
    required String activityType,
    required String category,
    required String action,
    required String title,
    String? description,
    String? entityType,
    int? entityId,
    Map<String, dynamic>? metadata,
    String? routeContext,
    ActivityContextSnapshot? contextOverride,
  }) =>
      _write(
        activityType: activityType,
        category: category,
        severity: ActivitySeverity.info,
        action: action,
        title: title,
        description: description,
        entityType: entityType,
        entityId: entityId,
        metadata: metadata,
        routeContext: routeContext,
        contextOverride: contextOverride,
      );

  Future<void> logWarning({
    required String activityType,
    required String category,
    required String action,
    required String title,
    String? description,
    String? entityType,
    int? entityId,
    Map<String, dynamic>? metadata,
    String? routeContext,
    ActivityContextSnapshot? contextOverride,
  }) =>
      _write(
        activityType: activityType,
        category: category,
        severity: ActivitySeverity.warning,
        action: action,
        title: title,
        description: description,
        entityType: entityType,
        entityId: entityId,
        metadata: metadata,
        routeContext: routeContext,
        contextOverride: contextOverride,
      );

  Future<void> logCritical({
    required String activityType,
    required String category,
    required String action,
    required String title,
    String? description,
    String? entityType,
    int? entityId,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    Map<String, dynamic>? metadata,
    String? routeContext,
    ActivityContextSnapshot? contextOverride,
  }) =>
      _write(
        activityType: activityType,
        category: category,
        severity: ActivitySeverity.critical,
        action: action,
        title: title,
        description: description,
        entityType: entityType,
        entityId: entityId,
        before: before,
        after: after,
        metadata: metadata,
        routeContext: routeContext,
        contextOverride: contextOverride,
      );

  Future<void> logSecurity({
    required String activityType,
    required String action,
    required String title,
    String? description,
    Map<String, dynamic>? metadata,
    String? routeContext,
    ActivityContextSnapshot? contextOverride,
  }) =>
      _write(
        activityType: activityType,
        category: ActivityCategories.security,
        severity: ActivitySeverity.security,
        action: action,
        title: title,
        description: description,
        metadata: metadata,
        routeContext: routeContext,
        contextOverride: contextOverride,
      );

  Future<void> logEntityCreate({
    required String activityType,
    required String category,
    required String entityType,
    required int entityId,
    required String title,
    String? description,
    Map<String, dynamic>? after,
    Map<String, dynamic>? metadata,
  }) =>
      _write(
        activityType: activityType,
        category: category,
        severity: ActivitySeverity.info,
        action: 'create',
        title: title,
        description: description,
        entityType: entityType,
        entityId: entityId,
        after: after,
        metadata: metadata,
      );

  Future<void> logEntityUpdate({
    required String activityType,
    required String category,
    required String entityType,
    required int entityId,
    required String title,
    String? description,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    String severity = ActivitySeverity.info,
    Map<String, dynamic>? metadata,
  }) =>
      _write(
        activityType: activityType,
        category: category,
        severity: severity,
        action: 'update',
        title: title,
        description: description,
        entityType: entityType,
        entityId: entityId,
        before: before,
        after: after,
        metadata: metadata,
      );

  Future<void> logEntityDelete({
    required String activityType,
    required String category,
    required String entityType,
    required int entityId,
    required String title,
    String? description,
    Map<String, dynamic>? before,
    Map<String, dynamic>? metadata,
  }) =>
      _write(
        activityType: activityType,
        category: category,
        severity: ActivitySeverity.warning,
        action: 'delete',
        title: title,
        description: description,
        entityType: entityType,
        entityId: entityId,
        before: before,
        metadata: metadata,
      );

  Future<void> _write({
    required String activityType,
    required String category,
    required String severity,
    required String action,
    required String title,
    String? description,
    String? entityType,
    int? entityId,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    Map<String, dynamic>? metadata,
    String? routeContext,
    ActivityContextSnapshot? contextOverride,
  }) async {
    try {
      final ctx = contextOverride ?? ActivityContextHolder.current;
      await _db.activityLogsDao.insertLog(
        ActivityLogsCompanion.insert(
          activityType: activityType,
          category: category,
          severity: severity,
          userId: Value(ctx.userId),
          usernameSnapshot: Value(ctx.username),
          roleSnapshot: Value(ctx.roleName),
          sessionId: Value(ctx.sessionId),
          entityType: Value(entityType),
          entityId: Value(entityId),
          action: action,
          title: title,
          description: Value(description),
          beforeJson: Value(_encode(before)),
          afterJson: Value(_encode(after)),
          metadataJson: Value(_encode(metadata)),
          routeContext: Value(routeContext ?? ctx.routeContext),
        ),
      );
    } catch (e, st) {
      debugPrint('[ActivityLogger] write failed: $e\n$st');
    }
  }

  String? _encode(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return null;
    try {
      return jsonEncode(data);
    } catch (_) {
      return null;
    }
  }
}