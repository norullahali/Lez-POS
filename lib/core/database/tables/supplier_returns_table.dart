// lib/core/database/tables/supplier_returns_table.dart
import 'package:drift/drift.dart';
import 'suppliers_table.dart';
import 'purchase_invoices_table.dart';
import 'purchase_items_table.dart';

class SupplierReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierId => integer().nullable().references(Suppliers, #id)();

  /// Original purchase header for purchase-linked returns (SR.1).
  /// Nullable for legacy/manual supplier returns without purchase linkage.
  IntColumn get purchaseInvoiceId =>
      integer().nullable().references(PurchaseInvoices, #id)();
  TextColumn get returnNumber => text()();
  DateTimeColumn get returnDate => dateTime().withDefault(currentDateAndTime)();
  RealColumn get total => real().withDefault(const Constant(0.0))();
  TextColumn get reason => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
}

class SupplierReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId =>
      integer().references(SupplierReturns, #id, onDelete: KeyAction.cascade)();

  /// Exact purchase line this return item reverses (SR.1 line-level traceability).
  /// Nullable for legacy/manual rows; null rows are excluded from returnable-qty sums.
  IntColumn get purchaseItemId =>
      integer().nullable().references(PurchaseItems, #id)();
  IntColumn get productId => integer()();
  TextColumn get productName => text()();
  RealColumn get quantity => real()();
  RealColumn get unitCost => real()();
  RealColumn get total => real()();

  List<Index> get indexes => [
        Index(
          'supplier_return_items_purchase_item_idx',
          'CREATE INDEX IF NOT EXISTS supplier_return_items_purchase_item_idx '
              'ON supplier_return_items (purchase_item_id)',
        ),
      ];
}
