import 'package:drift/drift.dart';

class ExpenseCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get description => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  List<Index> get indexes => [
        Index(
          'expense_categories_active_idx',
          'CREATE INDEX IF NOT EXISTS expense_categories_active_idx ON expense_categories (is_active)',
        ),
      ];
}