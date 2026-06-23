import 'package:drift/drift.dart';

class OtherIncomeCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get description => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {name},
      ];

  List<Index> get indexes => [
        Index(
          'other_income_categories_active_idx',
          'CREATE INDEX IF NOT EXISTS other_income_categories_active_idx'
          ' ON other_income_categories (is_active)',
        ),
      ];
}
