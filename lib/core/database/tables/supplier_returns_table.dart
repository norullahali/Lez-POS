// lib/core/database/tables/supplier_returns_table.dart
import 'package:drift/drift.dart';
import 'suppliers_table.dart';
import 'purchase_invoices_table.dart';

class SupplierReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierId => integer().nullable().references(Suppliers, #id)();
  IntColumn get purchaseInvoiceId => integer().nullable().references(PurchaseInvoices, #id)();
  TextColumn get returnNumber => text()();
  DateTimeColumn get returnDate => dateTime().withDefault(currentDateAndTime)();
  RealColumn get total => real().withDefault(const Constant(0.0))();
  TextColumn get reason => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
}

class SupplierReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId => integer().references(SupplierReturns, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer()();
  TextColumn get productName => text()();
  RealColumn get quantity => real()();
  RealColumn get unitCost => real()();
  RealColumn get total => real()();
}
