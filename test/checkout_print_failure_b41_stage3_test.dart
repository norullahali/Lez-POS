import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/printing/print_outcome.dart';
import 'package:lez_pos/core/printing/print_outcome_messages.dart';
import 'package:lez_pos/core/services/pos_sale_service.dart';
import 'package:lez_pos/core/services/process_sale_result.dart';
import 'package:lez_pos/core/services/receipt_service.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Mirrors [pos_screen] post-checkout: print only, errors swallowed.
Future<void> simulatePostCheckoutPrint({
  required ProcessSaleResult saleResult,
  required Future<PrintOutcome> Function(int invoiceId) printInvoice,
}) async {
  try {
    await printInvoice(saleResult.invoiceId);
  } catch (_) {
    // Same as pos_screen inner catch — sale already committed.
  }
}

Future<double> _productStock(AppDatabase db, int productId) async {
  final row = await (db.select(db.products)
        ..where((p) => p.id.equals(productId)))
      .getSingle();
  return row.currentStock;
}

void main() {
  group('Post-checkout print failure (B41 Stage 3)', () {
    late AppDatabase db;
    late PosSaleService saleService;
    late int productId;

    setUp(() async {
      db = AppDatabase.test();
      saleService = PosSaleService(db);
      productId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('Print Fail Product'),
              currentStock: Value(100),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );
    });

    tearDown(() async => db.close());

    test(
        'committed sale is unchanged when print/load fails and is retried',
        () async {
      final stockBefore = await _productStock(db, productId);
      final idempotencyKey = _uuid.v4();

      final saleResult = await saleService.processSale(
        idempotencyKey: idempotencyKey,
        fingerprintHash: 'b41-print-fail-fp',
        invoice: SalesInvoicesCompanion(
          invoiceNumber: Value('PF-${DateTime.now().microsecondsSinceEpoch}'),
          subtotal: const Value(10),
          total: const Value(10),
          paymentMethod: const Value('CASH'),
          cashPaid: const Value(10),
        ),
        items: [
          SaleItemsCompanion(
            productId: Value(productId),
            quantity: const Value(1),
            unitPrice: const Value(10),
            unitCost: const Value(5),
            total: const Value(10),
          ),
        ],
        netSaleTotal: 10,
      );

      expect(saleResult.idempotentReplay, isFalse);
      final invoicesAfterCommit =
          (await db.select(db.salesInvoices).get()).length;
      final stockAfterCommit = await _productStock(db, productId);
      expect(invoicesAfterCommit, 1);
      expect(stockAfterCommit, stockBefore - 1);

      var printCalls = 0;
      Future<PrintOutcome> failingPrint(int invoiceId) async {
        printCalls++;
        await loadPersistedReceiptData(invoiceId, db);
        throw StateError('simulated print failure');
      }

      await simulatePostCheckoutPrint(
        saleResult: saleResult,
        printInvoice: failingPrint,
      );
      for (var i = 0; i < 2; i++) {
        try {
          await failingPrint(saleResult.invoiceId);
        } catch (_) {}
      }

      expect(printCalls, 3);
      expect((await db.select(db.salesInvoices).get()).length, 1);
      expect(await _productStock(db, productId), stockAfterCommit);

      final replay = await saleService.processSale(
        idempotencyKey: idempotencyKey,
        fingerprintHash: 'b41-print-fail-fp',
        invoice: SalesInvoicesCompanion(
          invoiceNumber: Value('PF-replay-${DateTime.now().microsecondsSinceEpoch}'),
          subtotal: const Value(10),
          total: const Value(10),
          paymentMethod: const Value('CASH'),
          cashPaid: const Value(10),
        ),
        items: [
          SaleItemsCompanion(
            productId: Value(productId),
            quantity: const Value(1),
            unitPrice: const Value(10),
            unitCost: const Value(5),
            total: const Value(10),
          ),
        ],
        netSaleTotal: 10,
      );
      expect(replay.idempotentReplay, isTrue);
      expect((await db.select(db.salesInvoices).get()).length, 1);
      expect(await _productStock(db, productId), stockAfterCommit);
    });

    test('Stage 2 checkout failure message still mentions Ctrl+P', () {
      final msg = checkoutPrintFailureMessageAr(
        PrintOutcome.failed(code: 'printer_not_found'),
      );
      expect(msg, contains('Ctrl+P'));
    });
  });
}
