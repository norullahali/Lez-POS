import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../constants/movement_types.dart';

/// Service to handle complete purchase operations.
class PurchaseService {
  final AppDatabase db;

  PurchaseService(this.db);

  /// Main method to process a purchase invoice along with items and payments.
  Future<int> processPurchase({
    required PurchaseInvoicesCompanion invoice,
    required List<PurchaseItemsCompanion> items,
    double? paidAmount, // optional override
  }) async {
    try {
      return await db.transaction(() async {
        // ... (rest of the code as is)
        // 1. Validate
        await _validatePurchase(invoice, items);

        // 2. Insert purchase invoice
        final invoiceId = await db.into(db.purchaseInvoices).insert(invoice);

        // 3. Insert items and update stock ledger
        await _processItems(invoiceId, items);

        // 4. Update supplier account balance and record transaction
        final double total = invoice.total.present ? invoice.total.value : _calculateTotal(items);
        final double actualPaid = paidAmount ?? (invoice.paidAmount.present ? invoice.paidAmount.value : 0.0);
        final int supplierId = invoice.supplierId.value!;

        // Record the debt increase from the purchase
        await db.supplierAccountsDao.addTransaction(
          supplierId: supplierId,
          type: 'PURCHASE',
          amount: total, // Positive increases debt
          referenceId: invoiceId,
          note: 'فاتورة مشتريات رقم $invoiceId (${invoice.invoiceNumber.value})',
        );

        // Record the debt decrease from the payment
        if (actualPaid > 0) {
          await db.supplierAccountsDao.addTransaction(
            supplierId: supplierId,
            type: 'PAYMENT',
            amount: -actualPaid, // Negative decreases debt
            referenceId: invoiceId,
            note: 'دفع لفاتورة مشتريات رقم $invoiceId',
          );
        }

        // 5. Log the purchase
        await db.logsDao.insertLog(
          userId: null,
          actionType: 'PURCHASE_CONFIRMED',
          details: 'Purchase ID: $invoiceId, Supplier: $supplierId, Total: $total, Paid: $actualPaid',
        );

        return invoiceId;
      });
    } catch (e, st) {
      debugPrint('[PurchaseService] Error in processPurchase: $e\n$st');
      if (e is Exception) rethrow;
      throw Exception('فشل في إتمام عملية الشراء: ${e.toString()}');
    }
  }

  Future<void> _validatePurchase(
    PurchaseInvoicesCompanion purchase,
    List<PurchaseItemsCompanion> items,
  ) async {
    final supplierId = purchase.supplierId.value;
    if (supplierId == null) throw Exception('Supplier ID is required.');
    
    final supplier = await db.suppliersDao.getSupplierById(supplierId);
    if (supplier == null) throw Exception('Supplier with ID $supplierId does not exist.');

    for (final item in items) {
      if (item.unitCost.value <= 0) {
        throw Exception('Product ${item.productId.value} has invalid unit cost.');
      }
      if (item.quantity.value <= 0) {
        throw Exception('Product ${item.productId.value} has invalid quantity.');
      }

      final product = await db.productsDao.getProductById(item.productId.value);
      if (product == null) {
        throw Exception('Product with ID ${item.productId.value} does not exist.');
      }
    }
  }

  Future<void> _processItems(
    int invoiceId,
    List<PurchaseItemsCompanion> items,
  ) async {
    await db.batch((batch) {
      for (final item in items) {
        batch.insert(
          db.purchaseItems,
          item.copyWith(invoiceId: Value(invoiceId)),
        );

        batch.insert(
          db.stockLedger,
          StockLedgerCompanion(
            productId: item.productId,
            quantityChange: item.quantity,
            movementType: Value(StockMovementType.purchase.code),
            referenceId: Value(invoiceId),
            referenceType: const Value('purchase_invoices'),
            unitCost: item.unitCost,
            createdAt: Value(DateTime.now()),
          ),
        );
      }
    });

    for (final item in items) {
      await (db.update(db.products)..where((p) => p.id.equals(item.productId.value))).write(
        ProductsCompanion(
          costPrice: item.unitCost,
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  double _calculateTotal(List<PurchaseItemsCompanion> items) {
    return items.fold<double>(
      0,
      (sum, item) => sum + (item.quantity.value * item.unitCost.value),
    );
  }
}
