// lib/features/categories/repositories/categories_repository.dart
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../models/category_model.dart';

class CategoriesRepository {
  final AppDatabase _db;
  CategoriesRepository(this._db);

  Stream<List<CategoryModel>> watchAll() {
    return _db.categoriesDao.watchAllCategories().map(
          (rows) => rows.map(_toModel).toList(),
        );
  }

  Future<List<CategoryModel>> getAll() async {
    final rows = await _db.categoriesDao.getAllCategories();
    return rows.map(_toModel).toList();
  }

  Future<void> add(CategoryModel model) async {
    await _db.categoriesDao.insertCategory(
      CategoriesCompanion(
        name: Value(model.name),
        description: Value(model.description),
        colorValue: Value(model.colorValue),
        icon: Value(model.icon),
      ),
    );
  }

  Future<void> update(CategoryModel model) async {
    await _db.categoriesDao.updateCategory(
      CategoriesCompanion(
        id: Value(model.id!),
        name: Value(model.name),
        description: Value(model.description),
        colorValue: Value(model.colorValue),
        icon: Value(model.icon),
        isActive: Value(model.isActive),
      ),
    );
  }

  Future<void> delete(int id) async {
    await _db.categoriesDao.deleteCategory(id);
  }

  CategoryModel _toModel(Category row) => CategoryModel(
        id: row.id,
        name: row.name,
        description: row.description,
        colorValue: row.colorValue,
        icon: row.icon,
        isActive: row.isActive,
      );
}
