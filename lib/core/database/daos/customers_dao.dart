import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/customers_table.dart';
import '../tables/sales_invoices_table.dart';

part 'customers_dao.g.dart';

@DriftAccessor(tables: [Customers, SalesInvoices])
class CustomersDao extends DatabaseAccessor<AppDatabase> with _$CustomersDaoMixin {
  CustomersDao(super.db);

  Stream<List<Customer>> watchAllCustomers() =>
      (select(customers)..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();

  Future<List<Customer>> getAllCustomers() =>
      (select(customers)..orderBy([(c) => OrderingTerm.asc(c.name)])).get();

  Future<Customer?> getCustomerById(int id) =>
      (select(customers)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<int> createCustomer(CustomersCompanion customer) =>
      into(customers).insert(customer);

  Future<bool> updateCustomer(Customer customer) =>
      update(customers).replace(customer);

  Future<List<Customer>> searchCustomers(String query) {
    return (select(customers)
      ..where((c) => c.name.like('%$query%') | c.phone.like('%$query%'))
      ..limit(20)
    ).get();
  }

  Future<Map<String, dynamic>> getCustomerStats(int customerId) async {
    final countExp = salesInvoices.id.count();
    final totalExp = salesInvoices.total.sum();
    final lastPurchaseExp = salesInvoices.saleDate.max();

    final query = selectOnly(salesInvoices)
      ..addColumns([countExp, totalExp, lastPurchaseExp])
      ..where(salesInvoices.customerId.equals(customerId));

    final row = await query.getSingle();
    
    return {
      'totalSpent': row.read(totalExp) ?? 0.0,
      'invoiceCount': row.read(countExp) ?? 0,
      'lastPurchaseDate': row.read(lastPurchaseExp),
    };
  }

  Future<List<SalesInvoice>> getCustomerInvoices(int customerId, {int limit = 20}) {
    return (select(salesInvoices)
      ..where((i) => i.customerId.equals(customerId))
      ..orderBy([(i) => OrderingTerm.desc(i.saleDate)])
      ..limit(limit)
    ).get();
  }

  Future<List<Map<String, dynamic>>> getTopCustomersBySpending() async {
    final result = await customSelect(
      '''
      SELECT c.id, c.name, c.phone, COUNT(s.id) as invoice_count, SUM(s.total) as total_spent
      FROM customers c
      JOIN sales_invoices s ON s.customer_id = c.id
      WHERE c.id != 1
      GROUP BY c.id
      ORDER BY total_spent DESC
      LIMIT 50
      ''',
      readsFrom: {customers, salesInvoices},
    ).get();
    
    return result.map((r) => r.data).toList();
  }
}
