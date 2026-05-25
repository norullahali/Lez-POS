import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/automation_audit_context.dart';
import '../models/recommendation_invalidation.dart';
import '../models/workflow_lifecycle_state.dart';

class RecommendationRecord {
  const RecommendationRecord({
    required this.fingerprint,
    required this.kind,
    required this.sourceEngine,
    required this.lifecycleState,
    required this.generatedAt,
    required this.lastRefreshedAt,
    required this.occurrenceCount,
    required this.whyGenerated,
    required this.heuristicExplanation,
    required this.triggerSource,
    this.reviewedAt,
    this.acceptedAt,
    this.ignoredAt,
    this.completedAt,
    this.expiresAt,
    this.invalidatesOn = const [],
    this.sourceMetrics = const {},
    this.confidence = HeuristicConfidence.medium,
    this.titleSnapshot,
    this.entityType,
    this.entityId,
  });

  final String fingerprint;
  final String kind;
  final AutomationSourceEngine sourceEngine;
  final WorkflowLifecycleState lifecycleState;
  final DateTime generatedAt;
  final DateTime lastRefreshedAt;
  final DateTime? reviewedAt;
  final DateTime? acceptedAt;
  final DateTime? ignoredAt;
  final DateTime? completedAt;
  final DateTime? expiresAt;
  final List<RecommendationInvalidatesOn> invalidatesOn;
  final int occurrenceCount;
  final String whyGenerated;
  final Map<String, dynamic> sourceMetrics;
  final String heuristicExplanation;
  final String triggerSource;
  final HeuristicConfidence confidence;
  final String? titleSnapshot;
  final String? entityType;
  final int? entityId;

  bool get isStale => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  RecommendationRecord copyWith({
    WorkflowLifecycleState? lifecycleState,
    DateTime? lastRefreshedAt,
    DateTime? reviewedAt,
    DateTime? acceptedAt,
    DateTime? ignoredAt,
    DateTime? completedAt,
    DateTime? expiresAt,
    int? occurrenceCount,
    String? whyGenerated,
    Map<String, dynamic>? sourceMetrics,
    String? titleSnapshot,
  }) {
    return RecommendationRecord(
      fingerprint: fingerprint,
      kind: kind,
      sourceEngine: sourceEngine,
      lifecycleState: lifecycleState ?? this.lifecycleState,
      generatedAt: generatedAt,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      ignoredAt: ignoredAt ?? this.ignoredAt,
      completedAt: completedAt ?? this.completedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      invalidatesOn: invalidatesOn,
      occurrenceCount: occurrenceCount ?? this.occurrenceCount,
      whyGenerated: whyGenerated ?? this.whyGenerated,
      sourceMetrics: sourceMetrics ?? this.sourceMetrics,
      heuristicExplanation: heuristicExplanation,
      triggerSource: triggerSource,
      confidence: confidence,
      titleSnapshot: titleSnapshot ?? this.titleSnapshot,
      entityType: entityType,
      entityId: entityId,
    );
  }

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'kind': kind,
        'sourceEngine': sourceEngine.name,
        'lifecycleState': lifecycleState.name,
        'generatedAt': generatedAt.toIso8601String(),
        'lastRefreshedAt': lastRefreshedAt.toIso8601String(),
        'reviewedAt': reviewedAt?.toIso8601String(),
        'acceptedAt': acceptedAt?.toIso8601String(),
        'ignoredAt': ignoredAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'invalidatesOn': invalidatesOn.map((e) => e.name).toList(),
        'occurrenceCount': occurrenceCount,
        'whyGenerated': whyGenerated,
        'sourceMetrics': sourceMetrics,
        'heuristicExplanation': heuristicExplanation,
        'triggerSource': triggerSource,
        'confidence': confidence.name,
        'titleSnapshot': titleSnapshot,
        'entityType': entityType,
        'entityId': entityId,
      };

  factory RecommendationRecord.fromJson(Map<String, dynamic> json) {
    return RecommendationRecord(
      fingerprint: json['fingerprint'] as String,
      kind: json['kind'] as String,
      sourceEngine: AutomationSourceEngine.values.firstWhere(
        (e) => e.name == json['sourceEngine'],
        orElse: () => AutomationSourceEngine.workflow,
      ),
      lifecycleState: WorkflowLifecycleState.values.firstWhere(
        (e) => e.name == json['lifecycleState'],
        orElse: () => WorkflowLifecycleState.pending,
      ),
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      lastRefreshedAt: DateTime.parse(json['lastRefreshedAt'] as String),
      reviewedAt: json['reviewedAt'] != null ? DateTime.tryParse(json['reviewedAt'] as String) : null,
      acceptedAt: json['acceptedAt'] != null ? DateTime.tryParse(json['acceptedAt'] as String) : null,
      ignoredAt: json['ignoredAt'] != null ? DateTime.tryParse(json['ignoredAt'] as String) : null,
      completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'] as String) : null,
      expiresAt: json['expiresAt'] != null ? DateTime.tryParse(json['expiresAt'] as String) : null,
      invalidatesOn: (json['invalidatesOn'] as List<dynamic>? ?? [])
          .map((e) => RecommendationInvalidatesOn.values.firstWhere((v) => v.name == e, orElse: () => RecommendationInvalidatesOn.ttl))
          .toList(),
      occurrenceCount: (json['occurrenceCount'] as int?) ?? 1,
      whyGenerated: json['whyGenerated'] as String? ?? '',
      sourceMetrics: Map<String, dynamic>.from(json['sourceMetrics'] as Map? ?? {}),
      heuristicExplanation: json['heuristicExplanation'] as String? ?? '',
      triggerSource: json['triggerSource'] as String? ?? '',
      confidence: HeuristicConfidence.values.firstWhere(
        (e) => e.name == json['confidence'],
        orElse: () => HeuristicConfidence.medium,
      ),
      titleSnapshot: json['titleSnapshot'] as String?,
      entityType: json['entityType'] as String?,
      entityId: json['entityId'] as int?,
    );
  }
}

class RecommendationLifecycleStore {
  RecommendationLifecycleStore._();
  static const _key = 'automation_recommendation_lifecycle_v1';

  static Future<Map<String, RecommendationRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, RecommendationRecord.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(Map<String, RecommendationRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(records.map((k, v) => MapEntry(k, v.toJson()))));
  }

  static Future<RecommendationRecord?> get(String fingerprint) async {
    final records = await load();
    return records[fingerprint];
  }

  static Future<void> upsert(RecommendationRecord record) async {
    final records = await load();
    records[record.fingerprint] = record;
    await save(records);
  }
}