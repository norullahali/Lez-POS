import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_account_service.dart';
import 'package:lez_pos/core/services/customer_refund_settlement_service.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';

void main() {
  late AppDatabase db;
  late CustomerRefundSettlementService settlementService;
  late PartialReturnService partialService;
  late int customerId;
  late int otherCustomerId;
  late int productId;
  late int invoiceId;
  const returnedByUserId = 1;

  setUp(() async {
    db = AppDatabase.test();
    settlementService = CustomerRefundSettlementService(db);
    partialService = PartialReturnService(db);

    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('Refund Customer')),
        );
    otherCustomerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('Other Customer')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Refund Product'),
            barcode: Value('CRF-1'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  Future<double> balance([int? cid]) =>
      db.customerAccountsDao.getBalance(cid ?? customerId);

  Future<int> refundTxnCount([int? cid]) async {
    final rows = await (db.select(db.customerTransactions)
          ..where((t) =>
              t.customerId.equals(cid ?? customerId) & t.type.equals('REFUND')))
        .get();
    return rows.length;
  }

  Future<int> returnTxnCount([int? cid]) async {
    final rows = await (db.select(db.customerTransactions)
          ..where((t) =>
              t.customerId.equals(cid ?? customerId) & t.type.equals('RETURN')))
        .get();
    return rows.length;
  }

  Future<double> refundTotal([int? cid]) async {
    final rows = await (db.select(db.customerTransactions)
          ..where((t) =>
              t.customerId.equals(cid ?? customerId) & t.type.equals('REFUND')))
        .get();
    return rows.fold<double>(0, (sum, row) => sum + row.amount);
  }

  Future<int> createCreditInvoice({
    required int customer,
    double debtAmount = 100,
  }) async {
    final id = await db.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('CRF-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: Value(debtAmount),
        total: Value(debtAmount),
        debtAmount: Value(debtAmount),
        customerId: Value(customer),
        paymentMethod: const Value('DEBT'),
      ),
      items: [
        {
          'productId': productId,
          'qty': 10.0,
          'price': debtAmount / 10,
          'cost': 5.0,
        },
      ],
    );

    if (debtAmount > 0) {
      await db.customerAccountsDao.recordSale(
        customerId: customer,
        amount: debtAmount,
        invoiceId: id,
        note: 'test credit sale',
      );
    }

    return id;
  }

  Future<void> seedCredit100() async {
    invoiceId =
        await createCreditInvoice(customer: customerId, debtAmount: 100);
    await db.customerAccountsDao.recordPayment(
      customerId: customerId,
      amount: 200,
      note: 'overpayment',
    );
    expect(await balance(), -100);
  }

  Future<int> postReturnCredit100() async {
    invoiceId =
        await createCreditInvoice(customer: customerId, debtAmount: 100);
    await db.customerAccountsDao.recordPayment(
      customerId: customerId,
      amount: 100,
      note: 'pay before return',
    );
    expect(await balance(), 0);

    await db.returnsDao.returnFullSaleInvoice(
      invoiceId,
      note: 'full return',
      returnedByUserId: returnedByUserId,
    );
    expect(await balance(), -100);

    final returns = await db.select(db.customerReturns).get();
    return returns.single.id;
  }

  group('Phase C Step 2.1 customer refund settlement', () {
    test('A) full customer credit settlement', () async {
      await seedCredit100();

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 100,
      );

      expect(await balance(), 0);
      expect(await refundTxnCount(), 1);
      expect(await refundTotal(), 100);
    });

    test('B) partial customer credit settlement', () async {
      await seedCredit100();

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 40,
      );

      expect(await balance(), -60);
      expect(await refundTxnCount(), 1);
      expect(await refundTotal(), 40);
    });

    test('C) second partial settlement consumes remaining credit', () async {
      await seedCredit100();

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 40,
      );
      await settlementService.settleCredit(
        customerId: customerId,
        amount: 60,
      );

      expect(await balance(), 0);
      expect(await refundTxnCount(), 2);
      expect(await refundTotal(), 100);
    });

    test('D) over-settlement rejected', () async {
      await seedCredit100();
      final before = await balance();

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 101,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.amountExceedsCredit,
          ),
        ),
      );

      expect(await balance(), before);
      expect(await refundTxnCount(), 0);
    });

    test('E) no customer credit rejected', () async {
      invoiceId =
          await createCreditInvoice(customer: customerId, debtAmount: 100);
      expect(await balance(), 100);

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 10,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.noCustomerCredit,
          ),
        ),
      );

      expect(await refundTxnCount(), 0);
    });

    test('F) zero amount rejected', () async {
      await seedCredit100();

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 0,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.invalidAmount,
          ),
        ),
      );

      expect(await refundTxnCount(), 0);
    });

    test('G) negative amount rejected', () async {
      await seedCredit100();

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: -5,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.invalidAmount,
          ),
        ),
      );

      expect(await refundTxnCount(), 0);
    });

    test('H) customer not found rejected', () async {
      await expectLater(
        settlementService.settleCredit(
          customerId: 999999,
          amount: 10,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.customerNotFound,
          ),
        ),
      );

      expect(await refundTxnCount(999999), 0);
    });

    test('I) return not found rejected when returnId supplied', () async {
      await seedCredit100();

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 10,
          returnId: 999999,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.returnNotFound,
          ),
        ),
      );

      expect(await refundTxnCount(), 0);
    });

    test('J) return/customer mismatch rejected', () async {
      final returnId = await postReturnCredit100();

      await expectLater(
        settlementService.settleCredit(
          customerId: otherCustomerId,
          amount: 10,
          returnId: returnId,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.returnCustomerMismatch,
          ),
        ),
      );

      expect(await refundTxnCount(otherCustomerId), 0);
    });

    test('K) positive REFUND amount and correct type', () async {
      await seedCredit100();

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 25,
      );

      final txn = (await db.customerAccountsDao.getHistory(customerId))
          .firstWhere((t) => t.type == 'REFUND');
      expect(txn.type, 'REFUND');
      expect(txn.amount, greaterThan(0));
      expect(txn.amount, 25);
    });

    test('L) reference traceability when returnId supplied', () async {
      final returnId = await postReturnCredit100();

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 10,
        returnId: returnId,
      );

      final txn = (await db.customerAccountsDao.getHistory(customerId))
          .firstWhere((t) => t.type == 'REFUND');
      expect(txn.referenceId, returnId);
      expect(txn.amount, 10);
    });

    test('M) atomic rollback on post-refund failure', () async {
      await seedCredit100();
      final failingService = CustomerRefundSettlementService(
        db,
        postRefundHook: () async {
          throw Exception('forced post-refund failure');
        },
      );

      await expectLater(
        failingService.settleCredit(
          customerId: customerId,
          amount: 40,
        ),
        throwsA(isA<CustomerRefundSettlementException>()),
      );

      expect(await balance(), -100);
      expect(await refundTxnCount(), 0);
    });

    test('M2) atomic rollback on accounting failure', () async {
      await seedCredit100();
      final failingService = CustomerRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int customerId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          throw Exception('forced accounting failure');
        },
      );

      await expectLater(
        failingService.settleCredit(
          customerId: customerId,
          amount: 40,
        ),
        throwsA(isA<CustomerRefundSettlementException>()),
      );

      expect(await balance(), -100);
      expect(await refundTxnCount(), 0);
    });

    test('N) existing PAYMENT regression unchanged', () async {
      invoiceId =
          await createCreditInvoice(customer: customerId, debtAmount: 100);
      expect(await balance(), 100);

      await CustomerAccountService(db).processPayment(
        customerId: customerId,
        amount: 40,
      );

      expect(await balance(), 60);
      expect(await refundTxnCount(), 0);
    });

    test('O) existing RETURN regression unchanged', () async {
      invoiceId =
          await createCreditInvoice(customer: customerId, debtAmount: 100);
      final items = await db.salesDao.getItemsForInvoice(invoiceId);
      final saleItemId = items.single.id;

      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          PartialReturnLine(
            saleItemId: saleItemId,
            productId: productId,
            quantity: 4,
            unitPrice: 10,
            unitCost: 5,
          ),
        ],
      );

      expect(await returnTxnCount(), 1);
      expect(await refundTxnCount(), 0);
      expect(await balance(), 60);

      final returnTxn = (await db.customerAccountsDao.getHistory(customerId))
          .firstWhere((t) => t.type == 'RETURN');
      expect(returnTxn.amount, lessThan(0));
    });

    test('P) credit calculation authority from DB state', () async {
      await seedCredit100();

      await db.customerAccountsDao.recordSale(
        customerId: customerId,
        amount: 50,
        invoiceId: invoiceId + 1000,
        note: 'extra sale changes balance',
      );
      expect(await balance(), -50);

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 100,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.amountExceedsCredit,
          ),
        ),
      );

      await db.customerAccountsDao.adjustBalance(
        customerId: customerId,
        signedAmount: -50,
        reason: 'restore credit for authority test',
      );
      expect(await balance(), -100);

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 100,
      );

      expect(await balance(), 0);
      expect(await refundTotal(), 100);
    });
  });
}
