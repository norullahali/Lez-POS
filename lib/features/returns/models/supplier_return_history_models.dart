// lib/features/returns/models/supplier_return_history_models.dart

class SupplierReturnListItem {
  final int id;
  final String returnNumber;
  final DateTime returnDate;
  final double total;
  final String reason;
  final String notes;
  final int? supplierId;
  final String? supplierName;
  final int? purchaseInvoiceId;
  final String? purchaseInvoiceNumber;
  final int lineCount;

  const SupplierReturnListItem({
    required this.id,
    required this.returnNumber,
    required this.returnDate,
    required this.total,
    required this.reason,
    required this.notes,
    required this.supplierId,
    required this.supplierName,
    required this.purchaseInvoiceId,
    required this.purchaseInvoiceNumber,
    required this.lineCount,
  });

  bool get isPurchaseLinked => purchaseInvoiceId != null;

  String get displayReturnNumber =>
      returnNumber.isNotEmpty ? returnNumber : '#$id';

  String get displayPurchaseInvoice {
    if (purchaseInvoiceNumber != null && purchaseInvoiceNumber!.isNotEmpty) {
      return purchaseInvoiceNumber!;
    }
    if (purchaseInvoiceId != null) return '#$purchaseInvoiceId';
    return '-';
  }

  String get displaySupplierName =>
      (supplierName != null && supplierName!.isNotEmpty)
          ? supplierName!
          : 'غير محدد';

  String get linkageLabel =>
      isPurchaseLinked ? 'مرتبط بفاتورة شراء' : 'مرتجع يدوي';
}

class SupplierReturnDetailLine {
  final int id;
  final int? purchaseItemId;
  final int productId;
  final String productName;
  final double quantity;
  final double unitCost;
  final double total;

  const SupplierReturnDetailLine({
    required this.id,
    required this.purchaseItemId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    required this.total,
  });
}

class SupplierReturnDetail {
  final int id;
  final String returnNumber;
  final DateTime returnDate;
  final double total;
  final String reason;
  final String notes;
  final int? supplierId;
  final String? supplierName;
  final int? purchaseInvoiceId;
  final String? purchaseInvoiceNumber;
  final List<SupplierReturnDetailLine> lines;

  const SupplierReturnDetail({
    required this.id,
    required this.returnNumber,
    required this.returnDate,
    required this.total,
    required this.reason,
    required this.notes,
    required this.supplierId,
    required this.supplierName,
    required this.purchaseInvoiceId,
    required this.purchaseInvoiceNumber,
    required this.lines,
  });

  String get displayReturnNumber =>
      returnNumber.isNotEmpty ? returnNumber : '#$id';

  String get displayPurchaseInvoice {
    if (purchaseInvoiceNumber != null && purchaseInvoiceNumber!.isNotEmpty) {
      return purchaseInvoiceNumber!;
    }
    if (purchaseInvoiceId != null) return '#$purchaseInvoiceId';
    return '-';
  }

  String get displaySupplierName =>
      (supplierName != null && supplierName!.isNotEmpty)
          ? supplierName!
          : 'غير محدد';
}
