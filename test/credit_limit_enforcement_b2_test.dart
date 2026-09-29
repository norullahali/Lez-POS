import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/credit_limit_exception.dart';
import 'package:lez_pos/core/services/pos_sale_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:uuid/uuid.dart';

const _b2TestUuid = Uuid();
String b2IdempotencyKey() => _b2TestUuid.v4();
const b2Fingerprint = 'b2-test-fingerprint';

void main() {
  late AppDatabase db;
  late PosSaleService saleService;
  late int customerId;
  late int productId;

  setUp(() async {
    db = AppDatabase.test();
    saleService = PosSaleService(db);

    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(
            name: Value('Credit Limit Customer'),
            creditLimit: Value(100),
          ),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Test Product'),
            barcode: Value('B2-PROD-1'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  Future<double> ledgerBalance([int? cid]) =>
      db.customerAccountsDao.calculateBalanceFromTransactions(cid ?? customerId);

  Future<int> saleTxnCount([int? cid]) async {
    final rows = await (db.select(db.customerTransactions)
          ..where((t) =>
              t.customerId.equals(cid ?? customerId) & t.type.equals('SALE')))
        .get();
    return rows.length;
  }

  Future<int> invoiceCount() async {
    final rows = await db.select(db.salesInvoices).get();
    return rows.length;
  }

  Future<double> productStock() async {
    final row = await (db.select(db.products)
          ..where((p) => p.id.equals(productId)))
        .getSingle();
    return row.currentStock;
  }

  Future<void> seedExposure(double amount, {int? cid}) async {
    await db.customerAccountsDao.recordSale(
      customerId: cid ?? customerId,
      amount: amount,
      invoiceId: 0,
      note: 'seed exposure',
    );
  }

  Future<int> runCreditSale(
    double debtAmount, {
    int? cid,
  }) async {
    final targetCustomer = cid ?? customerId;
    final result = await saleService.processSale(
      idempotencyKey: b2IdempotencyKey(),
      fingerprintHash: b2Fingerprint,
      invoice: SalesInvoicesCompanion(
        subtotal: Value(debtAmount),
        total: Value(debtAmount),
        paymentMethod: const Value('DEBT'),
        cashPaid: const Value(0),
        debtAmount: Value(debtAmount),
        customerId: Value(targetCustomer),
      ),
      items: [
        SaleItemsCompanion(
          productId: Value(productId),
          quantity: const Value(1),
          unitPrice: Value(debtAmount),
          unitCost: const Value(5),
          total: Value(debtAmount),
        ),
      ],
      debtAmount: debtAmount,
      netSaleTotal: debtAmount,
    );
    return result.invoiceId;
  }

  Future<int> runCashSale(double amount, {int? cid}) async {
    final result = await saleService.processSale(
      idempotencyKey: b2IdempotencyKey(),
      fingerprintHash: b2Fingerprint,
      invoice: SalesInvoicesCompanion(
        subtotal: Value(amount),
        total: Value(amount),
        paymentMethod: const Value('CASH'),
        cashPaid: Value(amount),
        debtAmount: const Value(0),
        customerId: Value(cid ?? customerId),
      ),
      items: [
        SaleItemsCompanion(
          productId: Value(productId),
          quantity: const Value(1),
          unitPrice: Value(amount),
          unitCost: const Value(5),
          total: Value(amount),
        ),
      ],
      debtAmount: 0,
      netSaleTotal: amount,
    );
    return result.invoiceId;
  }

  group('B2 credit limit enforcement', () {
    test('1) credit sale under limit succeeds', () async {
      await runCreditSale(50);
      expect(await ledgerBalance(), closeTo(50, 0.001));
      expect(await saleTxnCount(), 1);
      expect(await invoiceCount(), 1);
    });

    test('2) credit sale exactly at limit succeeds', () async {
      await runCreditSale(100);
      expect(await ledgerBalance(), closeTo(100, 0.001));
      expect(await saleTxnCount(), 1);
    });

    test('3) credit sale over limit is rejected', () async {
      await expectLater(
        runCreditSale(101),
        throwsA(isA<CreditLimitExceededException>()),
      );
      expect(await ledgerBalance(), closeTo(0, 0.001));
      expect(await saleTxnCount(), 0);
      expect(await invoiceCount(), 0);
    });

    test('4) cash sale unaffected by credit limit', () async {
      await (db.update(db.customers)..where((c) => c.id.equals(customerId)))
          .write(const CustomersCompanion(creditLimit: Value(10)));
      await runCashSale(50);
      expect(await ledgerBalance(), closeTo(0, 0.001));
      expect(await saleTxnCount(), 0);
      expect(await invoiceCount(), 1);
    });

    test('5) existing customer exposure is included', () async {
      await seedExposure(60);
      await runCreditSale(40);
      expect(await ledgerBalance(), closeTo(100, 0.001));
      expect(await saleTxnCount(), 2);

      await expectLater(
        runCreditSale(1),
        throwsA(isA<CreditLimitExceededException>()),
      );
      expect(await ledgerBalance(), closeTo(100, 0.001));
    });

    test('6) customer payment increases available credit', () async {
      await seedExposure(80);
      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 30,
        note: 'partial payment',
      );
      expect(await ledgerBalance(), closeTo(50, 0.001));
      await runCreditSale(50);
      expect(await ledgerBalance(), closeTo(100, 0.001));
    });

    test('7) customer return reduces exposure correctly', () async {
      await seedExposure(90);
      await db.customerAccountsDao.recordReturn(
        customerId: customerId,
        amount: 20,
        returnId: 1,
        note: 'return seed',
      );
      expect(await ledgerBalance(), closeTo(70, 0.001));
      await runCreditSale(30);
      expect(await ledgerBalance(), closeTo(100, 0.001));
    });

    test('8) rejected credit sale leaves no partial database state', () async {
      final stockBefore = await productStock();
      final invoicesBefore = await invoiceCount();
      final saleTxnsBefore = await saleTxnCount();
      final ledgerBefore = await ledgerBalance();

      await expectLater(
        runCreditSale(150),
        throwsA(isA<CreditLimitExceededException>()),
      );

      expect(await productStock(), stockBefore);
      expect(await invoiceCount(), invoicesBefore);
      expect(await saleTxnCount(), saleTxnsBefore);
      expect(await ledgerBalance(), closeTo(ledgerBefore, 0.001));

      final ledgerRows = await db.select(db.stockLedger).get();
      expect(ledgerRows, isEmpty);
    });

    test('9) concurrent credit sales cannot exceed aggregate limit', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b2_${DateTime.now().microsecondsSinceEpoch}.db';
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

      final serviceA = PosSaleService(dbA);
      final serviceB = PosSaleService(dbB);

      final cid = await dbA.into(dbA.customers).insert(
            const CustomersCompanion(
              name: Value('Concurrent Credit Customer'),
              creditLimit: Value(100),
            ),
          );
      final pid = await dbA.into(dbA.products).insert(
            const ProductsCompanion(
              name: Value('Concurrent Product'),
              barcode: Value('B2-CONC-1'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
          );

      Future<int> concurrentSale(PosSaleService service) async {
        for (var attempt = 0; attempt < 20; attempt++) {
          try {
            final result = await service.processSale(
              idempotencyKey: b2IdempotencyKey(),
              fingerprintHash: b2Fingerprint,
              invoice: SalesInvoicesCompanion(
                subtotal: const Value(60),
                total: const Value(60),
                paymentMethod: const Value('DEBT'),
                cashPaid: const Value(0),
                debtAmount: const Value(60),
                customerId: Value(cid),
              ),
              items: [
                SaleItemsCompanion(
                  productId: Value(pid),
                  quantity: const Value(1),
                  unitPrice: const Value(60),
                  unitCost: const Value(5),
                  total: const Value(60),
                ),
              ],
              debtAmount: 60,
              netSaleTotal: 60,
            );
            return result.invoiceId;
          } on SqliteException catch (e) {
            if (e.resultCode != 5) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        }
        throw StateError('concurrent credit sale remained locked');
      }

      final results = await Future.wait<bool>([
        () async {
          try {
            await concurrentSale(serviceA);
            return true;
          } on CreditLimitExceededException {
            return false;
          }
        }(),
        () async {
          try {
            await concurrentSale(serviceB);
            return true;
          } on CreditLimitExceededException {
            return false;
          }
        }(),
      ]);

      expect(results.where((ok) => ok).length, 1);

      final exposure = await dbA.customerAccountsDao
          .calculateBalanceFromTransactions(cid);
      expect(exposure, lessThanOrEqualTo(100));
      expect(exposure, closeTo(60, 0.001));

      final saleRows = await (dbA.select(dbA.customerTransactions)
            ..where((t) => t.customerId.equals(cid) & t.type.equals('SALE')))
          .get();
      expect(saleRows.length, 1);
      expect(saleRows.single.amount, 60);
    });

    test('10) credit_limit <= 0 remains unlimited', () async {
      await (db.update(db.customers)..where((c) => c.id.equals(customerId)))
          .write(const CustomersCompanion(creditLimit: Value(0)));
      await runCreditSale(500);
      expect(await ledgerBalance(), closeTo(500, 0.001));

      await (db.update(db.customers)..where((c) => c.id.equals(customerId)))
          .write(const CustomersCompanion(creditLimit: Value(-1)));
      await runCreditSale(500);
      expect(await ledgerBalance(), closeTo(1000, 0.001));
    });

    test('11) general customer id=1 behavior remains unchanged', () async {
      // Default seed creates walk-in customer id=1 (general customer).
      await (db.update(db.customers)..where((c) => c.id.equals(1))).write(
            const CustomersCompanion(creditLimit: Value(10)),
          );

      final invoiceId = await runCreditSale(200, cid: 1);
      expect(invoiceId, greaterThan(0));

      final generalSaleTxns = await (db.select(db.customerTransactions)
            ..where((t) => t.customerId.equals(1) & t.type.equals('SALE')))
          .get();
      expect(generalSaleTxns, isEmpty);
    });
  });
}
