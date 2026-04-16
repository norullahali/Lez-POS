// lib/core/database/tables/customer_transactions_table.dart
import 'package:drift/drift.dart';
import 'customers_table.dart';

/// Immutable ledger — never deleted, only appended.
/// type: 'SALE' | 'PAYMENT' | 'ADJUSTMENT' | 'RETURN'
class CustomerTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer().references(Customers, #id)();

  /// 'SALE' | 'PAYMENT' | 'ADJUSTMENT' | 'RETURN'
  TextColumn get type => text()();

  /// +amount for SALE (balance increases), -amount for PAYMENT (balance decreases)
  /// sign for ADJUSTMENT is explicit.
  RealColumn get amount => real()();

  /// Invoice ID for SALE, or payment record id for PAYMENT (nullable for ADJUSTMENT)
  IntColumn get referenceId => integer().nullable()();

  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  List<Index> get indexes => [
        Index(
          'ct_customer_date_idx',
          'CREATE INDEX IF NOT EXISTS ct_customer_date_idx ON customer_transactions (customer_id, created_at)',
        ),
        Index(
          'ct_type_idx',
          'CREATE INDEX IF NOT EXISTS ct_type_idx ON customer_transactions (type)',
        ),
      ];
}
