// lib/core/database/tables/sale_items_table.dart
import 'package:drift/drift.dart';
import 'sales_invoices_table.dart';
import 'products_table.dart';

class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get invoiceId => integer().references(SalesInvoices, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get unitCost => real().withDefault(const Constant(0.0))();
  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();
  RealColumn get total => real()();

  List<Index> get indexes => [
        Index('sitems_invoice_idx', 'CREATE INDEX IF NOT EXISTS sitems_invoice_idx ON sale_items (invoice_id)'),
        Index('sitems_product_idx', 'CREATE INDEX IF NOT EXISTS sitems_product_idx ON sale_items (product_id)'),
      ];
}
