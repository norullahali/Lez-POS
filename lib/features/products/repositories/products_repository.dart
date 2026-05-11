// lib/features/products/repositories/products_repository.dart
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/utils/number_parser.dart';
import '../models/product_model.dart';

class ProductsRepository {
  final AppDatabase _db;
  ProductsRepository(this._db);

  Stream<List<ProductModel>> watchAll() {
    return _db.productsDao.watchAllProducts().map(
      (rows) => rows.map((p) => _toModel(p, p.currentStock)).toList(),
    );
  }

  Future<List<ProductModel>> getAll() async {
    final rows = await _db.productsDao.getAllProducts();
    return rows.map((p) => _toModel(p, p.currentStock)).toList();
  }

  Future<List<ProductModel>> getLimit(int limit, {int offset = 0}) async {
    final rows = await _db.productsDao.getProductsLimit(limit, offset: offset);
    return rows.map((p) => _toModel(p, p.currentStock)).toList();
  }

  Future<List<ProductModel>> search(String query) async {
    // Normalize digits so Arabic '٤٥٦' and English '456' return the same results.
    final rows = await _db.productsDao.searchProducts(query.normalizeBarcode());
    return rows.map((p) => _toModel(p, p.currentStock)).toList();
  }

  Future<ProductModel?> findByBarcode(String barcode) async {
    // Normalize before DB lookup so scanners using Arabic digits still match.
    final product = await _db.productsDao.findByBarcode(barcode.trim().normalizeBarcode());
    if (product == null) return null;
    return _toModel(product, product.currentStock);
  }

  Future<List<ProductModel>> getByCategory(int categoryId) async {
    final rows = await _db.productsDao.getProductsByCategory(categoryId);
    return rows.map((p) => _toModel(p, p.currentStock)).toList();
  }

  Future<ProductModel?> getProductById(int id) async {
    final product = await _db.productsDao.getProductById(id);
    if (product == null) return null;
    return _toModel(product, product.currentStock);
  }

  Future<void> add(ProductModel model) async {
    await _db.productsDao.insertProduct(
      ProductsCompanion(
        name: Value(model.name),
        barcode: Value(model.barcode.normalizeBarcode()),
        categoryId: Value(model.categoryId),
        supplierId: Value(model.supplierId),
        costPrice: Value(model.costPrice),
        sellPrice: Value(model.sellPrice),
        wholesalePrice: Value(model.wholesalePrice),
        unit: Value(model.unit),
        minStock: Value(model.minStock),
        trackExpiry: Value(model.trackExpiry),
      ),
    );
  }

  Future<void> update(ProductModel model) async {
    await _db.productsDao.updateProduct(
      ProductsCompanion(
        id: Value(model.id!),
        name: Value(model.name),
        barcode: Value(model.barcode.normalizeBarcode()),
        categoryId: Value(model.categoryId),
        supplierId: Value(model.supplierId),
        costPrice: Value(model.costPrice),
        sellPrice: Value(model.sellPrice),
        wholesalePrice: Value(model.wholesalePrice),
        unit: Value(model.unit),
        minStock: Value(model.minStock),
        trackExpiry: Value(model.trackExpiry),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> toggle(int id, bool isActive) async {
    await _db.productsDao.toggleProductActive(id, isActive);
  }

  ProductModel _toModel(Product row, double stock) => ProductModel(
        id: row.id,
        name: row.name,
        barcode: row.barcode,
        categoryId: row.categoryId,
        supplierId: row.supplierId,
        costPrice: row.costPrice,
        sellPrice: row.sellPrice,
        wholesalePrice: row.wholesalePrice,
        unit: row.unit,
        minStock: row.minStock,
        trackExpiry: row.trackExpiry,
        isActive: row.isActive,
        currentStock: stock,
      );
}
