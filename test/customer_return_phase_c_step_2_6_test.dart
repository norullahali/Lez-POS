import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/constants/invoice_lifecycle.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';
import 'package:lez_pos/features/returns/repositories/customer_return_read_repository.dart';

void main() {
  late AppDatabase db;
  late PartialReturnService partialService;
  late CustomerReturnReadRepository readRepo;
  late int customerId;
  late int cashCustomerId;
  late int productAId;
  late int productBId;
  late int productCId;
  late int invoiceId;
  late int saleItemAId;
  late int saleItemBId;
  const returnedByUserId = 1;

  Future<void> seedProducts() async {
    productAId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Product A'),
            barcode: Value('CR6-A'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
    productBId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Product B'),
            barcode: Value('CR6-B'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
    productCId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Product C'),
            barcode: Value('CR6-C'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
  }

  Future<int> createCreditInvoice({
    double debtAmount = 400,
    int? customer,
  }) async {
    final cid = customer ?? customerId;
    invoiceId = await db.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('SI6-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: const Value(400),
        total: const Value(400),
        debtAmount: Value(debtAmount),
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
    readRepo = CustomerReturnReadRepository(db);
    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('Credit Customer')),
        );
    cashCustomerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('Cash Customer')),
        );
    await seedProducts();
    await createCreditInvoice();
  });

  tearDown(() async => db.close());

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

  Future<int> headerCount() async =>
      (await db.select(db.customerReturns).get()).length;

  Future<int> itemCount() async =>
      (await db.select(db.customerReturnItems).get()).length;

  Future<int> saleItemReturnCount() async =>
      (await db.select(db.saleItemReturns).get()).length;

  Future<int> returnTxnCount() async =>
      (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('RETURN')))
              .get())
          .length;

  Future<double> creditReversedForInvoice() =>
      db.customerAccountsDao.getCreditReversalTotalForSaleInvoice(
        customerId: customerId,
        invoiceId: invoiceId,
      );

  Future<double> productStock(int productId) => db.stockDao.getStock(productId);

  Future<CustomerReturn?> headerForInvoice() =>
      db.returnsDao.findCustomerReturnByOriginalInvoiceId(invoiceId);

  group('Phase C Step 2.6 partial return customer_returns linkage', () {
    test('A) first partial return creates exactly one customer_returns header',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );

      expect(await headerCount(), 1);
      final header = await headerForInvoice();
      expect(header, isNotNull);
      expect(header!.originalInvoiceId, invoiceId);
    });

    test('B) first partial return creates correct customer_return_items',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );

      expect(await itemCount(), 1);
      final header = await headerForInvoice();
      final items = await db.returnsDao.getCustomerReturnItems(header!.id);
      expect(items.single.productId, productAId);
      expect(items.single.productName, 'Product A');
      expect(items.single.quantity, closeTo(2, 0.001));
      expect(items.single.unitPrice, closeTo(10, 0.001));
      expect(items.single.total, closeTo(20, 0.001));
    });

    test('C) second partial batch reuses the same header', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      final firstHeader = await headerForInvoice();

      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemBId, productId: productBId, qty: 1, price: 20)
        ],
      );

      expect(await headerCount(), 1);
      final secondHeader = await headerForInvoice();
      expect(secondHeader!.id, firstHeader!.id);
    });

    test('D) second batch appends customer_return_items', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemBId, productId: productBId, qty: 1, price: 20)
        ],
      );

      expect(await itemCount(), 2);
    });

    test('E) header total becomes cumulative across batches', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemBId, productId: productBId, qty: 1, price: 20)
        ],
      );

      final header = await headerForInvoice();
      expect(header!.total, closeTo(40, 0.001));
    });

    test('F) no duplicate customer_returns header exists for the invoice',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemBId, productId: productBId, qty: 1, price: 20)
        ],
      );

      final headers = await db.select(db.customerReturns).get();
      expect(headers.where((h) => h.originalInvoiceId == invoiceId).length, 1);
    });

    test('G) returnAllRemainingSaleInvoice reuses the same header', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      final before = (await headerForInvoice())!.id;

      await partialService.returnAllRemainingSaleInvoice(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: 'finish remaining',
      );

      expect(await headerCount(), 1);
      expect((await headerForInvoice())!.id, before);
    });

    test('H) full return after partial does not create a second header',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      final before = (await headerForInvoice())!.id;

      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'finish via full return',
        returnedByUserId: returnedByUserId,
      );

      expect(await headerCount(), 1);
      expect((await headerForInvoice())!.id, before);
    });

    test('I) clean full return regression still creates its normal header',
        () async {
      await db.close();
      db = AppDatabase.test();
      partialService = PartialReturnService(db);
      await seedProducts();
      customerId = await db.into(db.customers).insert(
            const CustomersCompanion(name: Value('Clean Full Customer')),
          );
      await createCreditInvoice();

      final returnId = await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'clean full',
        returnedByUserId: returnedByUserId,
      );

      expect(returnId, greaterThan(0));
      expect(await headerCount(), 1);
      final header = await headerForInvoice();
      expect(header!.total, closeTo(400, 0.001));
    });

    test('J) existing sale_item_returns behavior remains unchanged', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );

      expect(await saleItemReturnCount(), 1);
      final sir = await db.select(db.saleItemReturns).getSingle();
      expect(sir.saleInvoiceId, invoiceId);
      expect(sir.saleItemId, saleItemAId);
      expect(sir.returnedQuantity, closeTo(2, 0.001));
    });

    test('K) existing stock behavior remains unchanged', () async {
      final stockBefore = await productStock(productAId);

      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );

      expect(await productStock(productAId), closeTo(stockBefore + 2, 0.001));
    });

    test('L) existing customer RETURN transaction remains unchanged', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 4, price: 10)
        ],
      );

      expect(await returnTxnCount(), 1);
      expect(await creditReversedForInvoice(), closeTo(40, 0.01));
    });

    test('M) RETURN reference_id remains sale_item_returns.id', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 4, price: 10)
        ],
      );

      final sirRow = await db.select(db.saleItemReturns).getSingle();
      final returnTxn = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('RETURN')))
              .get())
          .single;
      expect(returnTxn.referenceId, sirRow.id);
      expect(sirRow.saleInvoiceId, invoiceId);
    });

    test('N) getCreditReversalTotalForSaleInvoice behavior remains unchanged',
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

      expect(await creditReversedForInvoice(), closeTo(80, 0.01));
    });

    test('O) cash invoice partial return creates document but no RETURN txn',
        () async {
      final cashInvoiceId = await db.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber:
              Value('CASH6-${DateTime.now().microsecondsSinceEpoch}'),
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
      final cashItemId =
          (await db.salesDao.getItemsForInvoice(cashInvoiceId)).single.id;

      await partialService.processPartialReturn(
        saleInvoiceId: cashInvoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(saleItemId: cashItemId, productId: productAId, qty: 2, price: 10)
        ],
      );

      expect(await returnTxnCount(), 0);
      final header = await db.returnsDao
          .findCustomerReturnByOriginalInvoiceId(cashInvoiceId);
      expect(header, isNotNull);
      expect(
          await db.returnsDao.getCustomerReturnItems(header!.id), isNotEmpty);
    });

    test('P) Customer Returns read path resolves the newly created header',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );

      final header = await headerForInvoice();
      final detail = await readRepo.getCustomerReturnDetail(header!.id);
      expect(detail, isNotNull);
      expect(detail!.originalInvoiceId, invoiceId);
      expect(detail.customerId, customerId);
      expect(detail.isRefundLinkEligible, isTrue);
      expect(detail.lines, isNotEmpty);
    });

    test(
        'Q) rollback removes customer_returns and sale_item_returns on failure',
        () async {
      final stockBefore = await productStock(productAId);
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

      expect(await headerCount(), 0);
      expect(await itemCount(), 0);
      expect(await saleItemReturnCount(), 0);
      expect(await returnTxnCount(), 0);
      expect(await productStock(productAId), closeTo(stockBefore, 0.001));
    });

    test('R) multiple batches remain one header when invoice fully returned',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemBId, productId: productBId, qty: 1, price: 20)
        ],
      );
      await partialService.returnAllRemainingSaleInvoice(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: 'complete',
      );

      final inv = await db.salesDao.getInvoiceById(invoiceId);
      expect(inv!.invoiceStatus, InvoiceLifecycleStatus.returned);
      expect(await headerCount(), 1);
    });

    test('S) no duplicate header when invoice becomes fully returned',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'complete via full return',
        returnedByUserId: returnedByUserId,
      );

      expect(await headerCount(), 1);
      final headers = await db.select(db.customerReturns).get();
      expect(headers.where((h) => h.originalInvoiceId == invoiceId).length, 1);
    });
  });
}
