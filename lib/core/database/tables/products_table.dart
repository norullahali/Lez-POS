// lib/core/database/tables/products_table.dart
import 'package:drift/drift.dart';
import 'categories_table.dart';
import 'suppliers_table.dart';

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get barcode => text().withDefault(const Constant(''))();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  IntColumn get supplierId => integer().nullable().references(Suppliers, #id)();
  RealColumn get costPrice => real().withDefault(const Constant(0.0))();
  RealColumn get sellPrice => real().withDefault(const Constant(0.0))();
  RealColumn get wholesalePrice => real().withDefault(const Constant(0.0))();
  TextColumn get unit => text().withDefault(const Constant('قطعة'))();
  RealColumn get minStock => real().withDefault(const Constant(0.0))();
  BoolColumn get trackExpiry => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {barcode},
      ];

  List<Index> get indexes => [
        Index('products_barcode_idx', 'CREATE INDEX IF NOT EXISTS products_barcode_idx ON products (barcode)'),
        Index('products_category_idx', 'CREATE INDEX IF NOT EXISTS products_category_idx ON products (category_id)'),
        Index('products_name_idx', 'CREATE INDEX IF NOT EXISTS products_name_idx ON products (name)'),
      ];
}
