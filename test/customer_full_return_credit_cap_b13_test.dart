import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/constants/invoice_lifecycle.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  const returnedByUserId = 1;
  const unitPrice = 10.0;
  const ledgerFilter = CashLedgerFilter(
    page: 0,
    pageSize: 1000,
    dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
  );

  late AppDatabase db;
  late PartialReturnService partialService;
  late FinancialLedgerRepository ledger;
  late int customerId;
  late int productId;
  late int saleItemId;
  late int invoiceId;

  Future<void> seedCreditInvoice({
    required AppDatabase target,
    double debtAmount = 100,
    double cashPaid = 0,
    double saleQty = 10,
    int? productOverride,
  }) async {
    final pid = productOverride ?? productId;
    final goodsTotal = saleQty * unitPrice;
    invoiceId = await target.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('B13-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: Value(goodsTotal),
        total: Value(goodsTotal),
        debtAmount: Value(debtAmount),
        cashPaid: Value(cashPaid),
        customerId: Value(customerId),
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
    if (debtAmount > 0) {
      await target.customerAccountsDao.recordSale(
        customerId: customerId,
        amount: debtAmount,
        invoiceId: invoiceId,
        note: 'B13 credit sale',
      );
    }
  }

  PartialReturnLine returnLine({required double quantity, int? itemId}) =>
      PartialReturnLine(
        saleItemId: itemId ?? saleItemId,
        productId: productId,
        quantity: quantity,
        unitPrice: unitPrice,
        unitCost: 5,
      );

  Future<double> returnCreditTotal([AppDatabase? target]) async {
    final database = target ?? db;
    return database.customerAccountsDao.getCreditReversalTotalForSaleInvoice(
      customerId: customerId,
      invoiceId: invoiceId,
    );
  }

  Future<int> returnTxnCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await (database.select(database.customerTransactions)
              ..where((t) => t.type.equals('RETURN')))
            .get())
        .length;
  }

  Future<int> customerReturnHeaderCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await (database.select(database.customerReturns)
              ..where((t) => t.originalInvoiceId.equals(invoiceId)))
            .get())
        .length;
  }

  Future<int> customerReturnItemCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await database.select(database.customerReturnItems).get()).length;
  }

  Future<int> saleItemReturnCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await database.select(database.saleItemReturns).get()).length;
  }

  Future<double> productStock([AppDatabase? target]) async {
    final database = target ?? db;
    return database.stockDao.getStock(productId);
  }

  Future<Object?> runPartialReturn(
    PartialReturnService targetService, {
    required double quantity,
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        await targetService.processPartialReturn(
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [returnLine(quantity: quantity)],
          note: 'B13 test',
        );
        return true;
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
    throw StateError('B13 partial return exhausted busy retries');
  }

  Future<Object?> runFullReturn(AppDatabase targetDb) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        final id = await targetDb.returnsDao.returnFullSaleInvoice(
          invoiceId,
          note: 'B13 full return',
          returnedByUserId: returnedByUserId,
        );
        return id;
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
    throw StateError('B13 full return exhausted busy retries');
  }

  setUp(() async {
    db = AppDatabase.test();
    partialService = PartialReturnService(db);
    ledger = FinancialLedgerRepository(db);
    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('B13 Credit Customer')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('B13 Product'),
            barcode: Value('B13-PROD'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
    await seedCreditInvoice(target: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('B13 full return credit cap', () {
    test('1) concurrent partial 60 + fresh full never exceeds debt 100',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b13_cc_${DateTime.now().microsecondsSinceEpoch}.db';
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
      customerId = await dbA.into(dbA.customers).insert(
            const CustomersCompanion(name: Value('B13 Concurrent Customer')),
          );
      productId = await dbA.into(dbA.products).insert(
            const ProductsCompanion(
              name: Value('B13 Concurrent Product'),
              barcode: Value('B13-CONCURRENT'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
          );
      await seedCreditInvoice(target: dbA, debtAmount: 100);
      await dbA.customStatement('PRAGMA busy_timeout = 5000');

      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      await dbB.customStatement('PRAGMA busy_timeout = 5000');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final partialServiceA = PartialReturnService(dbA);

      await Future.wait<Object?>([
        runPartialReturn(partialServiceA, quantity: 6),
        runFullReturn(dbB),
      ]);

      final totalCredit =
          await dbA.customerAccountsDao.getCreditReversalTotalForSaleInvoice(
        customerId: customerId,
        invoiceId: invoiceId,
      );
      expect(totalCredit, lessThanOrEqualTo(100.0001));
      expect(totalCredit, isNot(closeTo(160, 0.001)));
      expect(totalCredit, greaterThan(0));
    });

    test('2) financial invariant SUM(ABS(RETURN)) <= debt_amount', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 6)],
      );
      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'B13 invariant',
        returnedByUserId: returnedByUserId,
      );

      final inv = await db.salesDao.getInvoiceById(invoiceId);
      final totalCredit = await returnCreditTotal();
      expect(totalCredit, lessThanOrEqualTo(inv!.debtAmount + 0.0001));
    });

    test('3) sequential partial 60 then full return totals 100 credit',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 6)],
      );
      expect(await returnCreditTotal(), closeTo(60, 0.001));

      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'B13 sequential full',
        returnedByUserId: returnedByUserId,
      );

      expect(await returnCreditTotal(), closeTo(100, 0.001));
      expect(await saleItemReturnCount(), 2);
      final inv = await db.salesDao.getInvoiceById(invoiceId);
      expect(inv!.invoiceStatus, InvoiceLifecycleStatus.returned);
    });

    test('4) two concurrent fresh full returns only one succeeds', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b13_ff_${DateTime.now().microsecondsSinceEpoch}.db';
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
      customerId = await dbA.into(dbA.customers).insert(
            const CustomersCompanion(name: Value('B13 Full Concurrent')),
          );
      productId = await dbA.into(dbA.products).insert(
            const ProductsCompanion(
              name: Value('B13 Full Product'),
              barcode: Value('B13-FULL'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
          );
      await seedCreditInvoice(target: dbA, debtAmount: 100);
      await dbA.customStatement('PRAGMA busy_timeout = 5000');

      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      await dbB.customStatement('PRAGMA busy_timeout = 5000');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final stockBefore = await productStock(dbA);
      final outcomes = await Future.wait<Object?>([
        runFullReturn(dbA),
        runFullReturn(dbB),
      ]);

      final successes = outcomes.whereType<int>().where((id) => id >= 0);
      final failures = outcomes.whereType<StateError>();
      expect(successes.length, 1);
      expect(failures.length, 1);
      expect(await customerReturnHeaderCount(dbA), 1);
      expect(await returnTxnCount(dbA), 1);
      expect(await returnCreditTotal(dbA), closeTo(100, 0.001));
      expect(await productStock(dbA), closeTo(stockBefore + 10, 0.001));
      expect(await customerReturnItemCount(dbA), 1);
    });

    test('5) fresh full return on cash-only invoice creates zero RETURN rows',
        () async {
      await seedCreditInvoice(target: db, debtAmount: 0, cashPaid: 100);
      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'B13 cash full',
        returnedByUserId: returnedByUserId,
      );

      expect(await returnTxnCount(), 0);
      expect(await returnCreditTotal(), 0);
      expect(await customerReturnHeaderCount(), 1);
    });

    test('6) fresh full return on mixed invoice reverses debtAmount only',
        () async {
      await seedCreditInvoice(target: db, debtAmount: 50, cashPaid: 50);
      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'B13 mixed full',
        returnedByUserId: returnedByUserId,
      );

      expect(await returnCreditTotal(), closeTo(50, 0.001));
      expect(await returnCreditTotal(), lessThanOrEqualTo(50.0001));
      expect(await customerReturnHeaderCount(), 1);
    });

    test('7) fresh full succeeds without RETURN when guarded credit is null',
        () async {
      db.returnsDao.fullReturnCreditHook = ({
        required int customerId,
        required int invoiceId,
        required double proposedAmount,
        required int returnId,
        String note = '',
      }) async {
        // Simulates B12 clip-to-zero (null insert) on fresh full path.
      };

      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'B13 null credit clip',
        returnedByUserId: returnedByUserId,
      );

      expect(await returnTxnCount(), 0);
      expect(await returnCreditTotal(), 0);
      expect(await customerReturnHeaderCount(), 1);
      expect(await productStock(), closeTo(100, 0.001));
      final inv = await db.salesDao.getInvoiceById(invoiceId);
      expect(inv!.invoiceStatus, InvoiceLifecycleStatus.returned);
    });

    test('8) partial aborts when full return wins race', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b13_race_${DateTime.now().microsecondsSinceEpoch}.db';
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
      customerId = await dbA.into(dbA.customers).insert(
            const CustomersCompanion(name: Value('B13 Race Customer')),
          );
      productId = await dbA.into(dbA.products).insert(
            const ProductsCompanion(
              name: Value('B13 Race Product'),
              barcode: Value('B13-RACE'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
          );
      await seedCreditInvoice(target: dbA, debtAmount: 100);
      await dbA.customStatement('PRAGMA busy_timeout = 5000');

      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      await dbB.customStatement('PRAGMA busy_timeout = 5000');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final stockBefore = await productStock(dbA);
      final partialServiceA = PartialReturnService(dbA);

      final outcomes = await Future.wait<Object?>([
        runPartialReturn(partialServiceA, quantity: 4),
        runFullReturn(dbB),
      ]);

      expect(await productStock(dbA), closeTo(stockBefore + 10, 0.001));
      expect(await productStock(dbA), isNot(closeTo(stockBefore + 14, 0.001)));
      expect(await returnCreditTotal(dbA), closeTo(100, 0.001));

      final fullOutcome = outcomes[1];
      final partialOutcome = outcomes[0];
      expect(fullOutcome, isA<int>());
      if (partialOutcome is StateError) {
        expect(await saleItemReturnCount(dbA), 0);
      } else {
        expect(partialOutcome, true);
        expect(await saleItemReturnCount(dbA), greaterThan(0));
      }
    });

    test('9) B11 linkage parity for full and partial RETURN references',
        () async {
      final firstInvoiceId = invoiceId;
      await partialService.processPartialReturn(
        saleInvoiceId: firstInvoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 4)],
      );
      expect(await returnCreditTotal(), closeTo(40, 0.001));

      final partialRows = await (db.select(db.customerTransactions)
            ..where((t) => t.type.equals('RETURN')))
          .get();
      expect(partialRows.length, 1);
      final partialRef = partialRows.single.referenceId;
      final sir = await (db.select(db.saleItemReturns)
            ..where((t) => t.id.equals(partialRef!)))
          .getSingleOrNull();
      expect(sir, isNotNull);
      expect(sir!.saleInvoiceId, firstInvoiceId);
      expect(partialRows.single.amount.abs(), closeTo(40, 0.001));

      await seedCreditInvoice(target: db, debtAmount: 100);
      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'B13 full linkage',
        returnedByUserId: returnedByUserId,
      );
      expect(await returnCreditTotal(), closeTo(100, 0.001));

      final allReturnRows = await (db.select(db.customerTransactions)
            ..where((t) => t.type.equals('RETURN')))
          .get();
      expect(allReturnRows.length, 2);
      final fullTxn = allReturnRows.last;
      final fullHeader =
          await db.returnsDao.getCustomerReturnById(fullTxn.referenceId!);
      expect(fullHeader, isNotNull);
      expect(fullHeader!.originalInvoiceId, invoiceId);
      expect(fullTxn.amount.abs(), closeTo(100, 0.001));

      final page = await ledger.getEntries(ledgerFilter);
      final returnRefund = page.entries
          .where((e) => e.eventType == CashLedgerEventType.returnRefund)
          .toList();
      expect(returnRefund, isEmpty);
    });

    test('10) credit hook failure rolls back entire fresh return', () async {
      db.returnsDao.fullReturnCreditHook = ({
        required int customerId,
        required int invoiceId,
        required double proposedAmount,
        required int returnId,
        String note = '',
      }) async {
        throw Exception('forced full return credit failure');
      };

      final stockBefore = await productStock();

      await expectLater(
        db.returnsDao.returnFullSaleInvoice(
          invoiceId,
          note: 'B13 rollback',
          returnedByUserId: returnedByUserId,
        ),
        throwsA(isA<Exception>()),
      );

      expect(await customerReturnHeaderCount(), 0);
      expect(await customerReturnItemCount(), 0);
      expect(await returnTxnCount(), 0);
      expect(await productStock(), stockBefore);
      expect((await db.select(db.returnAuditLogs).get()).length, 0);
      final inv = await db.salesDao.getInvoiceById(invoiceId);
      expect(inv!.invoiceStatus, isNot(InvoiceLifecycleStatus.returned));
    });
  });
}
