// lib/core/database/daos/products_dao.dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products_table.dart';
import '../tables/categories_table.dart';
import '../tables/suppliers_table.dart';

part 'products_dao.g.dart';

// Joined product with category and supplier info
class ProductWithDetails {
  final Product product;
  final Category? category;
  final Supplier? supplier;
  final double currentStock;

  const ProductWithDetails({
    required this.product,
    this.category,
    this.supplier,
    required this.currentStock,
  });
}

@DriftAccessor(tables: [Products, Categories, Suppliers])
class ProductsDao extends DatabaseAccessor<AppDatabase> with _$ProductsDaoMixin {
  ProductsDao(super.db);

  // Get all active products
  Future<List<Product>> getAllProducts() =>
      (select(products)..where((p) => p.isActive.equals(true))
        ..orderBy([(p) => OrderingTerm.asc(p.name)]))
          .get();

  // Watch all active products
  Stream<List<Product>> watchAllProducts() =>
      (select(products)..where((p) => p.isActive.equals(true))
        ..orderBy([(p) => OrderingTerm.asc(p.name)]))
          .watch();

  // Get products with limit and offset for lazy loading
  Future<List<Product>> getProductsLimit(int limit, {int offset = 0}) =>
      (select(products)
        ..where((p) => p.isActive.equals(true))
        // Order by recently updated to prioritize active products
        ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)])
        ..limit(limit, offset: offset))
          .get();

  // Search by name or barcode
  Future<List<Product>> searchProducts(String query) =>
      (select(products)
        ..where((p) =>
            (p.name.like('%$query%') | p.barcode.like('%$query%')) &
            p.isActive.equals(true))
        ..limit(30))
          .get();

  // Find by exact barcode (indexed - fast POS lookup)
  Future<Product?> findByBarcode(String barcode) =>
      (select(products)
        ..where((p) => p.barcode.equals(barcode) & p.isActive.equals(true)))
          .getSingleOrNull();

  // Get products by category
  Future<List<Product>> getProductsByCategory(int categoryId) =>
      (select(products)
        ..where((p) =>
            p.categoryId.equals(categoryId) & p.isActive.equals(true)))
          .get();

  Future<Product?> getProductById(int id) =>
      (select(products)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<int> insertProduct(ProductsCompanion entry) =>
      into(products).insert(entry);

  Future<bool> updateProduct(ProductsCompanion entry) =>
      update(products).replace(entry);

  Future<int> toggleProductActive(int id, bool isActive) =>
      (update(products)..where((p) => p.id.equals(id)))
          .write(ProductsCompanion(isActive: Value(isActive)));
}
