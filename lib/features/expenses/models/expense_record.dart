import '../../../core/database/app_database.dart' as drift;

class ExpenseRecord {
  const ExpenseRecord({
    this.id,
    required this.categoryId,
    required this.amount,
    required this.expenseDate,
    required this.paidAt,
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
  final DateTime expenseDate;
  final DateTime paidAt;
  final String notes;
  final int? sessionId;
  final int createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isVoided;

  factory ExpenseRecord.fromDrift(drift.ExpenseRecord row) {
    return ExpenseRecord(
      id: row.id,
      categoryId: row.categoryId,
      amount: row.amount,
      expenseDate: row.expenseDate,
      paidAt: row.paidAt,
      notes: row.notes,
      sessionId: row.sessionId,
      createdBy: row.createdBy,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      isVoided: row.isVoided,
    );
  }

  ExpenseRecord copyWith({
    int? id,
    int? categoryId,
    double? amount,
    DateTime? expenseDate,
    DateTime? paidAt,
    String? notes,
    int? sessionId,
    int? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isVoided,
  }) {
    return ExpenseRecord(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      amount: amount ?? this.amount,
      expenseDate: expenseDate ?? this.expenseDate,
      paidAt: paidAt ?? this.paidAt,
      notes: notes ?? this.notes,
      sessionId: sessionId ?? this.sessionId,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isVoided: isVoided ?? this.isVoided,
    );
  }
}
