import 'package:drift/drift.dart';
import 'suppliers_table.dart';

class SupplierTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierId => integer().references(Suppliers, #id)();
  
  /// Type of transaction: 'PURCHASE', 'PAYMENT', 'ADJUSTMENT'
  TextColumn get type => text()();
  
  /// Can be PurchaseInvoice ID or Payment receipt ID
  IntColumn get referenceId => integer().nullable()();
  
  /// Positive amount INCREASES the debt (PURCHASE).
  /// Negative amount DECREASES the debt (PAYMENT).
  RealColumn get amount => real()();
  
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  
  TextColumn get note => text().withDefault(const Constant(''))();

  List<Index> get indexes => [
    Index('supp_tx_supplier_time_idx', 'CREATE INDEX IF NOT EXISTS supp_tx_supplier_time_idx ON supplier_transactions (supplier_id, created_at)'),
  ];
}
