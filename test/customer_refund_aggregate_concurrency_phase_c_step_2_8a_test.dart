import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/customer_refund_test_keys.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_refund_settlement_service.dart';
import 'package:lez_pos/features/customers/utils/customer_refund_settlement_messages.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  late AppDatabase db;
  late CustomerRefundSettlementService settlementService;
  late int customerId;
  late int productId;
  const returnedByUserId = 1;

  setUp(() async {
    db = AppDatabase.test();
    settlementService = CustomerRefundSettlementService(db);

    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('Aggregate Customer')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Aggregate Product'),
            barcode: Value('AGG-1'),
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

  Future<double> refundTotal([int? cid]) async {
    final rows = await (db.select(db.customerTransactions)
          ..where((t) =>
              t.customerId.equals(cid ?? customerId) & t.type.equals('REFUND')))
        .get();
    return rows.fold<double>(0, (sum, row) => sum + row.amount);
  }

  Future<int> createCreditInvoice({
    required int customer,
    required double debtAmount,
  }) async {
    final id = await db.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('AGG-${DateTime.now().microsecondsSinceEpoch}'),
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

  Future<void> seedAggregateCredit(double credit) async {
    await createCreditInvoice(
      customer: customerId,
      debtAmount: credit,
    );
    await db.customerAccountsDao.recordPayment(
      customerId: customerId,
      amount: credit * 2,
      note: 'overpayment seed',
    );
    expect(await balance(), closeTo(-credit, 0.001));
  }

  Future<int> seedLinkedReturn({required double returnTotal}) async {
    final invoiceId = await createCreditInvoice(
      customer: customerId,
      debtAmount: returnTotal,
    );
    await db.customerAccountsDao.recordPayment(
      customerId: customerId,
      amount: returnTotal,
      note: 'pay before return',
    );
    await db.returnsDao.returnFullSaleInvoice(
      invoiceId,
      note: 'linked return seed',
      returnedByUserId: returnedByUserId,
    );
    final returns = await db.select(db.customerReturns).get();
    return returns.last.id;
  }

  group('Phase C Step 2.8A aggregate credit concurrency', () {
    test('A) single refund within aggregate credit passes', () async {
      await seedAggregateCredit(100);
      await settlementService.settleCredit(
        
            idempotencyKey: refundTestIdempotencyKey(),customerId: customerId,
        amount: 40,
      );
      expect(await refundTxnCount(), 1);
      expect(await refundTotal(), 40);
      expect(await balance(), closeTo(-60, 0.001));
    });

    test('B) single refund exactly equal to aggregate credit passes', () async {
      await seedAggregateCredit(100);
      await settlementService.settleCredit(
        
            idempotencyKey: refundTestIdempotencyKey(),customerId: customerId,
        amount: 100,
      );
      expect(await refundTxnCount(), 1);
      expect(await balance(), closeTo(0, 0.001));
    });

    test('C) single refund exceeding aggregate credit fails', () async {
      await seedAggregateCredit(100);
      await expectLater(
        settlementService.settleCredit(
          
            idempotencyKey: refundTestIdempotencyKey(),customerId: customerId,
          amount: 100.01,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.amountExceedsCredit,
          ),
        ),
      );
      expect(await refundTxnCount(), 0);
      expect(await balance(), closeTo(-100, 0.001));
    });

    test('D) two sequential refunds within aggregate credit both pass',
        () async {
      await seedAggregateCredit(100);
      await settlementService.settleCredit(
        
            idempotencyKey: refundTestIdempotencyKey(),customerId: customerId,
        amount: 40,
      );
      await settlementService.settleCredit(
        
            idempotencyKey: refundTestIdempotencyKey(),customerId: customerId,
        amount: 40,
      );
      expect(await refundTxnCount(), 2);
      expect(await refundTotal(), 80);
      expect(await balance(), closeTo(-20, 0.001));
    });

    test('E) two concurrent refunds exceeding aggregate - not both succeed',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}c28a_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 5000');
      rawB.execute('PRAGMA busy_timeout = 5000');
      addTearDown(() {
        rawA.dispose();
        rawB.dispose();
        File(dbPath).deleteSync();
      });

      final dbA = AppDatabase.test(NativeDatabase.opened(rawA));
      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final serviceA = CustomerRefundSettlementService(dbA);
      final serviceB = CustomerRefundSettlementService(dbB);

      final cid = await dbA.into(dbA.customers).insert(
            const CustomersCompanion(name: Value('Concurrent Customer')),
          );
      await dbA.customerAccountsDao.recordReturnInTransaction(
        customerId: cid,
        amount: 100,
        returnId: 999,
        note: 'shared credit seed',
      );

      final results = await Future.wait<bool>([
        () async {
          try {
            await serviceA.settleCredit(
            idempotencyKey: refundTestIdempotencyKey(),customerId: cid, amount: 60);
            return true;
          } on CustomerRefundSettlementException {
            return false;
          }
        }(),
        () async {
          try {
            await serviceB.settleCredit(
            idempotencyKey: refundTestIdempotencyKey(),customerId: cid, amount: 60);
            return true;
          } on CustomerRefundSettlementException {
            return false;
          }
        }(),
      ]);

      expect(results.where((ok) => ok).length, 1);

      final count = await (dbA.select(dbA.customerTransactions)
            ..where((t) => t.customerId.equals(cid) & t.type.equals('REFUND')))
          .get();
      expect(count.length, 1);
      expect(count.single.amount, 60);
      expect(
        await dbA.customerAccountsDao.getBalance(cid),
        closeTo(-40, 0.001),
      );
    });

    test('F) different returnIds share one aggregate credit pool', () async {
      final returnA = await seedLinkedReturn(returnTotal: 100);
      final returnB = await seedLinkedReturn(returnTotal: 100);
      await db.customerAccountsDao.adjustBalance(
        customerId: customerId,
        signedAmount: 100,
        reason: 'limit aggregate pool for cross-return test',
      );
      expect(await balance(), closeTo(-100, 0.001));

      await settlementService.settleCredit(
        
            idempotencyKey: refundTestIdempotencyKey(),customerId: customerId,
        amount: 60,
        returnId: returnA,
      );
      await expectLater(
        settlementService.settleCredit(
          
            idempotencyKey: refundTestIdempotencyKey(),customerId: customerId,
          amount: 50,
          returnId: returnB,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.amountExceedsCredit,
          ),
        ),
      );
      expect(await refundTxnCount(), 1);
      expect(await refundTotal(), 60);
    });

    test('G) linked then unlinked refunds share aggregate credit', () async {
      final returnId = await seedLinkedReturn(returnTotal: 100);

      await settlementService.settleCredit(
        
            idempotencyKey: refundTestIdempotencyKey(),customerId: customerId,
        amount: 60,
        returnId: returnId,
      );
      await expectLater(
        settlementService.settleCredit(
          
            idempotencyKey: refundTestIdempotencyKey(),customerId: customerId,
          amount: 50,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.amountExceedsCredit,
          ),
        ),
      );
      expect(await refundTxnCount(), 1);
    });

    test('H) failed aggregate guard commits no REFUND row', () async {
      await seedAggregateCredit(50);
      await expectLater(
        settlementService.settleCredit(
          
            idempotencyKey: refundTestIdempotencyKey(),customerId: customerId,
          amount: 60,
        ),
        throwsA(isA<CustomerRefundSettlementException>()),
      );
      expect(await refundTxnCount(), 0);
      expect(await balance(), closeTo(-50, 0.001));
    });

    test('I) Step 2.7B per-return cap remains enforced', () async {
      final returnId = await seedLinkedReturn(returnTotal: 100);
      await expectLater(
        settlementService.settleCredit(
          
            idempotencyKey: refundTestIdempotencyKey(),customerId: customerId,
          amount: 101,
          returnId: returnId,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.amountExceedsReturnRefundableAmount,
          ),
        ),
      );
      expect(await refundTxnCount(), 0);
    });

    test('J) per-return failure after REFUND insert rolls back REFUND',
        () async {
      final returnId = await seedLinkedReturn(returnTotal: 100);
      final racingService = CustomerRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int customerId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          await db.customerAccountsDao.recordRefundInTransaction(
            customerId: customerId,
            amount: amount,
            returnId: returnId,
            note: note ?? '',
          );
          await db.customStatement(
            'UPDATE customer_returns SET settled_amount = 100 WHERE id = ?',
            [returnId],
          );
          final row = await db.customSelect(
            'SELECT last_insert_rowid() AS id',
          ).getSingle();
          return row.read<int>('id');
        },
      );

      await expectLater(
        racingService.settleCredit(
          idempotencyKey: refundTestIdempotencyKey(),
          customerId: customerId,
          amount: 50,
          returnId: returnId,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.amountExceedsReturnRefundableAmount,
          ),
        ),
      );
      expect(await refundTxnCount(), 0);
    });

    test('K) aggregate guard rejects second insert in same transaction',
        () async {
      await seedAggregateCredit(100);
      try {
        await db.transaction(() async {
          final first = await db.customerAccountsDao
              .recordRefundInTransactionIfWithinAggregateCredit(
            customerId: customerId,
            amount: 60,
          );
          final second = await db.customerAccountsDao
              .recordRefundInTransactionIfWithinAggregateCredit(
            customerId: customerId,
            amount: 60,
          );
          expect(first, isNotNull);
          expect(second, isNull);
          throw StateError('rollback probe');
        });
      } on StateError catch (_) {
        // expected rollback
      }
      expect(await refundTxnCount(), 0);
      expect(await balance(), closeTo(-100, 0.001));
    });

    test('L) customer ID 1 behavior unchanged - no credit refund path',
        () async {
      const generalCustomerId = 1;
      await expectLater(
        settlementService.settleCredit(
          
            idempotencyKey: refundTestIdempotencyKey(),customerId: generalCustomerId,
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
      final rows = await (db.select(db.customerTransactions)
            ..where((t) =>
                t.customerId.equals(generalCustomerId) &
                t.type.equals('REFUND')))
          .get();
      expect(rows, isEmpty);
    });

    test('M) unlinked profile-style refund still works', () async {
      await seedAggregateCredit(100);
      await settlementService.settleCredit(
        
            idempotencyKey: refundTestIdempotencyKey(),customerId: customerId,
        amount: 25,
        returnId: null,
      );
      expect(await refundTxnCount(), 1);
      final rows = await (db.select(db.customerTransactions)
            ..where((t) =>
                t.customerId.equals(customerId) & t.type.equals('REFUND')))
          .get();
      expect(rows.single.referenceId, isNull);
    });

    test('N) linked return detail refund still works', () async {
      final returnId = await seedLinkedReturn(returnTotal: 100);
      await settlementService.settleCredit(
        
            idempotencyKey: refundTestIdempotencyKey(),customerId: customerId,
        amount: 30,
        returnId: returnId,
      );
      expect(await refundTxnCount(), 1);
      final rows = await (db.select(db.customerTransactions)
            ..where((t) => t.type.equals('REFUND')))
          .get();
      expect(rows.single.referenceId, returnId);
      final header = await db.returnsDao.getCustomerReturnById(returnId);
      expect(header!.settledAmount, closeTo(30, 0.001));
    });

    test(
        'O) invoice-style unlinked refund path unchanged with Arabic message reuse',
        () async {
      await seedAggregateCredit(80);
      await settlementService.settleCredit(
        
            idempotencyKey: refundTestIdempotencyKey(),customerId: customerId,
        amount: 20,
      );
      expect(await refundTxnCount(), 1);
      expect(
        customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.amountExceedsCredit,
        ),
        customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.amountExceedsCredit,
        ),
      );
    });
  });
}
