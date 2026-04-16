import 'package:drift/drift.dart';
import 'pos_sessions_table.dart';
import 'customers_table.dart';

class SalesInvoices extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().nullable().references(PosSessions, #id)();
  IntColumn get customerId => integer().nullable().references(Customers, #id)();
  TextColumn get invoiceNumber => text()();
  DateTimeColumn get saleDate => dateTime().withDefault(currentDateAndTime)();
  RealColumn get subtotal => real().withDefault(const Constant(0.0))();
  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();
  RealColumn get total => real().withDefault(const Constant(0.0))();
  TextColumn get paymentMethod => text().withDefault(const Constant('CASH'))();
  RealColumn get cashPaid => real().withDefault(const Constant(0.0))();
  RealColumn get cardPaid => real().withDefault(const Constant(0.0))();
  RealColumn get changeAmount => real().withDefault(const Constant(0.0))();
  /// Amount charged to the customer's account (آجل / دين)
  RealColumn get debtAmount => real().withDefault(const Constant(0.0))();
  IntColumn get createdByUserId => integer().nullable().customConstraint('NULL REFERENCES users(id)')();
  IntColumn get processedByUserId => integer().nullable().customConstraint('NULL REFERENCES users(id)')();
  TextColumn get notes => text().withDefault(const Constant(''))();

  List<Index> get indexes => [
        Index('sales_date_idx', 'CREATE INDEX IF NOT EXISTS sales_date_idx ON sales_invoices (sale_date)'),
        Index('sales_number_idx', 'CREATE INDEX IF NOT EXISTS sales_number_idx ON sales_invoices (invoice_number)'),
      ];
}

