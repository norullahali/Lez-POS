// lib/features/purchases/models/purchase_invoice_model.dart

class PurchaseInvoiceModel {
  final int? id;
  final int? supplierId;
  final String? supplierName;
  final String invoiceNumber;
  final DateTime purchaseDate;
  final double subtotal;
  final double discountAmount;
  final double total;
  final double paidAmount;
  final double debtAmount;
  final DateTime? dueDate;
  final String status;
  final String notes;
  final List<PurchaseItemModel> items;

  const PurchaseInvoiceModel({
    this.id,
    this.supplierId,
    this.supplierName,
    required this.invoiceNumber,
    required this.purchaseDate,
    this.subtotal = 0,
    this.discountAmount = 0,
    this.total = 0,
    this.paidAmount = 0,
    this.debtAmount = 0,
    this.dueDate,
    this.status = 'CONFIRMED',
    this.notes = '',
    this.items = const [],
  });
}

class PurchaseItemModel {
  final int? id;
  final int productId;
  final String productName;
  final String productUnit;
  final double quantity;
  final double unitCost;
  final double discountAmount;
  final double total;
  final DateTime? expiryDate;

  const PurchaseItemModel({
    this.id,
    required this.productId,
    required this.productName,
    this.productUnit = 'قطعة',
    required this.quantity,
    required this.unitCost,
    this.discountAmount = 0,
    required this.total,
    this.expiryDate,
  });

  PurchaseItemModel copyWith({
    double? quantity,
    double? unitCost,
    double? discountAmount,
    DateTime? expiryDate,
  }) {
    final qty = quantity ?? this.quantity;
    final cost = unitCost ?? this.unitCost;
    final disc = discountAmount ?? this.discountAmount;
    return PurchaseItemModel(
      id: id,
      productId: productId,
      productName: productName,
      productUnit: productUnit,
      quantity: qty,
      unitCost: cost,
      discountAmount: disc,
      total: (qty * cost) - disc,
      expiryDate: expiryDate ?? this.expiryDate,
    );
  }
}
