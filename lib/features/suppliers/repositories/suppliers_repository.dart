// lib/features/suppliers/repositories/suppliers_repository.dart
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../models/supplier_model.dart';
import '../../purchases/models/purchase_invoice_model.dart';

class SuppliersRepository {
  final AppDatabase _db;
  SuppliersRepository(this._db);

  Stream<List<SupplierModel>> watchAll() {
    return _db.suppliersDao.watchAllSuppliers().map(
          (rows) => rows.map(_toModel).toList(),
        );
  }

  Future<List<SupplierModel>> getAll() async {
    final rows = await _db.suppliersDao.getAllSuppliers();
    return rows.map(_toModel).toList();
  }

  Future<List<SupplierModel>> search(String query) async {
    final rows = await _db.suppliersDao.searchSuppliers(query);
    return rows.map(_toModel).toList();
  }

  Future<SupplierModel?> getById(int id) async {
    final row = await _db.suppliersDao.getSupplierById(id);
    return row != null ? _toModel(row) : null;
  }

  Future<Map<String, dynamic>> getStats(int supplierId) async {
    final invoices = await _db.purchasesDao.getAllInvoices(); 
    final supplierInvoices = invoices.where((i) => i.supplierId == supplierId).toList();
    
    final invoiceCount = supplierInvoices.length;
    final totalPurchased = supplierInvoices.fold(0.0, (s, i) => s + i.total);
    final lastPurchaseDate = supplierInvoices.isNotEmpty 
        ? supplierInvoices.map((i) => i.purchaseDate).reduce((a, b) => a.isAfter(b) ? a : b)
        : null;

    return {
      'totalPurchased': totalPurchased,
      'invoiceCount': invoiceCount,
      'lastPurchaseDate': lastPurchaseDate,
    };
  }

  Future<List<PurchaseInvoiceModel>> getInvoices(int supplierId) async {
    final invoices = await _db.purchasesDao.getAllInvoices();
    final supplierInvoices = invoices.where((i) => i.supplierId == supplierId).toList();
    final result = <PurchaseInvoiceModel>[];
    for (final inv in supplierInvoices) {
       result.add(PurchaseInvoiceModel(
         id: inv.id,
         invoiceNumber: inv.invoiceNumber,
         supplierId: inv.supplierId,
         purchaseDate: inv.purchaseDate,
         total: inv.total,
         paidAmount: inv.paidAmount,
         debtAmount: inv.debtAmount,
         dueDate: inv.dueDate,
         status: inv.status,
       ));
    }
    return result;
  }

  Future<void> add(SupplierModel model) async {
    await _db.suppliersDao.insertSupplier(
      SuppliersCompanion(
        name: Value(model.name),
        phone: Value(model.phone),
        address: Value(model.address),
        notes: Value(model.notes),
      ),
    );
  }

  Future<void> update(SupplierModel model) async {
    await _db.suppliersDao.updateSupplier(
      SuppliersCompanion(
        id: Value(model.id!),
        name: Value(model.name),
        phone: Value(model.phone),
        address: Value(model.address),
        notes: Value(model.notes),
        isActive: Value(model.isActive),
      ),
    );
  }

  Future<void> delete(int id) async {
    await _db.suppliersDao.deleteSupplier(id);
  }

  SupplierModel _toModel(Supplier row) => SupplierModel(
        id: row.id,
        name: row.name,
        phone: row.phone,
        address: row.address,
        notes: row.notes,
        isActive: row.isActive,
      );
}
