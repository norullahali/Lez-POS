import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/customer_refund_test_keys.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_refund_settlement_service.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
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
          const CustomersCompanion(name: Value('Idempotency Customer')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Idempotency Product'),
            barcode: Value('CRI-1'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  Future<double> balance([AppDatabase? database, int? cid]) {
    final target = database ?? db;
    return target.customerAccountsDao.getBalance(cid ?? customerId);
  }

  Future<int> refundTxnCount([AppDatabase? database, int? cid]) async {
    final target = database ?? db;
    final rows = await (target.select(target.customerTransactions)
          ..where((t) =>
              t.customerId.equals(cid ?? customerId) & t.type.equals('REFUND')))
        .get();
    return rows.length;
  }

  Future<int> idempotencyRowCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.customerRefundIdempotency).get()).length;
  }

  Future<int> createCreditInvoice({
    required AppDatabase database,
    required int customer,
    double debtAmount = 100,
  }) async {
    final id = await database.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('CRI-${DateTime.now().microsecondsSinceEpoch}'),
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
      await database.customerAccountsDao.recordSale(
        customerId: customer,
        amount: debtAmount,
        invoiceId: id,
        note: 'test credit sale',
      );
    }

    return id;
  }

  Future<void> seedCredit100([AppDatabase? database]) async {
    final target = database ?? db;
    await createCreditInvoice(
      database: target,
      customer: customerId,
      debtAmount: 100,
    );
    await target.customerAccountsDao.recordPayment(
      customerId: customerId,
      amount: 200,
      note: 'overpayment',
    );
    expect(await balance(target), closeTo(-100, 0.001));
  }

  Future<int> postReturnCredit100([AppDatabase? database]) async {
    final target = database ?? db;
    final invoiceId = await createCreditInvoice(
      database: target,
      customer: customerId,
      debtAmount: 100,
    );
    await target.customerAccountsDao.recordPayment(
      customerId: customerId,
      amount: 100,
      note: 'pay before return',
    );
    expect(await balance(target), closeTo(0, 0.001));

    await target.returnsDao.returnFullSaleInvoice(
      invoiceId,
      note: 'full return',
      returnedByUserId: returnedByUserId,
    );
    expect(await balance(target), closeTo(-100, 0.001));

    final returns = await target.select(target.customerReturns).get();
    return returns.single.id;
  }

  Future<int> seedAdditionalLinkedReturn([AppDatabase? database]) async {
    final target = database ?? db;
    final invoiceId = await createCreditInvoice(
      database: target,
      customer: customerId,
      debtAmount: 100,
    );
    await target.customerAccountsDao.recordPayment(
      customerId: customerId,
      amount: 100,
      note: 'pay before second return',
    );
    expect(await balance(target), closeTo(-100, 0.001));

    await target.returnsDao.returnFullSaleInvoice(
      invoiceId,
      note: 'second full return',
      returnedByUserId: returnedByUserId,
    );
    expect(await balance(target), closeTo(-200, 0.001));

    final returns = await (target.select(target.customerReturns)
          ..orderBy([(r) => OrderingTerm.desc(r.id)]))
        .get();
    return returns.first.id;
  }

  Future<bool> idempotencyTableExists(AppDatabase database) async {
    final rows = await database.customSelect(
      '''
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'customer_refund_idempotency'
      ''',
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> idempotencyIndexExists(AppDatabase database) async {
    final rows = await database.customSelect(
      '''
      SELECT name FROM sqlite_master
      WHERE type = 'index' AND name = 'cri_customer_created_idx'
      ''',
    ).get();
    return rows.isNotEmpty;
  }

  Future<sqlite3.Database> openSimulatedV33RawDatabase() async {
    final rawDb = sqlite3.sqlite3.openInMemory();
    final bootstrap = AppDatabase.test(NativeDatabase.opened(rawDb));
    await bootstrap.close();
    rawDb.execute('DROP TABLE IF EXISTS customer_refund_idempotency');
    rawDb.execute('DROP INDEX IF EXISTS cri_customer_created_idx');
    rawDb.userVersion = 33;
    return rawDb;
  }

  group('Phase C Step 3.0 customer refund idempotency', () {
    test('A) same key sequential replay', () async {
      await seedCredit100();
      final key = refundTestIdempotencyKey();

      final first = await settlementService.settleCredit(
        customerId: customerId,
        amount: 40,
        idempotencyKey: key,
        note: 'first attempt',
      );
      final second = await settlementService.settleCredit(
        customerId: customerId,
        amount: 40,
        idempotencyKey: key,
        note: 'first attempt',
      );

      expect(first.idempotentReplay, isFalse);
      expect(second.idempotentReplay, isTrue);
      expect(second.customerTransactionId, first.customerTransactionId);
      expect(await refundTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('B) same key concurrent two connections', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}c30b_${DateTime.now().microsecondsSinceEpoch}.db';
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
            const CustomersCompanion(name: Value('Concurrent Idempotency')),
          );
      await dbA.customerAccountsDao.recordReturnInTransaction(
        customerId: cid,
        amount: 100,
        returnId: 999,
        note: 'shared credit seed',
      );

      final sharedKey = refundTestIdempotencyKey();
      final results = await Future.wait<CustomerRefundSettlementResult>([
        serviceA.settleCredit(
          customerId: cid,
          amount: 60,
          idempotencyKey: sharedKey,
        ),
        serviceB.settleCredit(
          customerId: cid,
          amount: 60,
          idempotencyKey: sharedKey,
        ),
      ]);

      expect(await refundTxnCount(dbA, cid), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(results.map((r) => r.customerTransactionId).toSet().length, 1);
      expect(results.where((r) => r.idempotentReplay).length, 1);
      expect(results.where((r) => !r.idempotentReplay).length, 1);
    });

    test('C) same key different amount conflicts with zero second mutation',
        () async {
      await seedCredit100();
      final key = refundTestIdempotencyKey();
      await settlementService.settleCredit(
        customerId: customerId,
        amount: 40,
        idempotencyKey: key,
      );

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 50,
          idempotencyKey: key,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.idempotencyKeyConflict,
          ),
        ),
      );

      expect(await refundTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await balance(), closeTo(-60, 0.001));
    });

    test('D) same key different returnId conflicts', () async {
      final returnIdA = await postReturnCredit100();
      final returnIdB = await seedAdditionalLinkedReturn();
      final key = refundTestIdempotencyKey();

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 20,
        idempotencyKey: key,
        returnId: returnIdA,
      );

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 20,
          idempotencyKey: key,
          returnId: returnIdB,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.idempotencyKeyConflict,
          ),
        ),
      );

      expect(await refundTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('E) different keys same returnId - two refunds and settled_amount',
        () async {
      final returnId = await postReturnCredit100();
      final keyA = refundTestIdempotencyKey();
      final keyB = refundTestIdempotencyKey();

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 30,
        idempotencyKey: keyA,
        returnId: returnId,
      );
      await settlementService.settleCredit(
        customerId: customerId,
        amount: 20,
        idempotencyKey: keyB,
        returnId: returnId,
      );

      expect(await refundTxnCount(), 2);
      expect(await idempotencyRowCount(), 2);
      final header = await db.returnsDao.getCustomerReturnById(returnId);
      expect(header!.settledAmount, closeTo(50, 0.001));
    });

    test('F) K1=50 and K2=50 against cap=100 both succeed', () async {
      final returnId = await postReturnCredit100();
      await settlementService.settleCredit(
        customerId: customerId,
        amount: 50,
        idempotencyKey: refundTestIdempotencyKey(),
        returnId: returnId,
      );
      await settlementService.settleCredit(
        customerId: customerId,
        amount: 50,
        idempotencyKey: refundTestIdempotencyKey(),
        returnId: returnId,
      );

      expect(await refundTxnCount(), 2);
      final header = await db.returnsDao.getCustomerReturnById(returnId);
      expect(header!.settledAmount, closeTo(100, 0.001));
    });

    test('G) unlinked refund same key replay - one REFUND only', () async {
      await seedCredit100();
      final key = refundTestIdempotencyKey();

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 25,
        idempotencyKey: key,
        returnId: null,
      );
      final replay = await settlementService.settleCredit(
        customerId: customerId,
        amount: 25,
        idempotencyKey: key,
        returnId: null,
      );

      expect(replay.idempotentReplay, isTrue);
      expect(await refundTxnCount(), 1);
      final rows = await (db.select(db.customerTransactions)
            ..where((t) => t.type.equals('REFUND')))
          .get();
      expect(rows.single.referenceId, isNull);
    });
    test(
        'H) failure before idempotency insert - rollback and key remains retryable',
        () async {
      await seedCredit100();
      final key = refundTestIdempotencyKey();

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 0,
          idempotencyKey: key,
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
      expect(await idempotencyRowCount(), 0);

      final retry = await settlementService.settleCredit(
        customerId: customerId,
        amount: 40,
        idempotencyKey: key,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await refundTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test(
        'I) failure after REFUND but before completion - rollback without orphan idempotency row',
        () async {
      await seedCredit100();
      final key = refundTestIdempotencyKey();
      final failingService =
          CustomerRefundSettlementService(db, postRefundHook: () async {
        throw Exception('forced post-refund failure');
      });

      await expectLater(
        failingService.settleCredit(
          customerId: customerId,
          amount: 40,
          idempotencyKey: key,
        ),
        throwsA(isA<CustomerRefundSettlementException>()),
      );

      expect(await refundTxnCount(), 0);
      expect(await idempotencyRowCount(), 0);
      expect(await balance(), closeTo(-100, 0.001));

      final retry = await settlementService.settleCredit(
        customerId: customerId,
        amount: 40,
        idempotencyKey: key,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await refundTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('J) replay returns original customerTransactionId', () async {
      await seedCredit100();
      final key = refundTestIdempotencyKey();
      final original = await settlementService.settleCredit(
        customerId: customerId,
        amount: 15,
        idempotencyKey: key,
        note: 'stable note',
      );
      final replay = await settlementService.settleCredit(
        customerId: customerId,
        amount: 15,
        idempotencyKey: key,
        note: 'stable note',
      );

      expect(replay.idempotentReplay, isTrue);
      expect(replay.customerTransactionId, original.customerTransactionId);
    });

    test('K) same key different note conflicts', () async {
      await seedCredit100();
      final key = refundTestIdempotencyKey();
      await settlementService.settleCredit(
        customerId: customerId,
        amount: 20,
        idempotencyKey: key,
        note: 'note A',
      );

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 20,
          idempotencyKey: key,
          note: 'note B',
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.idempotencyKeyConflict,
          ),
        ),
      );

      expect(await refundTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('L) same key same note with whitespace normalization replays',
        () async {
      await seedCredit100();
      final key = refundTestIdempotencyKey();
      final first = await settlementService.settleCredit(
        customerId: customerId,
        amount: 20,
        idempotencyKey: key,
        note: ' padded note ',
      );
      final second = await settlementService.settleCredit(
        customerId: customerId,
        amount: 20,
        idempotencyKey: key,
        note: 'padded note',
      );

      expect(first.idempotentReplay, isFalse);
      expect(second.idempotentReplay, isTrue);
      expect(second.customerTransactionId, first.customerTransactionId);
      expect(await refundTxnCount(), 1);
    });

    test('M) schema v33 to v34 migration creates idempotency table and index',
        () async {
      final rawDb = await openSimulatedV33RawDatabase();
      addTearDown(rawDb.dispose);

      expect(rawDb.userVersion, 33);
      final before = rawDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='customer_refund_idempotency'",
      );
      expect(before, isEmpty);

      final migrated = AppDatabase.test(NativeDatabase.opened(rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 34);
      expect(await idempotencyTableExists(migrated), isTrue);
      expect(await idempotencyIndexExists(migrated), isTrue);
    });

    test('N) fresh install schema v34 includes idempotency table', () async {
      expect(db.schemaVersion, 34);
      expect(await idempotencyTableExists(db), isTrue);
      expect(await idempotencyIndexExists(db), isTrue);
    });

    test('O) historical REFUND rows remain valid without idempotency record',
        () async {
      await seedCredit100();
      await db.customerAccountsDao.recordRefundInTransaction(
        customerId: customerId,
        amount: 30,
        note: 'legacy refund',
      );
      expect(await idempotencyRowCount(), 0);
      expect(await refundTxnCount(), 1);
      expect(await balance(), closeTo(-70, 0.001));

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 40,
        idempotencyKey: refundTestIdempotencyKey(),
      );

      expect(await refundTxnCount(), 2);
      expect(await idempotencyRowCount(), 1);
      expect(await balance(), closeTo(-30, 0.001));
    });

    test(
        'P) real concurrent same-key SQLite - one REFUND and deterministic replay',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}c30p_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 10000');
      rawB.execute('PRAGMA busy_timeout = 10000');
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
            const CustomersCompanion(name: Value('Same Key Concurrent')),
          );
      await dbA.customerAccountsDao.recordReturnInTransaction(
        customerId: cid,
        amount: 80,
        returnId: 1001,
        note: 'concurrent seed',
      );

      final sameKey =
          'fixed-idempotency-key-${DateTime.now().microsecondsSinceEpoch}';
      final outcomes = await Future.wait<CustomerRefundSettlementResult>([
        serviceA.settleCredit(
          customerId: cid,
          amount: 35,
          idempotencyKey: sameKey,
          note: 'concurrent op',
        ),
        serviceB.settleCredit(
          customerId: cid,
          amount: 35,
          idempotencyKey: sameKey,
          note: 'concurrent op',
        ),
      ]);

      expect(await refundTxnCount(dbA, cid), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(outcomes.map((r) => r.customerTransactionId).toSet().length, 1);
      expect(
        outcomes.every(
          (r) =>
              r.customerTransactionId == outcomes.first.customerTransactionId,
        ),
        isTrue,
      );
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(outcomes.where((r) => !r.idempotentReplay).length, 1);

      final ledger = FinancialLedgerRepository(dbA);
      const ledgerFilter = CashLedgerFilter(
        page: 0,
        pageSize: 1000,
        dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
      );
      final refundLedgerEvents = (await ledger.getEntries(ledgerFilter))
          .entries
          .where((e) => e.eventType == CashLedgerEventType.customerRefund)
          .toList();
      expect(refundLedgerEvents.length, 1);
      expect(refundLedgerEvents.single.amount, 35);
    });
  });
}
