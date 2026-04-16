// lib/core/database/tables/purchase_items_table.dart
import 'package:drift/drift.dart';
import 'purchase_invoices_table.dart';
import 'products_table.dart';

class PurchaseItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get invoiceId => integer().references(PurchaseInvoices, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitCost => real()();
  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();
  RealColumn get total => real()();
  DateTimeColumn get expiryDate => dateTime().nullable()();

  List<Index> get indexes => [
        Index('pitems_invoice_idx', 'CREATE INDEX IF NOT EXISTS pitems_invoice_idx ON purchase_items (invoice_id)'),
      ];
}
