// lib/features/customers/repositories/customers_repository.dart
import 'package:drift/drift.dart' as drift;
import '../../../core/database/app_database.dart';

class CustomersRepository {
  final AppDatabase _db;
  CustomersRepository(this._db);

  Stream<List<Customer>> watchAll() => _db.customersDao.watchAllCustomers();
  Future<List<Customer>> getAll() => _db.customersDao.getAllCustomers();
  Future<Customer?> getById(int id) => _db.customersDao.getCustomerById(id);
  Future<List<Customer>> search(String query) => _db.customersDao.searchCustomers(query);
  Future<Map<String, dynamic>> getStats(int customerId) => _db.customersDao.getCustomerStats(customerId);
  Future<List<SalesInvoice>> getInvoices(int customerId, {int limit = 20}) => _db.customersDao.getCustomerInvoices(customerId, limit: limit);
  Future<List<Map<String, dynamic>>> getTopCustomers() => _db.customersDao.getTopCustomersBySpending();

  Future<int> save(Customer customer) async {
    if (customer.id == 0) {
      return await _db.customersDao.createCustomer(
        CustomersCompanion.insert(
          name: customer.name,
          phone: customer.phone != null ? drift.Value(customer.phone) : const drift.Value.absent(),
          email: customer.email != null ? drift.Value(customer.email) : const drift.Value.absent(),
          address: customer.address != null ? drift.Value(customer.address) : const drift.Value.absent(),
          notes: customer.notes != null ? drift.Value(customer.notes) : const drift.Value.absent(),
        ),
      );
    } else {
      await _db.customersDao.updateCustomer(customer);
      return customer.id;
    }
  }

  Future<void> toggleActive(Customer customer, bool isActive) async {
    final updated = customer.copyWith(isActive: isActive);
    await _db.customersDao.updateCustomer(updated);
  }
}
