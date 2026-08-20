// lib/features/returns/repositories/customer_return_read_repository.dart

import '../../../core/database/app_database.dart';
import '../models/customer_return_history_models.dart';

class CustomerReturnReadRepository {
  CustomerReturnReadRepository(this._db);

  final AppDatabase _db;

  /// Read-only detail for a persisted customer return with invoice/customer resolution.
  Future<CustomerReturnDetail?> getCustomerReturnDetail(int returnId) async {
    final header = await _db.returnsDao.getCustomerReturnById(returnId);
    if (header == null) return null;

    final items = await _db.returnsDao.getCustomerReturnItems(returnId);

    String? saleInvoiceNumber;
    int? customerId;
    String? customerName;

    final invoiceId = header.originalInvoiceId;
    if (invoiceId != null) {
      final invoice = await _db.salesDao.getInvoiceById(invoiceId);
      saleInvoiceNumber = invoice?.invoiceNumber;
      customerId = invoice?.customerId;
      if (customerId != null && customerId != 1) {
        final customer = await _db.customersDao.getCustomerById(customerId);
        customerName = customer?.name;
      }
    }

    return CustomerReturnDetail(
      id: header.id,
      returnNumber: header.returnNumber,
      returnDate: header.returnDate,
      total: header.total,
      reason: header.reason,
      notes: header.notes,
      originalInvoiceId: header.originalInvoiceId,
      saleInvoiceNumber: saleInvoiceNumber,
      customerId: customerId,
      customerName: customerName,
      lines: items
          .map(
            (item) => CustomerReturnDetailLine(
              id: item.id,
              productId: item.productId,
              productName: item.productName,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              total: item.total,
            ),
          )
          .toList(),
    );
  }
}
