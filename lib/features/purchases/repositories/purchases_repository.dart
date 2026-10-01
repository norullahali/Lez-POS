// lib/features/purchases/repositories/purchases_repository.dart
import '../../../core/database/app_database.dart';
import '../../../core/services/purchase_save_result.dart';
import '../../../core/services/purchase_save_service.dart';
import '../models/purchase_invoice_model.dart';

class PurchasesRepository {
  final AppDatabase _db;
  final PurchaseSaveService _purchaseSaveService;

  PurchasesRepository(this._db, this._purchaseSaveService);

  Future<List<PurchaseInvoiceModel>> getAll() async {
    final invoices = await _db.purchasesDao.getAllInvoices();
    final result = <PurchaseInvoiceModel>[];
    for (final inv in invoices) {
      Supplier? supplier;
      if (inv.supplierId != null) {
        supplier = await _db.suppliersDao.getSupplierById(inv.supplierId!);
      }
      result.add(PurchaseInvoiceModel(
        id: inv.id,
        supplierId: inv.supplierId,
        supplierName: supplier?.name,
        invoiceNumber: inv.invoiceNumber,
        purchaseDate: inv.purchaseDate,
        subtotal: inv.subtotal,
        discountAmount: inv.discountAmount,
        total: inv.total,
        paidAmount: inv.paidAmount,
        debtAmount: inv.debtAmount,
        dueDate: inv.dueDate,
        status: inv.status,
        notes: inv.notes,
      ));
    }
    return result;
  }

  Stream<List<PurchaseInvoiceModel>> watchAll() {
    return _db.purchasesDao.watchAllInvoices().asyncMap((invoices) async {
      final result = <PurchaseInvoiceModel>[];
      for (final inv in invoices) {
        Supplier? supplier;
        if (inv.supplierId != null) {
          supplier = await _db.suppliersDao.getSupplierById(inv.supplierId!);
        }
        result.add(PurchaseInvoiceModel(
          id: inv.id,
          supplierId: inv.supplierId,
          supplierName: supplier?.name,
          invoiceNumber: inv.invoiceNumber,
          purchaseDate: inv.purchaseDate,
          subtotal: inv.subtotal,
          discountAmount: inv.discountAmount,
          total: inv.total,
          paidAmount: inv.paidAmount,
          debtAmount: inv.debtAmount,
          dueDate: inv.dueDate,
          status: inv.status,
          notes: inv.notes,
        ));
      }
      return result;
    });
  }

  Future<PurchaseSaveResult> save(
    PurchaseInvoiceModel invoice,
    int? userId, {
    required String idempotencyKey,
    required String fingerprintHash,
  }) {
    return _purchaseSaveService.processSave(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fingerprintHash,
      supplierId: invoice.supplierId,
      operatorInvoiceNumber: invoice.invoiceNumber,
      purchaseDate: invoice.purchaseDate,
      invoiceDiscount: invoice.discountAmount,
      total: invoice.total,
      paidAmount: invoice.paidAmount,
      dueDate: invoice.dueDate,
      notes: invoice.notes,
      items: invoice.items
          .map((item) => {
                'productId': item.productId,
                'qty': item.quantity,
                'cost': item.unitCost,
                'discount': item.discountAmount,
                'expiryDate': item.expiryDate,
              })
          .toList(),
      createdByUserId: userId,
    );
  }

  Future<void> delete(int id) => _db.purchasesDao.deleteInvoice(id);
}
