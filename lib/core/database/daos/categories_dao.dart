// lib/core/database/daos/categories_dao.dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/categories_table.dart';

part 'categories_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoriesDao extends DatabaseAccessor<AppDatabase> with _$CategoriesDaoMixin {
  CategoriesDao(super.db);

  // Read all active categories
  Future<List<Category>> getAllCategories() =>
      (select(categories)..where((c) => c.isActive.equals(true))
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .get();

  // Watch all active categories (live stream)
  Stream<List<Category>> watchAllCategories() =>
      (select(categories)..where((c) => c.isActive.equals(true))
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .watch();

  // Get single category by id
  Future<Category?> getCategoryById(int id) =>
      (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();

  // Insert
  Future<int> insertCategory(CategoriesCompanion entry) =>
      into(categories).insert(entry);

  // Update
  Future<bool> updateCategory(CategoriesCompanion entry) =>
      update(categories).replace(entry);

  // Soft delete
  Future<int> deactivateCategory(int id) =>
      (update(categories)..where((c) => c.id.equals(id)))
          .write(const CategoriesCompanion(isActive: Value(false)));

  // Hard delete
  Future<int> deleteCategory(int id) =>
      (delete(categories)..where((c) => c.id.equals(id))).go();
}
