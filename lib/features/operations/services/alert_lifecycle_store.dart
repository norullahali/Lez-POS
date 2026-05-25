import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/operational_alert_state.dart';

class AlertLifecycleRecord {
  const AlertLifecycleRecord({
    required this.fingerprint,
    required this.state,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.occurrenceCount,
    this.lastNotifiedAt,
    this.previousSeverity,
  });

  final String fingerprint;
  final OperationalAlertState state;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final int occurrenceCount;
  final DateTime? lastNotifiedAt;
  final String? previousSeverity;

  AlertLifecycleRecord copyWith({
    OperationalAlertState? state,
    DateTime? lastSeenAt,
    int? occurrenceCount,
    DateTime? lastNotifiedAt,
    String? previousSeverity,
  }) {
    return AlertLifecycleRecord(
      fingerprint: fingerprint,
      state: state ?? this.state,
      firstSeenAt: firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      occurrenceCount: occurrenceCount ?? this.occurrenceCount,
      lastNotifiedAt: lastNotifiedAt ?? this.lastNotifiedAt,
      previousSeverity: previousSeverity ?? this.previousSeverity,
    );
  }

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'state': state.name,
        'firstSeenAt': firstSeenAt.toIso8601String(),
        'lastSeenAt': lastSeenAt.toIso8601String(),
        'occurrenceCount': occurrenceCount,
        'lastNotifiedAt': lastNotifiedAt?.toIso8601String(),
        'previousSeverity': previousSeverity,
      };

  factory AlertLifecycleRecord.fromJson(Map<String, dynamic> json) {
    return AlertLifecycleRecord(
      fingerprint: json['fingerprint'] as String,
      state: OperationalAlertState.values.firstWhere(
        (e) => e.name == json['state'],
        orElse: () => OperationalAlertState.active,
      ),
      firstSeenAt: DateTime.parse(json['firstSeenAt'] as String),
      lastSeenAt: DateTime.parse(json['lastSeenAt'] as String),
      occurrenceCount: (json['occurrenceCount'] as int?) ?? 1,
      lastNotifiedAt: json['lastNotifiedAt'] != null
          ? DateTime.tryParse(json['lastNotifiedAt'] as String)
          : null,
      previousSeverity: json['previousSeverity'] as String?,
    );
  }
}

class AlertLifecycleStore {
  AlertLifecycleStore._();

  static const _recordsKey = 'operations_alert_lifecycle_v2';
  static const _legacyDismissKey = 'operations_dismissed_alerts';

  static Future<Map<String, AlertLifecycleRecord>> loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyDismissed(prefs);
    final raw = prefs.getString(_recordsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (k, v) => MapEntry(k, AlertLifecycleRecord.fromJson(v as Map<String, dynamic>)),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveRecords(Map<String, AlertLifecycleRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(records.map((k, v) => MapEntry(k, v.toJson())));
    await prefs.setString(_recordsKey, encoded);
  }

  static Future<void> transition(String fingerprint, OperationalAlertState state) async {
    final records = await loadRecords();
    final existing = records[fingerprint];
    final now = DateTime.now();
    records[fingerprint] = (existing ??
            AlertLifecycleRecord(
              fingerprint: fingerprint,
              state: state,
              firstSeenAt: now,
              lastSeenAt: now,
              occurrenceCount: 1,
            ))
        .copyWith(state: state, lastSeenAt: now);
    await saveRecords(records);
  }

  static Future<void> dismiss(String fingerprint) =>
      transition(fingerprint, OperationalAlertState.archived);

  static Future<void> acknowledge(String fingerprint) =>
      transition(fingerprint, OperationalAlertState.acknowledged);

  static Future<void> resolve(String fingerprint) =>
      transition(fingerprint, OperationalAlertState.resolved);

  static Future<void> _migrateLegacyDismissed(SharedPreferences prefs) async {
    final legacy = prefs.getString(_legacyDismissKey);
    if (legacy == null || legacy.isEmpty) return;
    try {
      final list = jsonDecode(legacy) as List<dynamic>;
      final records = await loadRecords();
      final now = DateTime.now();
      for (final id in list) {
        final fp = id.toString();
        if (records.containsKey(fp)) continue;
        records[fp] = AlertLifecycleRecord(
          fingerprint: fp,
          state: OperationalAlertState.archived,
          firstSeenAt: now,
          lastSeenAt: now,
          occurrenceCount: 1,
        );
      }
      await saveRecords(records);
    } catch (_) {}
  }
}