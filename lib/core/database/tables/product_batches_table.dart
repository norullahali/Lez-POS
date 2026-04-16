// lib/core/database/tables/product_batches_table.dart
import 'package:drift/drift.dart';
import 'products_table.dart';

class ProductBatches extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  DateTimeColumn get expiryDate => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get notes => text().withDefault(const Constant(''))();

  List<Index> get indexes => [
        Index('batches_product_idx', 'CREATE INDEX IF NOT EXISTS batches_product_idx ON product_batches (product_id)'),
        Index('batches_expiry_idx', 'CREATE INDEX IF NOT EXISTS batches_expiry_idx ON product_batches (expiry_date)'),
      ];
}
