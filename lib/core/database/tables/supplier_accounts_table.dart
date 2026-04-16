import 'package:drift/drift.dart';
import 'suppliers_table.dart';

class SupplierAccounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierId => integer().references(Suppliers, #id)();
  
  /// A positive balance means we OWE the supplier money.
  /// A negative balance means the supplier owes us (e.g., overpayment).
  RealColumn get currentBalance => real().withDefault(const Constant(0.0))();
  
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {supplierId},
  ];
}
