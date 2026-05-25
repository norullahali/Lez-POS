import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/workflow_lifecycle_state.dart';

class WorkflowLifecycleRecord {
  const WorkflowLifecycleRecord({
    required this.workflowId,
    required this.fingerprint,
    required this.state,
    required this.generatedAt,
    required this.lastSeenAt,
    this.reviewedAt,
    this.acceptedAt,
    this.ignoredAt,
    this.completedAt,
    this.whyGenerated,
    this.sourceEngine,
    this.triggerSource,
  });

  final String workflowId;
  final String fingerprint;
  final WorkflowLifecycleState state;
  final DateTime generatedAt;
  final DateTime lastSeenAt;
  final DateTime? reviewedAt;
  final DateTime? acceptedAt;
  final DateTime? ignoredAt;
  final DateTime? completedAt;
  final String? whyGenerated;
  final String? sourceEngine;
  final String? triggerSource;

  WorkflowLifecycleRecord copyWith({
    WorkflowLifecycleState? state,
    DateTime? lastSeenAt,
    DateTime? reviewedAt,
    DateTime? acceptedAt,
    DateTime? ignoredAt,
    DateTime? completedAt,
  }) {
    return WorkflowLifecycleRecord(
      workflowId: workflowId,
      fingerprint: fingerprint,
      state: state ?? this.state,
      generatedAt: generatedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      ignoredAt: ignoredAt ?? this.ignoredAt,
      completedAt: completedAt ?? this.completedAt,
      whyGenerated: whyGenerated,
      sourceEngine: sourceEngine,
      triggerSource: triggerSource,
    );
  }

  Map<String, dynamic> toJson() => {
        'workflowId': workflowId,
        'fingerprint': fingerprint,
        'state': state.name,
        'generatedAt': generatedAt.toIso8601String(),
        'lastSeenAt': lastSeenAt.toIso8601String(),
        'reviewedAt': reviewedAt?.toIso8601String(),
        'acceptedAt': acceptedAt?.toIso8601String(),
        'ignoredAt': ignoredAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'whyGenerated': whyGenerated,
        'sourceEngine': sourceEngine,
        'triggerSource': triggerSource,
      };

  factory WorkflowLifecycleRecord.fromJson(Map<String, dynamic> json) {
    return WorkflowLifecycleRecord(
      workflowId: json['workflowId'] as String,
      fingerprint: json['fingerprint'] as String,
      state: WorkflowLifecycleState.values.firstWhere(
        (e) => e.name == json['state'],
        orElse: () => WorkflowLifecycleState.pending,
      ),
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      lastSeenAt: DateTime.parse(json['lastSeenAt'] as String),
      reviewedAt: json['reviewedAt'] != null ? DateTime.tryParse(json['reviewedAt'] as String) : null,
      acceptedAt: json['acceptedAt'] != null ? DateTime.tryParse(json['acceptedAt'] as String) : null,
      ignoredAt: json['ignoredAt'] != null ? DateTime.tryParse(json['ignoredAt'] as String) : null,
      completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'] as String) : null,
      whyGenerated: json['whyGenerated'] as String?,
      sourceEngine: json['sourceEngine'] as String?,
      triggerSource: json['triggerSource'] as String?,
    );
  }
}

class WorkflowLifecycleStore {
  WorkflowLifecycleStore._();
  static const _key = 'automation_workflow_lifecycle_v1';

  static Future<Map<String, WorkflowLifecycleRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, WorkflowLifecycleRecord.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(Map<String, WorkflowLifecycleRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(records.map((k, v) => MapEntry(k, v.toJson()))));
  }

  static Future<WorkflowLifecycleRecord> touch({
    required String workflowId,
    required String fingerprint,
    String? whyGenerated,
    String? sourceEngine,
    String? triggerSource,
  }) async {
    final records = await load();
    final now = DateTime.now();
    final existing = records[fingerprint];
    final record = existing?.copyWith(lastSeenAt: now) ??
        WorkflowLifecycleRecord(
          workflowId: workflowId,
          fingerprint: fingerprint,
          state: WorkflowLifecycleState.pending,
          generatedAt: now,
          lastSeenAt: now,
          whyGenerated: whyGenerated,
          sourceEngine: sourceEngine,
          triggerSource: triggerSource,
        );
    records[fingerprint] = record;
    await save(records);
    return record;
  }

  static Future<WorkflowLifecycleRecord?> transition(
    String fingerprint,
    WorkflowLifecycleState next,
  ) async {
    final records = await load();
    final existing = records[fingerprint];
    if (existing == null) return null;
    final allowed = existing.state.transitionTo(next);
    if (allowed == null) return existing;
    final now = DateTime.now();
    records[fingerprint] = existing.copyWith(
      state: allowed,
      lastSeenAt: now,
      reviewedAt: allowed == WorkflowLifecycleState.reviewed ? now : existing.reviewedAt,
      acceptedAt: allowed == WorkflowLifecycleState.accepted ? now : existing.acceptedAt,
      ignoredAt: allowed == WorkflowLifecycleState.ignored ? now : existing.ignoredAt,
      completedAt: allowed == WorkflowLifecycleState.completed ? now : existing.completedAt,
    );
    await save(records);
    return records[fingerprint];
  }
}