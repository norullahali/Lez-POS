// lib/features/returns/models/customer_return_history_models.dart

/// Read-only settlement snapshot for return-linked refund UX (Phase C Step 2.7C).
class ReturnRefundableSnapshot {
  const ReturnRefundableSnapshot({
    required this.returnId,
    required this.customerId,
    required this.originalInvoiceId,
    required this.creditCap,
    required this.settledAmount,
    required this.remainingRefundable,
  });

  final int returnId;
  final int customerId;
  final int originalInvoiceId;
  final double creditCap;
  final double settledAmount;
  final double remainingRefundable;
}

class CustomerReturnDetailLine {
  final int id;
  final int productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double total;

  const CustomerReturnDetailLine({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });
}

class CustomerReturnDetail {
  final int id;
  final String returnNumber;
  final DateTime returnDate;
  final double total;
  final String reason;
  final String notes;
  final int? originalInvoiceId;
  final String? saleInvoiceNumber;
  final int? customerId;
  final String? customerName;
  final List<CustomerReturnDetailLine> lines;

  const CustomerReturnDetail({
    required this.id,
    required this.returnNumber,
    required this.returnDate,
    required this.total,
    required this.reason,
    required this.notes,
    required this.originalInvoiceId,
    required this.saleInvoiceNumber,
    required this.customerId,
    required this.customerName,
    required this.lines,
  });

  bool get isInvoiceLinked => originalInvoiceId != null;

  bool get isRefundLinkEligible =>
      isInvoiceLinked && customerId != null && customerId != 1;

  String get displayReturnNumber =>
      returnNumber.isNotEmpty ? returnNumber : '#$id';

  String get displaySaleInvoice {
    if (saleInvoiceNumber != null && saleInvoiceNumber!.isNotEmpty) {
      return saleInvoiceNumber!;
    }
    if (originalInvoiceId != null) return '#$originalInvoiceId';
    return '-';
  }

  String get displayCustomerName =>
      (customerName != null && customerName!.isNotEmpty)
          ? customerName!
          : 'غير محدد';
}
