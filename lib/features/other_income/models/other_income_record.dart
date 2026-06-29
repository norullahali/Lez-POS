import '../../../core/database/app_database.dart' as drift;

// Sentinel distinguishes 'not provided' from 'explicitly null' in copyWith.
// Prevents sessionId clearing ambiguity (mirrors ExpensesFilter._sentinel pattern).
const _sentinel = Object();

class OtherIncomeRecord {
  const OtherIncomeRecord({
    this.id,
    required this.categoryId,
    required this.amount,
    required this.incomeDate,
    required this.receivedAt,
    this.notes = '',
    this.sessionId,
    required this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.isVoided = false,
  });

  final int? id;
  final int categoryId;
  final double amount;
  final DateTime incomeDate;
  final DateTime receivedAt;
  final String notes;
  final int? sessionId;
  final int createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isVoided;

  factory OtherIncomeRecord.fromDrift(drift.OtherIncomeRecord row) {
    return OtherIncomeRecord(
      id: row.id,
      categoryId: row.categoryId,
      amount: row.amount,
      incomeDate: row.incomeDate,
      receivedAt: row.receivedAt,
      notes: row.notes,
      sessionId: row.sessionId,
      createdBy: row.createdBy,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      isVoided: row.isVoided,
    );
  }

  OtherIncomeRecord copyWith({
    int? id,
    int? categoryId,
    double? amount,
    DateTime? incomeDate,
    DateTime? receivedAt,
    String? notes,
    Object? sessionId = _sentinel,
    int? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isVoided,
  }) {
    return OtherIncomeRecord(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      amount: amount ?? this.amount,
      incomeDate: incomeDate ?? this.incomeDate,
      receivedAt: receivedAt ?? this.receivedAt,
      notes: notes ?? this.notes,
      sessionId: sessionId == _sentinel ? this.sessionId : sessionId as int?,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isVoided: isVoided ?? this.isVoided,
    );
  }
}
