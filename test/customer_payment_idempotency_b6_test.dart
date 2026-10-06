import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_account_service.dart';
import 'package:lez_pos/core/services/customer_payment_idempotency_conflict_exception.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/pos/repositories/pos_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/customer_payment_test_keys.dart';

Future<({sqlite3.Database rawDb, String path})> openSimulatedV37RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b6_v37_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement(
      'DROP TABLE IF EXISTS customer_payment_idempotency');
  await bootstrap.customStatement('DROP INDEX IF EXISTS cpi_customer_created_idx');
  await bootstrap.customStatement('PRAGMA user_version = 37');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 37);
  return (rawDb: rawDb, path: dbPath);
}

void main() {
  late AppDatabase db;
  late CustomerAccountService paymentService;
  late int customerId;
  late int productId;

  setUp(() async {
    db = AppDatabase.test();
    paymentService = CustomerAccountService(db);
    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('B6 Payment Customer')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('B6 Product'),
            barcode: Value('B6-P'),
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

  Future<int> paymentTxnCount([AppDatabase? database, int? cid]) async {
    final target = database ?? db;
    return (await (target.select(target.customerTransactions)
          ..where((t) =>
              t.customerId.equals(cid ?? customerId) & t.type.equals('PAYMENT')))
        .get())
        .length;
  }

  Future<int> idempotencyRowCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.customerPaymentIdempotency).get()).length;
  }

  Future<bool> idempotencyTableExists(AppDatabase database) async {
    final rows = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='customer_payment_idempotency'",
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> idempotencyIndexExists(AppDatabase database) async {
    final rows = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='index' "
      "AND name='cpi_customer_created_idx'",
    ).get();
    return rows.isNotEmpty;
  }

  Future<int> customerPaymentLedgerCount([AppDatabase? database]) async {
    final target = database ?? db;
    final ledger = FinancialLedgerRepository(target);
    const ledgerFilter = CashLedgerFilter(
      page: 0,
      pageSize: 1000,
      dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
    );
    return (await ledger.getEntries(ledgerFilter))
        .entries
        .where((e) => e.eventType == CashLedgerEventType.customerPayment)
        .length;
  }

  Future<void> seedDebt({
    AppDatabase? database,
    int? cid,
    double amount = 100,
  }) async {
    final target = database ?? db;
    final customer = cid ?? customerId;
    final invoiceId = await target.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('B6-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: Value(amount),
        total: Value(amount),
        debtAmount: Value(amount),
        customerId: Value(customer),
        paymentMethod: const Value('DEBT'),
      ),
      items: [
        {'productId': productId, 'qty': 1.0, 'price': amount, 'cost': 1.0},
      ],
    );
    await target.customerAccountsDao.recordSale(
      customerId: customer,
      amount: amount,
      invoiceId: invoiceId,
      note: 'seed debt',
    );
  }

  group('B6 customer payment idempotency', () {
    test('1) first payment succeeds', () async {
      await seedDebt();
      final key = b6PaymentIdempotencyKey();
      final result = await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 40,
        note: 'دفعة نقدية',
      );

      expect(result.idempotentReplay, isFalse);
      expect(await paymentTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await balance(), closeTo(60, 0.001));
    });

    test('2) same key replay returns same transaction ID', () async {
      await seedDebt();
      final key = b6PaymentIdempotencyKey();
      final first = await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 25,
        note: 'دفعة نقدية',
      );
      final second = await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 25,
        note: 'دفعة نقدية',
      );

      expect(second.idempotentReplay, isTrue);
      expect(second.customerTransactionId, first.customerTransactionId);
    });

    test('3) same key creates only one PAYMENT row', () async {
      await seedDebt();
      final key = b6PaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 30,
        note: 'note',
      );
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 30,
        note: 'note',
      );
      expect(await paymentTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('4) same key + different amount -> conflict', () async {
      await seedDebt();
      final key = b6PaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 20,
        note: 'note',
      );

      await expectLater(
        paymentService.processPayment(
          idempotencyKey: key,
          customerId: customerId,
          amount: 21,
          note: 'note',
        ),
        throwsA(isA<CustomerPaymentIdempotencyConflictException>()),
      );
      expect(await paymentTxnCount(), 1);
    });

    test('5) same key + different note -> conflict', () async {
      await seedDebt();
      final key = b6PaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 20,
        note: 'first note',
      );

      await expectLater(
        paymentService.processPayment(
          idempotencyKey: key,
          customerId: customerId,
          amount: 20,
          note: 'second note',
        ),
        throwsA(isA<CustomerPaymentIdempotencyConflictException>()),
      );
      expect(await paymentTxnCount(), 1);
    });

    test('6) different keys + identical payment data -> two payments', () async {
      await seedDebt(amount: 200);
      await paymentService.processPayment(
        idempotencyKey: b6PaymentIdempotencyKey(),
        customerId: customerId,
        amount: 50,
        note: 'دفعة نقدية',
      );
      await paymentService.processPayment(
        idempotencyKey: b6PaymentIdempotencyKey(),
        customerId: customerId,
        amount: 50,
        note: 'دفعة نقدية',
      );

      expect(await paymentTxnCount(), 2);
      expect(await idempotencyRowCount(), 2);
      expect(await balance(), closeTo(100, 0.001));
    });

    test('7) validation failure -> no idempotency row', () async {
      final key = b6PaymentIdempotencyKey();
      await expectLater(
        paymentService.processPayment(
          idempotencyKey: key,
          customerId: customerId,
          amount: 0,
          note: 'bad',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await paymentTxnCount(), 0);
      expect(await idempotencyRowCount(), 0);
    });

    test('8) failure before seal -> rollback and retryable key', () async {
      await seedDebt();
      final key = b6PaymentIdempotencyKey();
      final failingService = CustomerAccountService(
        db,
        preSealHook: () async {
          throw Exception('forced seal failure');
        },
      );

      await expectLater(
        failingService.processPayment(
          idempotencyKey: key,
          customerId: customerId,
          amount: 15,
          note: 'retry me',
        ),
        throwsA(isA<Exception>()),
      );
      expect(await paymentTxnCount(), 0);
      expect(await idempotencyRowCount(), 0);

      final retry = await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 15,
        note: 'retry me',
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await paymentTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('9) dual-connection same-key concurrency', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b6_conc_${DateTime.now().microsecondsSinceEpoch}.db';
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

      final cid = await dbA.into(dbA.customers).insert(
            const CustomersCompanion(name: Value('Concurrent Payer')),
          );
      await dbA.customerAccountsDao.recordSale(
        customerId: cid,
        amount: 100,
        invoiceId: 9001,
        note: 'seed',
      );

      final serviceA = CustomerAccountService(dbA);
      final serviceB = CustomerAccountService(dbB);
      final sameKey = b6PaymentIdempotencyKey();

      final outcomes = await Future.wait([
        serviceA.processPayment(
          idempotencyKey: sameKey,
          customerId: cid,
          amount: 35,
          note: 'concurrent',
        ),
        serviceB.processPayment(
          idempotencyKey: sameKey,
          customerId: cid,
          amount: 35,
          note: 'concurrent',
        ),
      ]);

      expect(await paymentTxnCount(dbA, cid), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(outcomes.map((r) => r.customerTransactionId).toSet().length, 1);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(outcomes.where((r) => !r.idempotentReplay).length, 1);
    });

    test('10) final customer balance correct after replay', () async {
      await seedDebt(amount: 80);
      final key = b6PaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 30,
        note: 'balance test',
      );
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 30,
        note: 'balance test',
      );
      expect(await balance(), closeTo(50, 0.001));
    });

    test('11) financial ledger shows one CUSTOMER_PAYMENT after replay',
        () async {
      await seedDebt();
      final key = b6PaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 22,
        note: 'ledger',
      );
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 22,
        note: 'ledger',
      );
      expect(await customerPaymentLedgerCount(), 1);
    });

    test('12) intentional overpayment remains allowed', () async {
      await seedDebt(amount: 50);
      final result = await paymentService.processPayment(
        idempotencyKey: b6PaymentIdempotencyKey(),
        customerId: customerId,
        amount: 80,
        note: 'overpay',
      );
      expect(result.idempotentReplay, isFalse);
      expect(await balance(), closeTo(-30, 0.001));
    });

    test('13) migration v37 -> v38 creates table and index', () async {
      final opened = await openSimulatedV37RawDatabase();
      addTearDown(opened.rawDb.dispose);

      final before = opened.rawDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='customer_payment_idempotency'",
      );
      expect(before, isEmpty);

      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 46);
      expect(await idempotencyTableExists(migrated), isTrue);
      expect(await idempotencyIndexExists(migrated), isTrue);
    });

    test('14) fresh schema v41 includes table and index', () async {
      expect(db.schemaVersion, 46);
      expect(await idempotencyTableExists(db), isTrue);
      expect(await idempotencyIndexExists(db), isTrue);
    });

    test('15) F6 PosRepository.settleDebt uses canonical service', () async {
      await seedDebt();
      final repo = PosRepository(db, CustomerAccountService(db));
      final key = b6PaymentIdempotencyKey();
      final result = await repo.settleDebt(
        idempotencyKey: key,
        customerId: customerId,
        amount: 25,
        note: 'تسوية دين من POS',
      );
      expect(result.idempotentReplay, isFalse);
      final replay = await repo.settleDebt(
        idempotencyKey: key,
        customerId: customerId,
        amount: 25,
        note: 'تسوية دين من POS',
      );
      expect(replay.idempotentReplay, isTrue);
      expect(replay.customerTransactionId, result.customerTransactionId);
      expect(await paymentTxnCount(), 1);
    });
  });
}
