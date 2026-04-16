// lib/core/database/tables/customer_accounts_table.dart
import 'package:drift/drift.dart';
import 'customers_table.dart';

/// One row per customer — stores the cached current balance.
/// Balance is always re-derived from [CustomerTransactions] for accuracy;
/// this row is updated atomically inside every DAO transaction.
class CustomerAccounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId =>
      integer().unique().references(Customers, #id)();
  RealColumn get currentBalance =>
      real().withDefault(const Constant(0.0))();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  List<Index> get indexes => [
        Index(
          'ca_customer_idx',
          'CREATE INDEX IF NOT EXISTS ca_customer_idx ON customer_accounts (customer_id)',
        ),
      ];
}
