import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/constants/invoice_lifecycle.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_return_credit.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';

void main() {
  late AppDatabase db;
  late PartialReturnService partialService;
  late int customerId;
  late int cashCustomerId;
  late int productAId;
  late int productBId;
  late int productCId;
  late int invoiceId;
  late int saleItemAId;
  late int saleItemBId;
  late int saleItemCId;
  const returnedByUserId = 1;

  Future<void> seedProducts() async {
    productAId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Product A'),
            barcode: Value('CR-A'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
    productBId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Product B'),
            barcode: Value('CR-B'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
    productCId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Product C'),
            barcode: Value('CR-C'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
  }

  Future<int> createCreditInvoice({
    double debtAmount = 400,
    double cashPaid = 0,
    int? customer,
  }) async {
    final cid = customer ?? customerId;
    invoiceId = await db.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('SI-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: const Value(400),
        total: const Value(400),
        debtAmount: Value(debtAmount),
        cashPaid: Value(cashPaid),
        customerId: Value(cid),
        paymentMethod: const Value('DEBT'),
      ),
      items: [
        {'productId': productAId, 'qty': 10.0, 'price': 10.0, 'cost': 5.0},
        {'productId': productBId, 'qty': 5.0, 'price': 20.0, 'cost': 5.0},
        {'productId': productCId, 'qty': 8.0, 'price': 25.0, 'cost': 5.0},
      ],
    );

    final items = await db.salesDao.getItemsForInvoice(invoiceId);
    saleItemAId = items.firstWhere((i) => i.productId == productAId).id;
    saleItemBId = items.firstWhere((i) => i.productId == productBId).id;
    saleItemCId = items.firstWhere((i) => i.productId == productCId).id;

    if (debtAmount > 0) {
      await db.customerAccountsDao.recordSale(
        customerId: cid,
        amount: debtAmount,
        invoiceId: invoiceId,
        note: 'test credit sale',
      );
    }
    return invoiceId;
  }

  setUp(() async {
    db = AppDatabase.test();
    partialService = PartialReturnService(db);
    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('Credit Customer')),
        );
    cashCustomerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('Cash Customer')),
        );
    await seedProducts();
    await createCreditInvoice();
  });

  tearDown(() async {
    await db.close();
  });

  Future<double> customerBalance([int? cid]) =>
      db.customerAccountsDao.getBalance(cid ?? customerId);

  Future<int> returnTxnCount() async {
    final rows = await (db.select(db.customerTransactions)
          ..where((t) => t.type.equals('RETURN')))
        .get();
    return rows.length;
  }

  Future<double> creditReversedForInvoice() =>
      db.customerAccountsDao.getCreditReversalTotalForSaleInvoice(
        customerId: customerId,
        invoiceId: invoiceId,
      );

  Future<double> productStock(int productId) => db.stockDao.getStock(productId);

  Future<int> saleItemReturnCount() async {
    final rows = await db.select(db.saleItemReturns).get();
    return rows.length;
  }

  Future<int> customerReturnHeaderCount() async {
    final rows = await db.select(db.customerReturns).get();
    return rows.length;
  }

  PartialReturnLine line({
    required int saleItemId,
    required int productId,
    required double qty,
    required double price,
  }) =>
      PartialReturnLine(
        saleItemId: saleItemId,
        productId: productId,
        quantity: qty,
        unitPrice: price,
        unitCost: 5,
      );

  group('CustomerReturnCredit helpers', () {
    test('proportional goods value and debt ratio', () {
      expect(
        CustomerReturnCredit.goodsValueForReturnedQuantity(
          soldQuantity: 10,
          lineTotal: 100,
          returnedQuantity: 4,
        ),
        40,
      );
      expect(
        CustomerReturnCredit.creditReversalForGoodsValue(
          returnedGoodsValue: 40,
          invoiceTotal: 400,
          invoiceDebtAmount: 400,
        ),
        40,
      );
      expect(
        CustomerReturnCredit.creditReversalForGoodsValue(
          returnedGoodsValue: 40,
          invoiceTotal: 400,
          invoiceDebtAmount: 200,
        ),
        20,
      );
      expect(
        CustomerReturnCredit.cappedCreditReversal(
          proposed: 50,
          invoiceDebtAmount: 400,
          alreadyReversed: 360,
        ),
        40,
      );
    });
  });

  group('Phase C.1 customer returns', () {
    test('A) full return on credit invoice reverses full debt', () async {
      expect(await customerBalance(), 400);

      final returnId = await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'full return',
        returnedByUserId: returnedByUserId,
      );

      expect(returnId, greaterThan(0));
      expect(await customerReturnHeaderCount(), 1);
      expect(await returnTxnCount(), 1);
      expect(await creditReversedForInvoice(), 400);
      expect(await customerBalance(), 0);

      final inv = await db.salesDao.getInvoiceById(invoiceId);
      expect(inv!.invoiceStatus, InvoiceLifecycleStatus.returned);
      expect(await productStock(productAId), 100);
      expect(await productStock(productBId), 100);
      expect(await productStock(productCId), 100);
    });

    test('B) partial return on credit invoice creates RETURN transaction',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 4, price: 10)
        ],
      );

      expect(await returnTxnCount(), 1);
      final txns = await db.customerAccountsDao.getHistory(customerId);
      expect(txns.any((t) => t.type == 'RETURN'), isTrue);
    });

    test('C) partial return credit amount matches returned goods share',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 4, price: 10)
        ],
      );

      expect(await creditReversedForInvoice(), 40);
      expect(await customerBalance(), 360);
    });

    test('D) partial return does not reverse more debt than returned goods',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 4, price: 10)
        ],
      );

      expect(await creditReversedForInvoice(), lessThanOrEqualTo(40));
      expect(await customerBalance(), greaterThanOrEqualTo(0));
    });

    test('E) multiple partial returns accumulate credit reversal correctly',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 4, price: 10)
        ],
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemBId, productId: productBId, qty: 2, price: 20)
        ],
      );

      // A: 40 + B: (2/5)*100 = 40 => 80 total reversed
      expect(await creditReversedForInvoice(), closeTo(80, 0.01));
      expect(await customerBalance(), closeTo(320, 0.01));
      expect(await returnTxnCount(), 2);
    });

    test('F) partial then return all remaining completes invoice', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 4, price: 10)
        ],
      );

      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'return remaining',
        returnedByUserId: returnedByUserId,
      );

      final inv = await db.salesDao.getInvoiceById(invoiceId);
      expect(inv!.invoiceStatus, InvoiceLifecycleStatus.returned);
      expect(await customerBalance(), 0);
      expect(await creditReversedForInvoice(), closeTo(400, 0.01));
    });

    test('G) return all remaining returns only remaining quantities', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 4, price: 10)
        ],
      );

      await partialService.returnAllRemainingSaleInvoice(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: 'all remaining',
      );

      final returned =
          await partialService.getReturnedQuantitiesForInvoice(invoiceId);
      expect(returned[saleItemAId], closeTo(10, 0.01));
      expect(returned[saleItemBId], closeTo(5, 0.01));
      expect(returned[saleItemCId], closeTo(8, 0.01));
    });

    test('H) fully returned line excluded from return all remaining batch',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemBId, productId: productBId, qty: 5, price: 20)
        ],
      );

      final availableA =
          await partialService.getAvailableReturnQuantity(saleItemAId);
      final availableB =
          await partialService.getAvailableReturnQuantity(saleItemBId);
      expect(availableA, closeTo(10, 0.01));
      expect(availableB, closeTo(0, 0.01));
      expect(await partialService.hasRemainingReturnableQuantity(invoiceId),
          isTrue);
    });

    test('I) full return after partial does not duplicate stock restoration',
        () async {
      final stockBefore = await productStock(productAId);

      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 4, price: 10)
        ],
      );
      expect(await productStock(productAId), stockBefore + 4);

      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'remaining',
        returnedByUserId: returnedByUserId,
      );

      expect(await productStock(productAId), 100);
      expect(await saleItemReturnCount(), 4);
    });

    test(
        'J) full return after partial does not duplicate customer credit reversal',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 4, price: 10)
        ],
      );

      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'remaining',
        returnedByUserId: returnedByUserId,
      );

      expect(await creditReversedForInvoice(), closeTo(400, 0.01));
      expect(await customerBalance(), closeTo(0, 0.01));
    });

    test('K) third return attempt rejected when fully returned', () async {
      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'full',
        returnedByUserId: returnedByUserId,
      );

      await expectLater(
        partialService.processPartialReturn(
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [
            line(
                saleItemId: saleItemAId,
                productId: productAId,
                qty: 1,
                price: 10)
          ],
        ),
        throwsA(isA<StateError>()),
      );

      await expectLater(
        db.returnsDao.returnFullSaleInvoice(
          invoiceId,
          note: 'again',
          returnedByUserId: returnedByUserId,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('L) wrong sale item id rejected', () async {
      await expectLater(
        partialService.processPartialReturn(
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [
            line(saleItemId: 99999, productId: productAId, qty: 1, price: 10)
          ],
        ),
        throwsA(isA<StateError>()),
      );
      expect(await saleItemReturnCount(), 0);
    });

    test('M) excess quantity rejected with no side effects', () async {
      await expectLater(
        partialService.processPartialReturn(
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [
            line(
                saleItemId: saleItemAId,
                productId: productAId,
                qty: 11,
                price: 10)
          ],
        ),
        throwsA(isA<StateError>()),
      );

      expect(await saleItemReturnCount(), 0);
      expect(await returnTxnCount(), 0);
      expect(await customerBalance(), 400);
    });

    test('N) customer accounting failure rolls back all return writes',
        () async {
      final failingService = PartialReturnService.withCreditPoster(
        db,
        creditPoster: ({
          required int customerId,
          required double amount,
          required int returnId,
          String note = '',
        }) async {
          throw Exception('forced accounting failure');
        },
      );

      final stockBefore = await productStock(productAId);

      await expectLater(
        failingService.processPartialReturn(
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [
            line(
                saleItemId: saleItemAId,
                productId: productAId,
                qty: 4,
                price: 10)
          ],
        ),
        throwsA(isA<Exception>()),
      );

      expect(await saleItemReturnCount(), 0);
      expect(await returnTxnCount(), 0);
      expect(await productStock(productAId), stockBefore);
      expect(await customerBalance(), 400);
    });

    test('O) batch failure rolls back stock and prior lines in same return',
        () async {
      final stockBefore = await productStock(productAId);

      await expectLater(
        partialService.processPartialReturn(
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [
            line(
                saleItemId: saleItemAId,
                productId: productAId,
                qty: 4,
                price: 10),
            line(
                saleItemId: saleItemBId,
                productId: productBId,
                qty: 99,
                price: 20),
          ],
        ),
        throwsA(isA<StateError>()),
      );

      expect(await saleItemReturnCount(), 0);
      expect(await returnTxnCount(), 0);
      expect(await productStock(productAId), stockBefore);
      expect(await customerBalance(), 400);
    });

    test('P) return persistence failure rolls back customer accounting',
        () async {
      // Same as O: invalid second line prevents any accounting write.
      await expectLater(
        partialService.processPartialReturn(
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [
            line(
                saleItemId: saleItemAId,
                productId: productAId,
                qty: 4,
                price: 10),
            line(
                saleItemId: saleItemCId,
                productId: productCId,
                qty: 99,
                price: 25),
          ],
        ),
        throwsA(isA<StateError>()),
      );

      expect(await returnTxnCount(), 0);
      expect(await customerBalance(), 400);
    });

    test('Q) cash sale partial return creates no customer RETURN transaction',
        () async {
      await db.close();
      db = AppDatabase.test();
      partialService = PartialReturnService(db);
      cashCustomerId = await db.into(db.customers).insert(
            const CustomersCompanion(name: Value('Cash Customer')),
          );
      await seedProducts();

      final cashInvoiceId = await db.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber: Value('CASH-${DateTime.now().microsecondsSinceEpoch}'),
          subtotal: const Value(100),
          total: const Value(100),
          debtAmount: const Value(0),
          cashPaid: const Value(100),
          customerId: Value(cashCustomerId),
          paymentMethod: const Value('CASH'),
        ),
        items: [
          {'productId': productAId, 'qty': 10.0, 'price': 10.0, 'cost': 5.0},
        ],
      );

      final items = await db.salesDao.getItemsForInvoice(cashInvoiceId);
      final cashItemId = items.single.id;

      await partialService.processPartialReturn(
        saleInvoiceId: cashInvoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(saleItemId: cashItemId, productId: productAId, qty: 2, price: 10)
        ],
      );

      expect(await returnTxnCount(), 0);
    });

    test('R) credit sale regression keeps SALE plus RETURN ledger integrity',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemCId, productId: productCId, qty: 8, price: 25)
        ],
      );

      final txns = await db.customerAccountsDao.getHistory(customerId);
      expect(txns.where((t) => t.type == 'SALE').length, 1);
      expect(txns.where((t) => t.type == 'RETURN').length, 1);
      expect(await customerBalance(), closeTo(200, 0.01));
    });

    test('Partial A + Partial B + Return All Remaining without over-return',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 4, price: 10)
        ],
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemBId, productId: productBId, qty: 2, price: 20)
        ],
      );

      await partialService.returnAllRemainingSaleInvoice(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: 'finish',
      );

      expect(await creditReversedForInvoice(), closeTo(400, 0.01));
      expect(await customerBalance(), closeTo(0, 0.01));

      final inv = await db.salesDao.getInvoiceById(invoiceId);
      expect(inv!.invoiceStatus, InvoiceLifecycleStatus.returned);
    });
  });
}
