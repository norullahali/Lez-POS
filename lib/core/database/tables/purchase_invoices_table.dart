// lib/core/database/tables/purchase_invoices_table.dart
import 'package:drift/drift.dart';
import 'suppliers_table.dart';

class PurchaseInvoices extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierId => integer().nullable().references(Suppliers, #id)();
  TextColumn get invoiceNumber => text().withDefault(const Constant(''))();
  DateTimeColumn get purchaseDate => dateTime()();
  RealColumn get subtotal => real().withDefault(const Constant(0.0))();
  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();
  RealColumn get total => real().withDefault(const Constant(0.0))();
  RealColumn get paidAmount => real().withDefault(const Constant(0.0))();
  RealColumn get debtAmount => real().withDefault(const Constant(0.0))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('CONFIRMED'))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get createdByUserId => integer().nullable().customConstraint('NULL REFERENCES users(id)')();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  List<Index> get indexes => [
        Index('purchase_date_idx', 'CREATE INDEX IF NOT EXISTS purchase_date_idx ON purchase_invoices (purchase_date)'),
        Index('purchase_supplier_idx', 'CREATE INDEX IF NOT EXISTS purchase_supplier_idx ON purchase_invoices (supplier_id)'),
      ];
}
