import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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
  late PartialReturnService service;
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
        invoiceNumber: Value('B12-${DateTime.now().microsecondsSinceEpoch}'),
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
        note: 'B12 credit sale',
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

  Future<double> absReturnTxnTotal([AppDatabase? target]) async {
    final database = target ?? db;
    final rows = await (database.select(database.customerTransactions)
          ..where((t) => t.type.equals('RETURN')))
        .get();
    return rows.fold<double>(0, (sum, row) => sum + row.amount.abs());
  }

  Future<int> returnTxnCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await (database.select(database.customerTransactions)
              ..where((t) => t.type.equals('RETURN')))
            .get())
        .length;
  }

  Future<int> saleItemReturnCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await database.select(database.saleItemReturns).get()).length;
  }

  Future<Object?> runPartialReturn(
    PartialReturnService targetService, {
    required double quantity,
    int? itemId,
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        await targetService.processPartialReturn(
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [returnLine(quantity: quantity, itemId: itemId)],
          note: 'B12 test',
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
    throw StateError('B12 partial return exhausted busy retries');
  }

  setUp(() async {
    db = AppDatabase.test();
    service = PartialReturnService(db);
    ledger = FinancialLedgerRepository(db);
    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('B12 Credit Customer')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('B12 Product'),
            barcode: Value('B12-PROD'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
    await seedCreditInvoice(target: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('B12 partial return credit cap', () {
    test('1) single partial credit return inserts proposed RETURN', () async {
      await service.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 4)],
      );

      expect(await returnCreditTotal(), closeTo(40, 0.001));
      expect(await returnTxnCount(), 1);
    });

    test('2) sequential 40 + 60 on debt 100 totals 100', () async {
      await service.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 4)],
      );
      await service.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 6)],
      );

      expect(await returnCreditTotal(), closeTo(100, 0.001));
      expect(await returnTxnCount(), 2);
    });

    test('3) sequential 40 + 30 + 30 on debt 100 totals 100', () async {
      await service.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 4)],
      );
      await service.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 3)],
      );
      await service.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 3)],
      );

      expect(await returnCreditTotal(), closeTo(100, 0.001));
      expect(await returnTxnCount(), 3);
    });

    test('4) after credit cap exhausted partial return skips RETURN row',
        () async {
      await seedCreditInvoice(target: db, debtAmount: 100);
      await service.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 6)],
      );
      expect(await returnCreditTotal(), closeTo(60, 0.001));

      await db.transaction(() async {
        final sirId = await db.saleItemReturnsDao
            .insertSaleItemReturnIfWithinSaleLineCap(
          saleInvoiceId: invoiceId,
          saleItemId: saleItemId,
          productId: productId,
          returnedQuantity: 2,
          unitPriceAtReturn: unitPrice,
          returnTotal: 20,
          returnedByUserId: returnedByUserId,
        );
        expect(sirId, isNotNull);
        final inserted = await db.customerAccountsDao
            .recordReturnInTransactionIfWithinInvoiceCreditCap(
          customerId: customerId,
          invoiceId: invoiceId,
          proposedAmount: 40,
          referenceId: sirId!,
          note: 'B12 cap exhaustion setup',
        );
        expect(inserted, isNotNull);
      });
      expect(await returnCreditTotal(), closeTo(100, 0.001));

      await service.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 2)],
        note: 'after cap exhausted',
      );

      expect(await returnCreditTotal(), closeTo(100, 0.001));
      expect(await returnTxnCount(), 2);
      expect(await saleItemReturnCount(), 3);
    });

    test('5) dual-connection concurrent 6 + 6 never exceeds debt 100',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b12_cc_${DateTime.now().microsecondsSinceEpoch}.db';
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
            const CustomersCompanion(name: Value('B12 Concurrent Customer')),
          );
      productId = await dbA.into(dbA.products).insert(
            const ProductsCompanion(
              name: Value('B12 Concurrent Product'),
              barcode: Value('B12-CONCURRENT'),
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

      final serviceA = PartialReturnService(dbA);
      final serviceB = PartialReturnService(dbB);

      final outcomes = await Future.wait<Object?>([
        runPartialReturn(serviceA, quantity: 6),
        runPartialReturn(serviceB, quantity: 6),
      ]);

      expect(outcomes.whereType<bool>().length, greaterThan(0));

      final totalCredit =
          await dbA.customerAccountsDao.getCreditReversalTotalForSaleInvoice(
        customerId: customerId,
        invoiceId: invoiceId,
      );
      expect(totalCredit, lessThanOrEqualTo(100.0001));
      expect(totalCredit, isNot(closeTo(120, 0.001)));
      expect(totalCredit, greaterThan(0));
    });

    test('6) quantity rejection leaves no partial artifacts', () async {
      await service.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 6)],
      );

      await expectLater(
        service.processPartialReturn(
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [returnLine(quantity: 6)],
        ),
        throwsA(isA<StateError>()),
      );

      expect(await saleItemReturnCount(), 1);
      expect(await returnTxnCount(), 1);
      expect(await returnCreditTotal(), closeTo(60, 0.001));
    });

    test('7) cash-only partial return creates zero RETURN rows', () async {
      await seedCreditInvoice(target: db, debtAmount: 0, cashPaid: 100);
      await service.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 4)],
      );

      expect(await returnTxnCount(), 0);
      expect(await returnCreditTotal(), 0);
      expect(await saleItemReturnCount(), 1);
    });

    test('8) mixed invoice uses proportional credit capped by debtAmount',
        () async {
      await seedCreditInvoice(target: db, debtAmount: 50, cashPaid: 50);
      await service.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 5)],
      );

      expect(await returnCreditTotal(), closeTo(25, 0.001));
      expect(await returnCreditTotal(), lessThanOrEqualTo(50.0001));
    });

    test('9) B11 ledger partial credit still suppresses RETURN_REFUND',
        () async {
      await service.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 4)],
      );

      final page = await ledger.getEntries(ledgerFilter);
      final returnRefund = page.entries
          .where((e) => e.eventType == CashLedgerEventType.returnRefund)
          .toList();
      expect(returnRefund, isEmpty);
    });

    test('10) read helper matches inserted RETURN total', () async {
      await service.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 4)],
      );

      expect(
        await returnCreditTotal(),
        closeTo(await absReturnTxnTotal(), 0.001),
      );
    });

    test('11) sequential 60 then proposed 60 clips second RETURN to 40',
        () async {
      await service.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 6)],
      );
      expect(await returnCreditTotal(), closeTo(60, 0.001));

      final secondSirId = await db.into(db.saleItemReturns).insert(
            SaleItemReturnsCompanion.insert(
              saleInvoiceId: invoiceId,
              saleItemId: saleItemId,
              productId: productId,
              returnedQuantity: 6,
              unitPriceAtReturn: unitPrice,
              returnTotal: 60,
              returnedByUserId: returnedByUserId,
            ),
          );

      await db.transaction(() async {
        final inserted = await db.customerAccountsDao
            .recordReturnInTransactionIfWithinInvoiceCreditCap(
          customerId: customerId,
          invoiceId: invoiceId,
          proposedAmount: 60,
          referenceId: secondSirId,
          note: 'B12 clip verification',
        );
        expect(inserted, isNotNull);
      });

      expect(await returnCreditTotal(), closeTo(100, 0.001));

      final rows = await (db.select(db.customerTransactions)
            ..where((t) => t.type.equals('RETURN'))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
      expect(rows.length, 2);
      expect(rows[0].amount.abs(), closeTo(60, 0.001));
      expect(rows[1].amount.abs(), closeTo(40, 0.001));
    });

    test('12) credit poster failure rolls back entire partial return',
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

      final stockBefore = await db.stockDao.getStock(productId);

      await expectLater(
        failingService.processPartialReturn(
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [returnLine(quantity: 4)],
        ),
        throwsA(isA<Exception>()),
      );

      expect(await saleItemReturnCount(), 0);
      expect(await returnTxnCount(), 0);
      expect(await db.stockDao.getStock(productId), stockBefore);
      expect(
        (await db.select(db.returnAuditLogs).get()).length,
        0,
      );
    });
  });
}
