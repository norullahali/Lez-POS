import '../../../core/database/app_database.dart' as drift;

class ExpenseCategory {
  const ExpenseCategory({
    this.id,
    required this.name,
    this.description = '',
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String name;
  final String description;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ExpenseCategory.fromDrift(drift.ExpenseCategory row) {
    return ExpenseCategory(
      id: row.id,
      name: row.name,
      description: row.description,
      isActive: row.isActive,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  ExpenseCategory copyWith({
    int? id,
    String? name,
    String? description,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExpenseCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
