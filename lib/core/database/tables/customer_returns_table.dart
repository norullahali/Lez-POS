// lib/core/database/tables/customer_returns_table.dart
import 'package:drift/drift.dart';
import 'sales_invoices_table.dart';

class CustomerReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get originalInvoiceId => integer().nullable().references(SalesInvoices, #id)();
  TextColumn get returnNumber => text()();
  DateTimeColumn get returnDate => dateTime().withDefault(currentDateAndTime)();
  RealColumn get total => real().withDefault(const Constant(0.0))();
  TextColumn get reason => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
}

class CustomerReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId => integer().references(CustomerReturns, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer()();
  TextColumn get productName => text()();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get unitCost => real().withDefault(const Constant(0.0))();
  RealColumn get total => real()();
}
