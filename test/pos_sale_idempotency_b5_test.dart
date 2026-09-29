import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/credit_limit_exception.dart';
import 'package:lez_pos/core/services/pos_sale_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/pos_sale_fingerprint.dart';
import 'package:lez_pos/core/services/pos_sale_service.dart';
import 'package:lez_pos/core/services/process_sale_result.dart';
import 'package:lez_pos/core/services/settings_service.dart';
import 'package:lez_pos/core/services/stock_guard.dart';
import 'package:lez_pos/features/loyalty/services/loyalty_service.dart';
import 'package:lez_pos/features/pos/models/cart_item.dart';
import 'package:lez_pos/features/products/models/product_model.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite3/sqlite3.dart' show Database, SqliteException;
import 'package:uuid/uuid.dart';

const _b5TestUuid = Uuid();
String b5IdempotencyKey() => _b5TestUuid.v4();

Future<({Database rawDb, String path})> openSimulatedV36RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b5_v36_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement('DROP TABLE IF EXISTS pos_sale_idempotency');
  await bootstrap.customStatement('DROP INDEX IF EXISTS psi_sales_invoice_idx');
  await bootstrap.customStatement('PRAGMA user_version = 36');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 36);
  return (rawDb: rawDb, path: dbPath);
}

void main() {
  late AppDatabase db;
  late PosSaleService saleService;
  late int productId;
  late int customerId;

  setUp(() async {
    db = AppDatabase.test();
    saleService = PosSaleService(db);
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('B5 Product'),
            barcode: Value('B5-PROD-1'),
            currentStock: Value(100),
            costPrice: Value(5),
            sellPrice: Value(10),
          ),
        );
    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(
            name: Value('B5 Customer'),
            creditLimit: Value(100),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  SalesInvoicesCompanion cashHeader({double amount = 10, int? cid}) {
    return SalesInvoicesCompanion(
      subtotal: Value(amount),
      total: Value(amount),
      paymentMethod: const Value('CASH'),
      cashPaid: Value(amount),
      debtAmount: const Value(0),
      customerId: Value(cid),
    );
  }

  List<SaleItemsCompanion> cashItems({double qty = 1, double price = 10}) {
    return [
      SaleItemsCompanion(
        productId: Value(productId),
        quantity: Value(qty),
        unitPrice: Value(price),
        unitCost: const Value(5),
        total: Value(qty * price),
      ),
    ];
  }

  PaymentInfo testPayment({double amount = 10, String? key}) {
    return PaymentInfo(
      method: 'CASH',
      idempotencyKey: key ?? b5IdempotencyKey(),
      cashPaid: amount,
    );
  }

  String fingerprintFor({
    required PaymentInfo payment,
    int? cid,
    double amount = 10,
  }) {
    final product = ProductModel(
      id: productId,
      name: 'B5 Product',
      barcode: 'B5-PROD-1',
      costPrice: 5,
      sellPrice: 10,
    );
    return PosSaleFingerprint.compute(
      sessionId: 1,
      cartSlotId: 1,
      items: [
        CartItem(product: product, quantity: 1, unitPrice: amount),
      ],
      invoiceDiscount: 0,
      loyaltyPointsUsed: payment.pointsUsed,
      loyaltyDiscount: payment.loyaltyDiscount,
      customerId: cid,
      payment: payment,
    );
  }

  Future<ProcessSaleResult> runCashSale({
    String? key,
    String? fingerprint,
    double amount = 10,
    int? cid,
  }) {
    final payment = testPayment(amount: amount, key: key);
    return saleService.processSale(
      idempotencyKey: payment.idempotencyKey,
      fingerprintHash:
          fingerprint ?? fingerprintFor(payment: payment, cid: cid, amount: amount),
      invoice: cashHeader(amount: amount, cid: cid),
      items: cashItems(price: amount),
      debtAmount: 0,
      netSaleTotal: amount,
    );
  }

  Future<int> invoiceCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.salesInvoices).get()).length;
  }

  Future<int> saleItemCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.saleItems).get()).length;
  }

  Future<double> productStock([AppDatabase? database]) async {
    final target = database ?? db;
    final row = await (target.select(target.products)
          ..where((p) => p.id.equals(productId)))
        .getSingle();
    return row.currentStock;
  }

  Future<int> saleTxnCount([AppDatabase? database, int? cid]) async {
    final target = database ?? db;
    final rows = await (target.select(target.customerTransactions)
          ..where((t) =>
              t.customerId.equals(cid ?? customerId) & t.type.equals('SALE')))
        .get();
    return rows.length;
  }

  Future<int> idempotencyRowCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.posSaleIdempotency).get()).length;
  }

  Future<double> loyaltyPoints([AppDatabase? database, int? cid]) async {
    final target = database ?? db;
    return LoyaltyService(target, SettingsService(target))
        .getPoints(cid ?? customerId);
  }

  group('B5 POS sale idempotency', () {
    test('1) normal sale with key succeeds', () async {
      final result = await runCashSale();
      expect(result.idempotentReplay, isFalse);
      expect(result.invoiceNumber, isNotEmpty);
      expect(await invoiceCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('2) sequential same-key retry is idempotent', () async {
      final key = b5IdempotencyKey();
      final payment = testPayment(key: key);
      final fp = fingerprintFor(payment: payment);

      final first = await saleService.processSale(
        idempotencyKey: key,
        fingerprintHash: fp,
        invoice: cashHeader(),
        items: cashItems(),
        debtAmount: 0,
        netSaleTotal: 10,
      );
      final second = await saleService.processSale(
        idempotencyKey: key,
        fingerprintHash: fp,
        invoice: cashHeader(),
        items: cashItems(),
        debtAmount: 0,
        netSaleTotal: 10,
      );

      expect(first.idempotentReplay, isFalse);
      expect(second.idempotentReplay, isTrue);
      expect(second.invoiceId, first.invoiceId);
      expect(second.invoiceNumber, first.invoiceNumber);
      expect(await invoiceCount(), 1);
      expect(await saleItemCount(), 1);
      expect(await productStock(), 99);
      expect(await idempotencyRowCount(), 1);
    });

    test('3) concurrent same-key dual connection yields one sale', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b5_conc_${DateTime.now().microsecondsSinceEpoch}.db';
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

      final pid = await dbA.into(dbA.products).insert(
            const ProductsCompanion(
              name: Value('Conc Product'),
              barcode: Value('B5-CONC'),
              currentStock: Value(100),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      final serviceA = PosSaleService(dbA);
      final serviceB = PosSaleService(dbB);
      final key = b5IdempotencyKey();
      const fp = 'b5-concurrent-fingerprint';

      Future<ProcessSaleResult> attempt(PosSaleService service) async {
        for (var i = 0; i < 20; i++) {
          try {
            return await service.processSale(
              idempotencyKey: key,
              fingerprintHash: fp,
              invoice: SalesInvoicesCompanion(
                subtotal: const Value(10),
                total: const Value(10),
                paymentMethod: const Value('CASH'),
                cashPaid: const Value(10),
              ),
              items: [
                SaleItemsCompanion(
                  productId: Value(pid),
                  quantity: const Value(1),
                  unitPrice: const Value(10),
                  unitCost: const Value(5),
                  total: const Value(10),
                ),
              ],
              debtAmount: 0,
              netSaleTotal: 10,
            );
          } on SqliteException catch (e) {
            if (e.resultCode != 5) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        }
        fail('processSale remained locked');
      }

      final results = await Future.wait([attempt(serviceA), attempt(serviceB)]);
      expect(results.where((r) => r.idempotentReplay).length, 1);
      expect(results.map((r) => r.invoiceId).toSet().length, 1);
      expect(await dbA.select(dbA.salesInvoices).get(), hasLength(1));
      expect(await dbA.select(dbA.posSaleIdempotency).get(), hasLength(1));
    });

    test('4) failed stock transaction leaves no idempotency seal', () async {
      final key = b5IdempotencyKey();
      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(const ProductsCompanion(currentStock: Value(0)));

      await expectLater(
        runCashSale(key: key),
        throwsA(isA<InsufficientStockException>()),
      );
      expect(await idempotencyRowCount(), 0);
      expect(await invoiceCount(), 0);

      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(const ProductsCompanion(currentStock: Value(100)));

      final retry = await runCashSale(key: key);
      expect(retry.idempotentReplay, isFalse);
      expect(await invoiceCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('5) credit-limit failure leaves no seal; retry succeeds if valid',
        () async {
      await db.customerAccountsDao.recordSale(
        customerId: customerId,
        amount: 60,
        invoiceId: 0,
        note: 'seed exposure',
      );

      final key = b5IdempotencyKey();
      final payment = PaymentInfo(
        method: 'DEBT',
        idempotencyKey: key,
        debtAmount: 50,
      );
      final fp = fingerprintFor(payment: payment, cid: customerId, amount: 50);

      await expectLater(
        saleService.processSale(
          idempotencyKey: key,
          fingerprintHash: fp,
          invoice: SalesInvoicesCompanion(
            subtotal: const Value(50),
            total: const Value(50),
            paymentMethod: const Value('DEBT'),
            debtAmount: const Value(50),
            customerId: Value(customerId),
          ),
          items: cashItems(qty: 1, price: 50),
          debtAmount: 50,
          netSaleTotal: 50,
        ),
        throwsA(isA<CreditLimitExceededException>()),
      );
      expect(await idempotencyRowCount(), 0);
      expect(await invoiceCount(), 0);

      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 20,
        note: 'reduce exposure',
      );

      final retry = await saleService.processSale(
        idempotencyKey: key,
        fingerprintHash: fp,
        invoice: SalesInvoicesCompanion(
          subtotal: const Value(50),
          total: const Value(50),
          paymentMethod: const Value('DEBT'),
          debtAmount: const Value(50),
          customerId: Value(customerId),
        ),
        items: cashItems(qty: 1, price: 50),
        debtAmount: 50,
        netSaleTotal: 50,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await invoiceCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('6) same key + different fingerprint conflicts', () async {
      final key = b5IdempotencyKey();
      await runCashSale(key: key, fingerprint: 'fp-a');

      await expectLater(
        runCashSale(key: key, fingerprint: 'fp-b'),
        throwsA(isA<PosSaleIdempotencyConflictException>()),
      );
      expect(await invoiceCount(), 1);
    });

    test('7) two different keys + identical cart create two sales', () async {
      const fp = 'identical-cart-fingerprint';
      await runCashSale(key: b5IdempotencyKey(), fingerprint: fp);
      await runCashSale(key: b5IdempotencyKey(), fingerprint: fp);
      expect(await invoiceCount(), 2);
      expect(await idempotencyRowCount(), 2);
    });

    test('8) duplicate side-effect verification on replay', () async {
      final key = b5IdempotencyKey();
      final payment = PaymentInfo(
        method: 'DEBT',
        idempotencyKey: key,
        debtAmount: 40,
      );
      final fp = fingerprintFor(payment: payment, cid: customerId, amount: 40);

      await saleService.processSale(
        idempotencyKey: key,
        fingerprintHash: fp,
        invoice: SalesInvoicesCompanion(
          subtotal: const Value(40),
          total: const Value(40),
          paymentMethod: const Value('DEBT'),
          debtAmount: const Value(40),
          customerId: Value(customerId),
        ),
        items: cashItems(qty: 1, price: 40),
        debtAmount: 40,
        netSaleTotal: 40,
      );
      final pointsAfterFirst = await loyaltyPoints();

      await saleService.processSale(
        idempotencyKey: key,
        fingerprintHash: fp,
        invoice: SalesInvoicesCompanion(
          subtotal: const Value(40),
          total: const Value(40),
          paymentMethod: const Value('DEBT'),
          debtAmount: const Value(40),
          customerId: Value(customerId),
        ),
        items: cashItems(qty: 1, price: 40),
        debtAmount: 40,
        netSaleTotal: 40,
      );

      expect(await invoiceCount(), 1);
      expect(await saleItemCount(), 1);
      expect(await productStock(), 99);
      expect(await saleTxnCount(), 1);
      expect(await loyaltyPoints(), pointsAfterFirst);
    });

    test('9) migration v36 to v37 creates idempotency table', () async {
      final fixture = await openSimulatedV36RawDatabase();
      addTearDown(() => File(fixture.path).deleteSync());

      final migrated = AppDatabase.test(NativeDatabase.opened(fixture.rawDb));
      addTearDown(() async => migrated.close());

      final tableRows = await migrated.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'pos_sale_idempotency'",
      ).get();
      expect(tableRows, isNotEmpty);

      final indexRows = await migrated.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'psi_sales_invoice_idx'",
      ).get();
      expect(indexRows, isNotEmpty);
      expect(migrated.schemaVersion, 38);
    });

    test('10) fresh install includes pos_sale_idempotency at v38', () async {
      final fresh = AppDatabase.test();
      addTearDown(() async => fresh.close());
      expect(fresh.schemaVersion, 38);
      final rows = await fresh.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'pos_sale_idempotency'",
      ).get();
      expect(rows, isNotEmpty);
    });

    test('11) fingerprint is deterministic and payment key is stable', () {
      final payment = PaymentInfo(method: 'CASH', idempotencyKey: 'fixed-key');
      final product = ProductModel(
        id: 1,
        name: 'P',
        barcode: 'B',
        costPrice: 1,
        sellPrice: 2,
      );
      final item = CartItem(product: product, quantity: 2, unitPrice: 2);
      final a = PosSaleFingerprint.compute(
        sessionId: 5,
        cartSlotId: 2,
        items: [item],
        invoiceDiscount: 1,
        loyaltyPointsUsed: 0,
        loyaltyDiscount: 0,
        customerId: 3,
        payment: payment,
      );
      final b = PosSaleFingerprint.compute(
        sessionId: 5,
        cartSlotId: 2,
        items: [item],
        invoiceDiscount: 1,
        loyaltyPointsUsed: 0,
        loyaltyDiscount: 0,
        customerId: 3,
        payment: payment,
      );
      expect(a, b);
      expect(payment.idempotencyKey, 'fixed-key');
    });
  });
}
