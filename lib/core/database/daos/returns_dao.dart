// lib/core/database/daos/returns_dao.dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/customer_returns_table.dart';
import '../tables/supplier_returns_table.dart';
import '../tables/stock_ledger_table.dart';
import '../../constants/movement_types.dart';

part 'returns_dao.g.dart';

@DriftAccessor(tables: [
  CustomerReturns,
  CustomerReturnItems,
  SupplierReturns,
  SupplierReturnItems,
  StockLedger,
])
class ReturnsDao extends DatabaseAccessor<AppDatabase> with _$ReturnsDaoMixin {
  ReturnsDao(super.db);

  // --- Customer Returns ---
  Future<List<CustomerReturn>> getAllCustomerReturns() =>
      (select(customerReturns)
        ..orderBy([(r) => OrderingTerm.desc(r.returnDate)]))
          .get();

  Future<List<CustomerReturnItem>> getCustomerReturnItems(int returnId) =>
      (select(customerReturnItems)
        ..where((i) => i.returnId.equals(returnId)))
          .get();

  Future<int> saveCustomerReturn({
    required CustomerReturnsCompanion header,
    required List<Map<String, dynamic>> items,
  }) async {
    return transaction(() async {
      final returnId = await into(customerReturns).insert(header);
      for (final item in items) {
        final productId = item['productId'] as int;
        final qty = (item['qty'] as num).toDouble();
        final price = (item['price'] as num).toDouble();
        final cost = (item['cost'] as num?)?.toDouble() ?? 0.0;

        final itemId = await into(customerReturnItems).insert(
          CustomerReturnItemsCompanion(
            returnId: Value(returnId),
            productId: Value(productId),
            productName: Value(item['productName'] as String),
            quantity: Value(qty),
            unitPrice: Value(price),
            unitCost: Value(cost),
            total: Value(qty * price),
          ),
        );

        // Stock comes BACK IN when customer returns
        await into(stockLedger).insert(
          StockLedgerCompanion(
            productId: Value(productId),
            movementType: Value(StockMovementType.returnIn.code),
            referenceId: Value(itemId),
            referenceType: const Value('customer_return_items'),
            quantityChange: Value(qty), // positive = stock back in
            unitCost: Value(cost),
          ),
        );
      }
      return returnId;
    });
  }

  // --- Supplier Returns ---
  Future<List<SupplierReturn>> getAllSupplierReturns() =>
      (select(supplierReturns)
        ..orderBy([(r) => OrderingTerm.desc(r.returnDate)]))
          .get();

  Future<List<SupplierReturnItem>> getSupplierReturnItems(int returnId) =>
      (select(supplierReturnItems)
        ..where((i) => i.returnId.equals(returnId)))
          .get();

  Future<int> saveSupplierReturn({
    required SupplierReturnsCompanion header,
    required List<Map<String, dynamic>> items,
  }) async {
    return transaction(() async {
      final returnId = await into(supplierReturns).insert(header);
      for (final item in items) {
        final productId = item['productId'] as int;
        final qty = (item['qty'] as num).toDouble();
        final cost = (item['cost'] as num).toDouble();

        final itemId = await into(supplierReturnItems).insert(
          SupplierReturnItemsCompanion(
            returnId: Value(returnId),
            productId: Value(productId),
            productName: Value(item['productName'] as String),
            quantity: Value(qty),
            unitCost: Value(cost),
            total: Value(qty * cost),
          ),
        );

        // Stock goes OUT when returned to supplier
        await into(stockLedger).insert(
          StockLedgerCompanion(
            productId: Value(productId),
            movementType: Value(StockMovementType.returnOut.code),
            referenceId: Value(itemId),
            referenceType: const Value('supplier_return_items'),
            quantityChange: Value(-qty), // negative = out
            unitCost: Value(cost),
          ),
        );
      }
      return returnId;
    });
  }
}
