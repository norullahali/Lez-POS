// lib/features/products/models/product_model.dart

class ProductModel {
  final int? id;
  final String name;
  final String barcode;
  final int? categoryId;
  final String? categoryName;
  final int? supplierId;
  final String? supplierName;
  final double costPrice;
  final double sellPrice;
  final double wholesalePrice;
  final String unit;
  final double minStock;
  final bool trackExpiry;
  final bool isActive;
  final double currentStock;

  const ProductModel({
    this.id,
    required this.name,
    this.barcode = '',
    this.categoryId,
    this.categoryName,
    this.supplierId,
    this.supplierName,
    this.costPrice = 0,
    this.sellPrice = 0,
    this.wholesalePrice = 0,
    this.unit = 'قطعة',
    this.minStock = 0,
    this.trackExpiry = false,
    this.isActive = true,
    this.currentStock = 0,
  });

  bool get isLowStock => currentStock <= minStock;

  ProductModel copyWith({
    int? id,
    String? name,
    String? barcode,
    int? categoryId,
    String? categoryName,
    int? supplierId,
    String? supplierName,
    double? costPrice,
    double? sellPrice,
    double? wholesalePrice,
    String? unit,
    double? minStock,
    bool? trackExpiry,
    bool? isActive,
    double? currentStock,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      costPrice: costPrice ?? this.costPrice,
      sellPrice: sellPrice ?? this.sellPrice,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      unit: unit ?? this.unit,
      minStock: minStock ?? this.minStock,
      trackExpiry: trackExpiry ?? this.trackExpiry,
      isActive: isActive ?? this.isActive,
      currentStock: currentStock ?? this.currentStock,
    );
  }
}
