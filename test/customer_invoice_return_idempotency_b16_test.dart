import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/activity/activity_types.dart';
import 'package:lez_pos/core/constants/invoice_lifecycle.dart';
import 'package:lez_pos/core/constants/movement_types.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_invoice_return_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/customer_invoice_return_fingerprint.dart';
import 'package:lez_pos/core/services/customer_invoice_return_posting_result.dart';
import 'package:lez_pos/core/services/customer_invoice_return_service.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/customer_invoice_return_posting_helpers.dart';
import 'support/customer_invoice_return_test_keys.dart';

Future<({sqlite3.Database rawDb, String path})> openSimulatedV43RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b16_v43_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement(
    'DROP TABLE IF EXISTS customer_invoice_return_idempotency',
  );
  await bootstrap.customStatement('PRAGMA user_version = 43');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 43);
  return (rawDb: rawDb, path: dbPath);
}

void main() {
  const returnedByUserId = 1;
  const unitPrice = 10.0;
  const defaultPartialQty = 2.0;

  late AppDatabase db;
  late CustomerInvoiceReturnService service;
  late int customerId;
  late int productId;
  late int saleItemId;
  late int invoiceId;

  Future<void> seedCreditInvoice({
    required AppDatabase target,
    double debtAmount = 100,
    double cashPaid = 0,
    double saleQty = 10,
    int? customerOverride,
    int? productOverride,
  }) async {
    final pid = productOverride ?? productId;
    final goodsTotal = saleQty * unitPrice;
    invoiceId = await target.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('B16-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: Value(goodsTotal),
        total: Value(goodsTotal),
        debtAmount: Value(debtAmount),
        cashPaid: Value(cashPaid),
        customerId: customerOverride != null
            ? Value(customerOverride)
            : Value(customerId),
        paymentMethod: Value(cashPaid > 0 ? 'MIXED' : 'DEBT'),
      ),
      items: [
        {
          'productId': pid,
          'qty': saleQty,
          'price': unitPrice,
          'cost': 5.0,
        },
      ],
    );
    saleItemId =
        (await target.salesDao.getItemsForInvoice(invoiceId)).single.id;
    if (debtAmount > 0 && customerOverride != null) {
      await target.customerAccountsDao.recordSale(
        customerId: customerOverride,
        amount: debtAmount,
        invoiceId: invoiceId,
        note: 'B16 credit sale',
      );
    } else if (debtAmount > 0) {
      await target.customerAccountsDao.recordSale(
        customerId: customerId,
        amount: debtAmount,
        invoiceId: invoiceId,
        note: 'B16 credit sale',
      );
    }
  }

  CustomerInvoicePartialReturnLine partialLine(
    double qty, {
    int? itemId,
  }) =>
      CustomerInvoicePartialReturnLine(
        saleItemId: itemId ?? saleItemId,
        quantity: qty,
      );

  List<CustomerInvoicePartialReturnLine> defaultPartialLines([
    double qty = defaultPartialQty,
  ]) =>
      [partialLine(qty)];

  Future<int> idempotencyRowCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.customerInvoiceReturnIdempotency).get())
        .length;
  }

  Future<int> customerReturnCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.customerReturns).get()).length;
  }

  Future<int> saleItemReturnCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.saleItemReturns).get()).length;
  }

  Future<int> returnTxnCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await (target.select(target.customerTransactions)
              ..where((t) => t.type.equals('RETURN')))
            .get())
        .length;
  }

  Future<int> returnInLedgerCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await (target.select(target.stockLedger)
              ..where(
                (l) => l.movementType.equals(StockMovementType.returnIn.code),
              ))
            .get())
        .length;
  }

  Future<int> activityLogCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await (target.select(target.activityLogs)
              ..where(
                (l) => l.activityType.isIn([
                  ActivityTypes.returnPartial,
                  ActivityTypes.returnFull,
                ]),
              ))
            .get())
        .length;
  }

  Future<double> returnCreditTotal([AppDatabase? database]) async {
    final target = database ?? db;
    return target.customerAccountsDao.getCreditReversalTotalForSaleInvoice(
      customerId: customerId,
      invoiceId: invoiceId,
    );
  }

  Future<double> productStock([AppDatabase? database]) async {
    final target = database ?? db;
    return target.stockDao.getStock(productId);
  }

  Future<bool> idempotencyTableExists(AppDatabase database) async {
    final rows = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='customer_invoice_return_idempotency'",
    ).get();
    return rows.isNotEmpty;
  }

  Future<void> seedConcurrentDatabase(AppDatabase target) async {
    customerId = await target.into(target.customers).insert(
          const CustomersCompanion(name: Value('B16 Concurrent Customer')),
        );
    productId = await target.into(target.products).insert(
          const ProductsCompanion(
            name: Value('B16 Concurrent Product'),
            barcode: Value('B16-CONCURRENT'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
    await seedCreditInvoice(target: target);
  }

  Future<Object?> _tryPostPartial(
    CustomerInvoiceReturnService targetService, {
    required String idempotencyKey,
    List<CustomerInvoicePartialReturnLine>? lines,
    String? note,
  }) async {
    try {
      return await postPartialCustomerInvoiceReturn(
        targetService,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: lines ?? defaultPartialLines(),
        note: note,
        idempotencyKey: idempotencyKey,
      );
    } on CustomerInvoiceReturnIdempotencyConflictException {
      return 'conflict';
    }
  }

  Future<Object?> _tryPostFull(
    CustomerInvoiceReturnService targetService, {
    required String idempotencyKey,
    String note = 'B16 full return',
  }) async {
    try {
      return await postFullCustomerInvoiceReturn(
        targetService,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: note,
        idempotencyKey: idempotencyKey,
      );
    } on CustomerInvoiceReturnIdempotencyConflictException {
      return 'conflict';
    }
  }

  Future<Object?> runPartialWithBusyRetry(
    CustomerInvoiceReturnService targetService, {
    required String idempotencyKey,
    required double quantity,
    String? note,
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await postPartialCustomerInvoiceReturn(
          targetService,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [partialLine(quantity)],
          note: note,
          idempotencyKey: idempotencyKey,
        );
      } on CustomerInvoiceReturnIdempotencyConflictException {
        return 'conflict';
      } on StateError catch (e) {
        return e;
      } catch (e) {
        final message = e.toString();
        final isBusy = message.contains('database is locked') ||
            message.contains('SqliteException(5)');
        if (isBusy && attempt < 7) {
          await Future<void>.delayed(
            Duration(milliseconds: 25 * (attempt + 1)),
          );
          continue;
        }
        rethrow;
      }
    }
    throw StateError('B16 partial exhausted busy retries');
  }

  Future<Object?> runFullWithBusyRetry(
    CustomerInvoiceReturnService targetService, {
    required String idempotencyKey,
    String note = 'B16 concurrent full',
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await postFullCustomerInvoiceReturn(
          targetService,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          note: note,
          idempotencyKey: idempotencyKey,
        );
      } on CustomerInvoiceReturnIdempotencyConflictException {
        return 'conflict';
      } on StateError catch (e) {
        return e;
      } catch (e) {
        final message = e.toString();
        final isBusy = message.contains('database is locked') ||
            message.contains('SqliteException(5)');
        if (isBusy && attempt < 7) {
          await Future<void>.delayed(
            Duration(milliseconds: 25 * (attempt + 1)),
          );
          continue;
        }
        rethrow;
      }
    }
    throw StateError('B16 full exhausted busy retries');
  }

  setUp(() async {
    db = AppDatabase.test();
    service = CustomerInvoiceReturnService(db);
    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('B16 Credit Customer')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('B16 Product'),
            barcode: Value('B16-PROD'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
    await seedCreditInvoice(target: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('B16 customer invoice return idempotency', () {
    test('A) first partial succeeds', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final result = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );

      expect(result.idempotentReplay, isFalse);
      expect(result.customerReturnId, greaterThan(0));
      expect(result.returnType, CustomerInvoiceReturnType.partial);
      expect(result.executionPath, CustomerInvoiceExecutionPath.partialBatch);
      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await saleItemReturnCount(), 1);
      expect(await returnTxnCount(), 1);
      expect(await returnInLedgerCount(), 1);
      expect(await productStock(), closeTo(92, 0.001));
      expect(await activityLogCount(), 1);
    });

    test('B) same key + same fingerprint partial replays', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      final replay = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(replay.idempotentReplay, isTrue);
    });

    test('C) replay returns same customerReturnId', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final first = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      final second = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(second.customerReturnId, first.customerReturnId);
    });

    test('D) replay creates no second customer_returns row', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('E) replay creates no second sale_item_returns row', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(await saleItemReturnCount(), 1);
    });

    test('F) replay creates no second RETURN transaction', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(await returnTxnCount(), 1);
    });

    test('G) same key + different qty conflicts', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      await expectLater(
        postPartialCustomerInvoiceReturn(
          service,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(3),
          idempotencyKey: key,
        ),
        throwsA(isA<CustomerInvoiceReturnIdempotencyConflictException>()),
      );
    });

    test('H) conflict creates no mutation', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      final creditAfterFirst = await returnCreditTotal();
      final stockAfterFirst = await productStock();

      await expectLater(
        postPartialCustomerInvoiceReturn(
          service,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(4),
          idempotencyKey: key,
        ),
        throwsA(isA<CustomerInvoiceReturnIdempotencyConflictException>()),
      );

      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await saleItemReturnCount(), 1);
      expect(await returnTxnCount(), 1);
      expect(await returnInLedgerCount(), 1);
      expect(await returnCreditTotal(), creditAfterFirst);
      expect(await productStock(), stockAfterFirst);
    });

    test('I) sequential retry after successful commit replays', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final first = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(first.idempotentReplay, isFalse);

      final second = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(second.idempotentReplay, isTrue);
      expect(second.customerReturnId, first.customerReturnId);
    });

    test('J) preSealHook failure then retry succeeds fresh', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final failingService = CustomerInvoiceReturnService(
        db,
        preSealHook: () async {
          throw Exception('forced preSeal failure');
        },
      );

      await expectLater(
        postPartialCustomerInvoiceReturn(
          failingService,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(),
          idempotencyKey: key,
        ),
        throwsA(isA<Exception>()),
      );
      expect(await customerReturnCount(), 0);
      expect(await idempotencyRowCount(), 0);

      final retry = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('K) two connections same key same partial commits once', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b16_conc_${DateTime.now().microsecondsSinceEpoch}.db';
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

      await seedConcurrentDatabase(dbA);

      final serviceA = CustomerInvoiceReturnService(dbA);
      final serviceB = CustomerInvoiceReturnService(dbB);
      final sameKey = b16CustomerInvoiceReturnIdempotencyKey();

      final outcomes = await Future.wait([
        postPartialCustomerInvoiceReturn(
          serviceA,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(),
          idempotencyKey: sameKey,
        ),
        postPartialCustomerInvoiceReturn(
          serviceB,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(),
          idempotencyKey: sameKey,
        ),
      ]);

      expect(await customerReturnCount(dbA), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(outcomes.map((r) => r.customerReturnId).toSet().length, 1);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(outcomes.where((r) => !r.idempotentReplay).length, 1);
    });

    test('L) two connections same key different fingerprint one conflict',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b16_conf_${DateTime.now().microsecondsSinceEpoch}.db';
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

      await seedConcurrentDatabase(dbA);

      final serviceA = CustomerInvoiceReturnService(dbA);
      final serviceB = CustomerInvoiceReturnService(dbB);
      final sameKey = b16CustomerInvoiceReturnIdempotencyKey();

      final outcomes = await Future.wait<Object?>([
        _tryPostPartial(serviceA, idempotencyKey: sameKey),
        _tryPostPartial(
          serviceB,
          idempotencyKey: sameKey,
          lines: defaultPartialLines(3),
        ),
      ]);

      expect(await customerReturnCount(dbA), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(outcomes.whereType<CustomerInvoiceReturnPostingResult>().length, 1);
      expect(outcomes.where((o) => o == 'conflict').length, 1);
    });

    test('M) B12 cap for different keys credits at most invoice debt', () async {
      final key1 = b16CustomerInvoiceReturnIdempotencyKey();
      final key2 = b16CustomerInvoiceReturnIdempotencyKey();

      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(6),
        idempotencyKey: key1,
      );
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(4),
        idempotencyKey: key2,
      );

      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 2);
      expect(await saleItemReturnCount(), 2);
      expect(await returnCreditTotal(), closeTo(100, 0.0001));
      expect(await returnTxnCount(), 2);
    });

    test('N) quantity cap rejects second key after full qty returned', () async {
      final capProductId = await db.into(db.products).insert(
            ProductsCompanion(
              name: const Value('B16 Cap Product'),
              barcode: Value(
                'B16-CAP-',
              ),
              currentStock: const Value(100),
              costPrice: const Value(5),
            ),
          );
      await seedCreditInvoice(
        target: db,
        productOverride: capProductId,
        saleQty: 10,
        debtAmount: 100,
      );
      final capInvoiceId = invoiceId;
      final capSaleItemId = saleItemId;

      final key1 = b16CustomerInvoiceReturnIdempotencyKey();
      final key2 = b16CustomerInvoiceReturnIdempotencyKey();

      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: capInvoiceId,
        returnedByUserId: returnedByUserId,
        lines: [partialLine(10, itemId: capSaleItemId)],
        idempotencyKey: key1,
      );

      await expectLater(
        postPartialCustomerInvoiceReturn(
          service,
          saleInvoiceId: capInvoiceId,
          returnedByUserId: returnedByUserId,
          lines: [partialLine(1, itemId: capSaleItemId)],
          idempotencyKey: key2,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('O) credit poster failure rolls back return and idempotency row',
        () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final failingService = CustomerInvoiceReturnService.withCreditPoster(
        db,
        creditPoster: ({
          required int customerId,
          required double amount,
          required int returnId,
          String note = '',
        }) async {
          throw Exception('forced credit poster failure');
        },
      );
      final stockBefore = await productStock();

      await expectLater(
        postPartialCustomerInvoiceReturn(
          failingService,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(),
          idempotencyKey: key,
        ),
        throwsA(isA<Exception>()),
      );

      expect(await customerReturnCount(), 0);
      expect(await idempotencyRowCount(), 0);
      expect(await saleItemReturnCount(), 0);
      expect(await returnTxnCount(), 0);
      expect(await productStock(), stockBefore);
    });

    test('P) migration v43 -> v44 creates customer_invoice_return_idempotency',
        () async {
      final opened = await openSimulatedV43RawDatabase();
      addTearDown(opened.rawDb.dispose);

      final before = opened.rawDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='customer_invoice_return_idempotency'",
      );
      expect(before, isEmpty);

      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 48);
      expect(await idempotencyTableExists(migrated), isTrue);
    });

    test('Q) seal race preSealHook then retry succeeds once', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      var hookCalls = 0;
      final flakyService = CustomerInvoiceReturnService(
        db,
        preSealHook: () async {
          hookCalls++;
          if (hookCalls == 1) {
            throw Exception('forced seal race');
          }
        },
      );

      await expectLater(
        postPartialCustomerInvoiceReturn(
          flakyService,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(),
          idempotencyKey: key,
        ),
        throwsA(isA<Exception>()),
      );
      expect(await customerReturnCount(), 0);
      expect(await idempotencyRowCount(), 0);

      final retry = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('R) duplicate line ordering shares fingerprint and replays', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final unordered = [
        partialLine(2),
        partialLine(1),
      ];
      final ordered = [
        partialLine(1),
        partialLine(2),
      ];

      expect(
        CustomerInvoiceReturnFingerprint.computePartial(
          customerId: customerId,
          saleInvoiceId: invoiceId,
          lines: unordered
              .map(
                (line) => CustomerInvoicePartialReturnLineInput(
                  saleItemId: line.saleItemId,
                  quantity: line.quantity,
                ),
              )
              .toList(),
        ),
        CustomerInvoiceReturnFingerprint.computePartial(
          customerId: customerId,
          saleInvoiceId: invoiceId,
          lines: ordered
              .map(
                (line) => CustomerInvoicePartialReturnLineInput(
                  saleItemId: line.saleItemId,
                  quantity: line.quantity,
                ),
              )
              .toList(),
        ),
      );

      final first = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: unordered,
        idempotencyKey: key,
      );
      final replay = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: ordered,
        idempotencyKey: key,
      );
      expect(first.idempotentReplay, isFalse);
      expect(replay.idempotentReplay, isTrue);
      expect(replay.customerReturnId, first.customerReturnId);
      expect(await customerReturnCount(), 1);
    });

    test('S) different note on same key conflicts', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        note: 'first note',
        idempotencyKey: key,
      );
      await expectLater(
        postPartialCustomerInvoiceReturn(
          service,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(),
          note: 'second note',
          idempotencyKey: key,
        ),
        throwsA(isA<CustomerInvoiceReturnIdempotencyConflictException>()),
      );
    });

    test('T) walk-in cash invoice null customerId idempotency works', () async {
      await seedCreditInvoice(
        target: db,
        debtAmount: 0,
        cashPaid: 100,
      );
      await (db.update(db.salesInvoices)..where((i) => i.id.equals(invoiceId)))
          .write(const SalesInvoicesCompanion(customerId: Value(null)));

      final inv = await db.salesDao.getInvoiceById(invoiceId);
      expect(inv!.customerId, isNull);

      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final first = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(first.idempotentReplay, isFalse);
      expect(await returnTxnCount(), 0);

      final replay = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(replay.customerReturnId, first.customerReturnId);
      expect(await returnTxnCount(), 0);
      expect(await customerReturnCount(), 1);
    });

    test('U) independent partial keys create two returns', () async {
      final key1 = b16CustomerInvoiceReturnIdempotencyKey();
      final key2 = b16CustomerInvoiceReturnIdempotencyKey();
      expect(key1, isNot(equals(key2)));

      final first = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key1,
      );
      final second = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(1),
        idempotencyKey: key2,
      );

      expect(first.idempotentReplay, isFalse);
      expect(second.idempotentReplay, isFalse);
      expect(first.primaryReferenceId, isNot(equals(second.primaryReferenceId)));
      expect(first.customerReturnId, second.customerReturnId);
      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 2);
      expect(await saleItemReturnCount(), 2);
      expect(await returnTxnCount(), 2);
    });

    test('V) empty partial lines rejects before idempotency record', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await expectLater(
        service.processPartialReturn(
          idempotencyKey: key,
          saleInvoiceId: invoiceId,
          lines: const [],
          returnedByUserId: returnedByUserId,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await idempotencyRowCount(), 0);
      expect(await customerReturnCount(), 0);
    });

    test('W) partial then full different keys both succeed', () async {
      final partialKey = b16CustomerInvoiceReturnIdempotencyKey();
      final fullKey = b16CustomerInvoiceReturnIdempotencyKey();

      final partial = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(4),
        idempotencyKey: partialKey,
      );
      final full = await postFullCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: 'B16 partial then full',
        idempotencyKey: fullKey,
      );

      expect(partial.idempotentReplay, isFalse);
      expect(full.idempotentReplay, isFalse);
      expect(full.executionPath, CustomerInvoiceExecutionPath.fullRemaining);
      expect(await idempotencyRowCount(), 2);
      expect(await returnCreditTotal(), closeTo(100, 0.0001));
      final inv = await db.salesDao.getInvoiceById(invoiceId);
      expect(inv!.invoiceStatus, InvoiceLifecycleStatus.returned);
    });

    test('X) first fresh full succeeds fullFresh without sale_item_returns',
        () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final result = await postFullCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: 'B16 fresh full',
        idempotencyKey: key,
      );

      expect(result.idempotentReplay, isFalse);
      expect(result.executionPath, CustomerInvoiceExecutionPath.fullFresh);
      expect(result.customerReturnId, greaterThan(0));
      expect(result.primaryReferenceId, result.customerReturnId);
      expect(await saleItemReturnCount(), 0);
      expect(await customerReturnCount(), 1);
      expect(await returnTxnCount(), 1);
      expect(await activityLogCount(), 1);
    });

    test('Y) fresh full replay keeps ids and creates no sale_item_returns',
        () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      const note = 'B16 fresh full replay';
      final first = await postFullCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: note,
        idempotencyKey: key,
      );
      expect(first.executionPath, CustomerInvoiceExecutionPath.fullFresh);
      expect(await saleItemReturnCount(), 0);

      final replay = await postFullCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: note,
        idempotencyKey: key,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(replay.customerReturnId, first.customerReturnId);
      expect(replay.primaryReferenceId, first.primaryReferenceId);
      expect(replay.executionPath, CustomerInvoiceExecutionPath.fullFresh);
      expect(await saleItemReturnCount(), 0);
      expect(await customerReturnCount(), 1);
    });

    test('Z) full remaining path after partial', () async {
      final partialKey = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(3),
        idempotencyKey: partialKey,
      );

      final fullKey = b16CustomerInvoiceReturnIdempotencyKey();
      final full = await postFullCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: 'B16 full remaining',
        idempotencyKey: fullKey,
      );

      expect(full.executionPath, CustomerInvoiceExecutionPath.fullRemaining);
      expect(full.primaryReferenceId, isNotNull);
      expect(await saleItemReturnCount(), 2);
    });

    test('AA) full remaining replay preserves sealed executionPath and refs',
        () async {
      final partialKey = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(3),
        idempotencyKey: partialKey,
      );

      final fullKey = b16CustomerInvoiceReturnIdempotencyKey();
      const note = 'B16 full remaining replay';
      final first = await postFullCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: note,
        idempotencyKey: fullKey,
      );
      expect(first.executionPath, CustomerInvoiceExecutionPath.fullRemaining);
      final sirAfterFirst = await saleItemReturnCount();

      final replay = await postFullCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: note,
        idempotencyKey: fullKey,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(replay.customerReturnId, first.customerReturnId);
      expect(replay.primaryReferenceId, first.primaryReferenceId);
      expect(replay.executionPath, CustomerInvoiceExecutionPath.fullRemaining);
      expect(await saleItemReturnCount(), sirAfterFirst);
    });

    test('AB) activity log count unchanged on replay', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      final logsAfterFirst = await activityLogCount();

      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(await activityLogCount(), logsAfterFirst);
    });

    test('AC) same key partial then full conflicts', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      await expectLater(
        postFullCustomerInvoiceReturn(
          service,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          note: 'B16 conflict full',
          idempotencyKey: key,
        ),
        throwsA(isA<CustomerInvoiceReturnIdempotencyConflictException>()),
      );
      expect(await idempotencyRowCount(), 1);
    });

    test('AD) B13 race partial then full routes fullRemaining', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b16_race_${DateTime.now().microsecondsSinceEpoch}.db';
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
      await seedConcurrentDatabase(dbA);
      await dbA.customStatement('PRAGMA busy_timeout = 5000');

      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      await dbB.customStatement('PRAGMA busy_timeout = 5000');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final serviceA = CustomerInvoiceReturnService(dbA);
      final serviceB = CustomerInvoiceReturnService(dbB);
      final partialKey = b16CustomerInvoiceReturnIdempotencyKey();
      final fullKey = b16CustomerInvoiceReturnIdempotencyKey();

      final outcomes = await Future.wait<Object?>([
        runPartialWithBusyRetry(
          serviceA,
          idempotencyKey: partialKey,
          quantity: 4,
        ),
        runFullWithBusyRetry(serviceB, idempotencyKey: fullKey),
      ]);

      final fullResult = outcomes
          .whereType<CustomerInvoiceReturnPostingResult>()
          .where((r) => r.returnType == CustomerInvoiceReturnType.full)
          .toList();
      expect(fullResult, isNotEmpty);
      expect(
        fullResult.single.executionPath,
        CustomerInvoiceExecutionPath.fullRemaining,
      );
      expect(await returnCreditTotal(dbA), closeTo(100, 0.0001));
      expect(await idempotencyRowCount(dbA), 2);
    });

    test('AJ) two connections full vs full same key commits once', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b16_full_conc_${DateTime.now().microsecondsSinceEpoch}.db';
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

      await seedConcurrentDatabase(dbA);
      final serviceA = CustomerInvoiceReturnService(dbA);
      final serviceB = CustomerInvoiceReturnService(dbB);
      final sameKey = b16CustomerInvoiceReturnIdempotencyKey();
      const note = 'B16 concurrent fresh full';

      final outcomes = await Future.wait([
        postFullCustomerInvoiceReturn(
          serviceA,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          note: note,
          idempotencyKey: sameKey,
        ),
        postFullCustomerInvoiceReturn(
          serviceB,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          note: note,
          idempotencyKey: sameKey,
        ),
      ]);

      expect(await customerReturnCount(dbA), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(outcomes.map((r) => r.customerReturnId).toSet().length, 1);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(outcomes.where((r) => !r.idempotentReplay).length, 1);
      expect(
        outcomes.singleWhere((r) => !r.idempotentReplay).executionPath,
        CustomerInvoiceExecutionPath.fullFresh,
      );
    });

    test('AK) two connections partial vs partial different keys both commit',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b16_partial_conc_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 15000');
      rawB.execute('PRAGMA busy_timeout = 15000');
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

      await seedConcurrentDatabase(dbA);
      await dbA.customStatement('PRAGMA busy_timeout = 15000');
      await dbB.customStatement('PRAGMA busy_timeout = 15000');

      final serviceA = CustomerInvoiceReturnService(dbA);
      final serviceB = CustomerInvoiceReturnService(dbB);
      final keyA = b16CustomerInvoiceReturnIdempotencyKey();
      final keyB = b16CustomerInvoiceReturnIdempotencyKey();

      final outcomes = await Future.wait([
        postPartialCustomerInvoiceReturn(
          serviceA,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [partialLine(2)],
          idempotencyKey: keyA,
        ),
        postPartialCustomerInvoiceReturn(
          serviceB,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [partialLine(3)],
          idempotencyKey: keyB,
        ),
      ]);

      expect(outcomes, hasLength(2));
      expect(outcomes.every((r) => !r.idempotentReplay), isTrue);
      expect(await customerReturnCount(dbA), 1);
      expect(await idempotencyRowCount(dbA), 2);
      expect(await saleItemReturnCount(dbA), 2);
      expect(await returnCreditTotal(dbA), closeTo(50, 0.0001));
    });
  });
}