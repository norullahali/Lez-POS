// lib/features/products/repositories/products_repository.dart
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../models/product_model.dart';

class ProductsRepository {
  final AppDatabase _db;
  ProductsRepository(this._db);

  Stream<List<ProductModel>> watchAll() {
    return _db.productsDao.watchAllProducts().asyncMap((rows) async {
      final stocks = await _db.stockDao.getAllStocks();
      return rows.map((p) => _toModel(p, stocks[p.id] ?? 0)).toList();
    });
  }

  Future<List<ProductModel>> getAll() async {
    final rows = await _db.productsDao.getAllProducts();
    final stocks = await _db.stockDao.getAllStocks();
    return rows.map((p) => _toModel(p, stocks[p.id] ?? 0)).toList();
  }

  Future<List<ProductModel>> getLimit(int limit, {int offset = 0}) async {
    final rows = await _db.productsDao.getProductsLimit(limit, offset: offset);
    final stocks = await _db.stockDao.getAllStocks();
    return rows.map((p) => _toModel(p, stocks[p.id] ?? 0)).toList();
  }

  Future<List<ProductModel>> search(String query) async {
    final rows = await _db.productsDao.searchProducts(query);
    final stocks = await _db.stockDao.getAllStocks();
    return rows.map((p) => _toModel(p, stocks[p.id] ?? 0)).toList();
  }

  Future<ProductModel?> findByBarcode(String barcode) async {
    final product = await _db.productsDao.findByBarcode(barcode);
    if (product == null) return null;
    final stock = await _db.stockDao.getStock(product.id);
    return _toModel(product, stock);
  }

  Future<List<ProductModel>> getByCategory(int categoryId) async {
    final rows = await _db.productsDao.getProductsByCategory(categoryId);
    final stocks = await _db.stockDao.getAllStocks();
    return rows.map((p) => _toModel(p, stocks[p.id] ?? 0)).toList();
  }

  Future<ProductModel?> getProductById(int id) async {
    final product = await _db.productsDao.getProductById(id);
    if (product == null) return null;
    final stock = await _db.stockDao.getStock(id);
    return _toModel(product, stock);
  }

  Future<void> add(ProductModel model) async {
    await _db.productsDao.insertProduct(
      ProductsCompanion(
        name: Value(model.name),
        barcode: Value(model.barcode),
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
        barcode: Value(model.barcode),
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
