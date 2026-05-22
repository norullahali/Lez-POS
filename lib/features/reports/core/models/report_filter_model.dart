// lib/features/reports/core/models/report_filter_model.dart
import 'package:flutter/material.dart';
import 'report_date_preset.dart';

/// Unified report filter state shared across report screens.
class ReportFilterModel {
  const ReportFilterModel({
    this.preset = ReportDatePreset.thisMonth,
    this.singleDate,
    this.range,
    this.year,
    this.cashierId,
    this.categoryId,
    this.supplierId,
    this.customerId,
    this.paymentMethod,
    this.branchId,
  });

  final ReportDatePreset preset;
  final DateTime? singleDate;
  final DateTimeRange? range;
  final int? year;

  // Future-ready optional dimensions (unused in current reports).
  final int? cashierId;
  final int? categoryId;
  final int? supplierId;
  final int? customerId;
  final String? paymentMethod;
  final int? branchId;

  DateTime resolveSingleDate([DateTime? now]) {
    final n = _dateOnly(now ?? DateTime.now());
    if (singleDate != null) return _dateOnly(singleDate!);
    return switch (preset) {
      ReportDatePreset.today => n,
      ReportDatePreset.yesterday => n.subtract(const Duration(days: 1)),
      _ => n,
    };
  }

  DateTimeRange resolveRange([DateTime? now]) {
    if (range != null) return range!;
    final n = _dateOnly(now ?? DateTime.now());
    return switch (preset) {
      ReportDatePreset.today => DateTimeRange(start: n, end: n),
      ReportDatePreset.yesterday => DateTimeRange(
          start: n.subtract(const Duration(days: 1)),
          end: n.subtract(const Duration(days: 1)),
        ),
      ReportDatePreset.thisWeek => DateTimeRange(
          start: n.subtract(Duration(days: n.weekday - 1)),
          end: n,
        ),
      ReportDatePreset.thisMonth => DateTimeRange(
          start: DateTime(n.year, n.month, 1),
          end: n,
        ),
      ReportDatePreset.thisYear => DateTimeRange(
          start: DateTime(n.year, 1, 1),
          end: n,
        ),
      ReportDatePreset.custom => range ?? DateTimeRange(
          start: n.subtract(const Duration(days: 30)),
          end: n,
        ),
    };
  }

  int resolveYear([DateTime? now]) => year ?? (now ?? DateTime.now()).year;

  String summaryAr([DateTime? now]) {
    if (singleDate != null && preset != ReportDatePreset.custom) {
      return '${preset.labelAr}: ${_fmt(singleDate!)}';
    }
    if (year != null && preset == ReportDatePreset.thisYear) {
      return 'سنة $year';
    }
    final r = resolveRange(now);
    return '${preset.labelAr}: ${_fmt(r.start)} — ${_fmt(r.end)}';
  }

  ReportFilterModel copyWith({
    ReportDatePreset? preset,
    DateTime? singleDate,
    DateTimeRange? range,
    int? year,
    int? cashierId,
    int? categoryId,
    int? supplierId,
    int? customerId,
    String? paymentMethod,
    int? branchId,
    bool clearSingleDate = false,
    bool clearRange = false,
    bool clearYear = false,
  }) {
    return ReportFilterModel(
      preset: preset ?? this.preset,
      singleDate: clearSingleDate ? null : (singleDate ?? this.singleDate),
      range: clearRange ? null : (range ?? this.range),
      year: clearYear ? null : (year ?? this.year),
      cashierId: cashierId ?? this.cashierId,
      categoryId: categoryId ?? this.categoryId,
      supplierId: supplierId ?? this.supplierId,
      customerId: customerId ?? this.customerId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      branchId: branchId ?? this.branchId,
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _fmt(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}