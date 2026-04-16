// lib/features/purchases/repositories/purchases_repository.dart
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../models/purchase_invoice_model.dart';

class PurchasesRepository {
  final AppDatabase _db;
  PurchasesRepository(this._db);

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

  Future<int> save(PurchaseInvoiceModel invoice, int? userId) async {
    return _db.purchasesDao.savePurchaseInvoice(
      header: PurchaseInvoicesCompanion(
        supplierId: Value(invoice.supplierId),
        invoiceNumber: Value(invoice.invoiceNumber),
        purchaseDate: Value(invoice.purchaseDate),
        subtotal: Value(invoice.subtotal),
        discountAmount: Value(invoice.discountAmount),
        total: Value(invoice.total),
        paidAmount: Value(invoice.paidAmount),
        debtAmount: Value(invoice.debtAmount),
        dueDate: Value(invoice.dueDate),
        status: Value(invoice.status),
        notes: Value(invoice.notes),
        createdByUserId: Value(userId),
      ),
      items: invoice.items.map((item) => {
        'productId': item.productId,
        'qty': item.quantity,
        'cost': item.unitCost,
        'discount': item.discountAmount,
        'expiryDate': item.expiryDate,
      }).toList(),
    );
  }

  Future<void> delete(int id) => _db.purchasesDao.deleteInvoice(id);
}
