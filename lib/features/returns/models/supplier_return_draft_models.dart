// lib/features/returns/models/supplier_return_draft_models.dart

class SupplierReturnPurchaseOption {
  final int purchaseInvoiceId;
  final int supplierId;
  final String supplierName;
  final String invoiceNumber;
  final DateTime purchaseDate;
  final double totalAmount;
  final String status;

  const SupplierReturnPurchaseOption({
    required this.purchaseInvoiceId,
    required this.supplierId,
    required this.supplierName,
    required this.invoiceNumber,
    required this.purchaseDate,
    required this.totalAmount,
    required this.status,
  });

  String get displayInvoiceNumber =>
      invoiceNumber.isNotEmpty ? invoiceNumber : '#$purchaseInvoiceId';
}

class SupplierReturnDraftLine {
  final int purchaseItemId;
  final int productId;
  final String productName;
  final double purchasedQty;
  final double alreadyReturnedQty;
  final double returnableQty;
  final double unitCost;
  final double selectedReturnQty;

  const SupplierReturnDraftLine({
    required this.purchaseItemId,
    required this.productId,
    required this.productName,
    required this.purchasedQty,
    required this.alreadyReturnedQty,
    required this.returnableQty,
    required this.unitCost,
    this.selectedReturnQty = 0,
  });

  double get lineDraftTotal => selectedReturnQty * unitCost;

  SupplierReturnDraftLine copyWith({double? selectedReturnQty}) {
    return SupplierReturnDraftLine(
      purchaseItemId: purchaseItemId,
      productId: productId,
      productName: productName,
      purchasedQty: purchasedQty,
      alreadyReturnedQty: alreadyReturnedQty,
      returnableQty: returnableQty,
      unitCost: unitCost,
      selectedReturnQty: selectedReturnQty ?? this.selectedReturnQty,
    );
  }
}

String? validateDraftLineQuantity(
  SupplierReturnDraftLine line,
  double quantity,
) {
  if (quantity < 0) {
    return 'كمية الإرجاع لا يمكن أن تكون سالبة';
  }
  if (quantity > line.returnableQty + 0.0001) {
    return 'تتجاوز الكمية المتاحة للإرجاع (${line.returnableQty.toStringAsFixed(0)})';
  }
  return null;
}
