// lib/core/database/daos/suppliers_dao.dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/suppliers_table.dart';

part 'suppliers_dao.g.dart';

@DriftAccessor(tables: [Suppliers])
class SuppliersDao extends DatabaseAccessor<AppDatabase> with _$SuppliersDaoMixin {
  SuppliersDao(super.db);

  Future<List<Supplier>> getAllSuppliers() =>
      (select(suppliers)..where((s) => s.isActive.equals(true))
        ..orderBy([(s) => OrderingTerm.asc(s.name)]))
          .get();

  Stream<List<Supplier>> watchAllSuppliers() =>
      (select(suppliers)..where((s) => s.isActive.equals(true))
        ..orderBy([(s) => OrderingTerm.asc(s.name)]))
          .watch();

  Future<List<Supplier>> searchSuppliers(String query) =>
      (select(suppliers)
        ..where((s) => s.name.like('%$query%') & s.isActive.equals(true)))
          .get();

  Future<Supplier?> getSupplierById(int id) =>
      (select(suppliers)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<int> insertSupplier(SuppliersCompanion entry) =>
      into(suppliers).insert(entry);

  Future<bool> updateSupplier(SuppliersCompanion entry) =>
      update(suppliers).replace(entry);

  Future<int> deactivateSupplier(int id) =>
      (update(suppliers)..where((s) => s.id.equals(id)))
          .write(const SuppliersCompanion(isActive: Value(false)));

  Future<int> deleteSupplier(int id) =>
      (delete(suppliers)..where((s) => s.id.equals(id))).go();
}
