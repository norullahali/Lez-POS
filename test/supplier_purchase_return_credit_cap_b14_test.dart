import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/supplier_account_service.dart';
import 'package:lez_pos/core/services/supplier_payment_exceeds_payable_exception.dart';
import 'package:lez_pos/core/services/supplier_refund_settlement_service.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/supplier_payment_test_keys.dart';
import 'support/supplier_refund_test_keys.dart';

void main() {
  late AppDatabase db;
  late SupplierReturnService returnService;
  late SupplierAccountService paymentService;
  late SupplierRefundSettlementService settlementService;
  late int supplierId;
  late int productId;
  late int purchaseItemId;
  late int invoiceId;

  const unitCost = 5.0;

  Future<void> seedPurchase({
    required AppDatabase target,
    double purchaseQty = 20,
    double initialStock = 0,
    double debtAmount = 100,
  }) async {
    supplierId = await target.into(target.suppliers).insert(
          const SuppliersCompanion(name: Value('B14 Supplier')),
        );
    productId = await target.into(target.products).insert(
          ProductsCompanion(
            name: const Value('B14 Part'),
            currentStock: Value(initialStock),
          ),
        );
    invoiceId = await target.purchasesDao.savePurchaseInvoice(
      header: PurchaseInvoicesCompanion(
        supplierId: Value(supplierId),
        purchaseDate: Value(DateTime(2026, 3, 1)),
        total: Value(debtAmount),
        paidAmount: const Value(0),
        debtAmount: Value(debtAmount),
      ),
      items: [
        {'productId': productId, 'qty': purchaseQty, 'cost': unitCost},
      ],
    );
    final items = await target.purchasesDao.getItemsForInvoice(invoiceId);
    purchaseItemId = items.single.id;
  }

  SupplierReturnPostingInput postingInput({required double quantity}) {
    return SupplierReturnPostingInput(
      supplierId: supplierId,
      purchaseInvoiceId: invoiceId,
      lines: [
        SupplierReturnPostingLine(
          purchaseItemId: purchaseItemId,
          quantity: quantity,
        ),
      ],
    );
  }

  Future<double> creditReversalTotal([AppDatabase? target]) async {
    final database = target ?? db;
    return database.supplierAccountsDao.getCreditReversalTotalForPurchaseInvoice(
      supplierId: supplierId,
      purchaseInvoiceId: invoiceId,
    );
  }

  Future<double> invoiceDebtAmount([AppDatabase? target]) async {
    final database = target ?? db;
    final row = await (database.select(database.purchaseInvoices)
          ..where((p) => p.id.equals(invoiceId)))
        .getSingle();
    return row.debtAmount;
  }

  Future<double> supplierBalance([AppDatabase? target]) async {
    final database = target ?? db;
    return database.supplierAccountsDao.getBalance(supplierId);
  }

  Future<int> returnHeaderCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await database.select(database.supplierReturns).get()).length;
  }

  Future<int> returnTxnCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await (database.select(database.supplierTransactions)
          ..where((t) => t.type.equals('RETURN')))
        .get())
        .length;
  }

  Future<double> returnTxnAbsTotal([AppDatabase? target]) async {
    final database = target ?? db;
    final rows = await (database.select(database.supplierTransactions)
          ..where((t) => t.type.equals('RETURN')))
        .get();
    return rows.fold<double>(0, (sum, row) => sum + row.amount.abs());
  }

  Future<double> returnedQuantity([AppDatabase? target]) async {
    final database = target ?? db;
    final row = await database.customSelect(
      '''
      SELECT COALESCE(SUM(quantity), 0) AS total
      FROM supplier_return_items
      WHERE purchase_item_id = ?
      ''',
      variables: [Variable.withInt(purchaseItemId)],
      readsFrom: {database.supplierReturnItems},
    ).getSingle();
    return (row.data['total'] as num).toDouble();
  }

  Future<Object?> runConcurrentReturn(
    SupplierReturnService targetService,
    SupplierReturnPostingInput input,
  ) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await targetService.postPurchaseLinkedReturn(input);
      } on SupplierReturnPostingException catch (e) {
        return e.code;
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
    throw StateError('concurrent return exhausted busy retries');
  }

  setUp(() async {
    db = AppDatabase.test();
    returnService = SupplierReturnService(db);
    paymentService = SupplierAccountService(db);
    settlementService = SupplierRefundSettlementService(db);
    await seedPurchase(target: db, purchaseQty: 30, initialStock: 0);
  });

  tearDown(() async {
    await db.close();
  });

  group('B14 supplier purchase-linked return invoice credit cap', () {
    test('1) single return within cap posts full RETURN amount', () async {
      await returnService.postPurchaseLinkedReturn(postingInput(quantity: 6));

      expect(await creditReversalTotal(), closeTo(30, 0.0001));
      expect(await returnTxnCount(), 1);
      expect(await supplierBalance(), closeTo(70, 0.0001));
    });

    test('2) proposed return exceeding remaining cap is clipped', () async {
      await returnService.postPurchaseLinkedReturn(postingInput(quantity: 16));
      expect(await creditReversalTotal(), closeTo(80, 0.0001));

      await returnService.postPurchaseLinkedReturn(postingInput(quantity: 8));

      expect(await creditReversalTotal(), closeTo(100, 0.0001));
      expect(await returnTxnCount(), 2);
      final lastReturn = (await (db.select(db.supplierTransactions)
            ..where((t) => t.type.equals('RETURN'))
            ..orderBy([(t) => OrderingTerm.desc(t.id)]))
          .get())
          .first;
      expect(lastReturn.amount.abs(), closeTo(20, 0.0001));
    });

    test('3) sequential 40 + 60 totals 100 credit reversal', () async {
      await returnService.postPurchaseLinkedReturn(postingInput(quantity: 8));
      await returnService.postPurchaseLinkedReturn(postingInput(quantity: 12));

      expect(await creditReversalTotal(), closeTo(100, 0.0001));
      expect(await returnTxnAbsTotal(), closeTo(100, 0.0001));
    });

    test('4) sequential 70 + 40 totals 100 credit reversal', () async {
      await returnService.postPurchaseLinkedReturn(postingInput(quantity: 14));
      await returnService.postPurchaseLinkedReturn(postingInput(quantity: 8));

      expect(await creditReversalTotal(), closeTo(100, 0.0001));
      expect(await returnTxnAbsTotal(), closeTo(100, 0.0001));
    });

    test('5) exhausted cap succeeds without RETURN row', () async {
      await returnService.postPurchaseLinkedReturn(postingInput(quantity: 20));
      expect(await creditReversalTotal(), closeTo(100, 0.0001));

      final returnId = await returnService.postPurchaseLinkedReturn(
        postingInput(quantity: 4),
      );

      expect(returnId, greaterThan(0));
      expect(await returnHeaderCount(), 2);
      expect(await returnTxnCount(), 1);
      expect(await creditReversalTotal(), closeTo(100, 0.0001));
      expect(await returnedQuantity(), 24);
    });

    test('6) dual connection 60 + 60 keeps total RETURN <= 100', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b14cc_${DateTime.now().microsecondsSinceEpoch}.db';
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
      await seedPurchase(target: dbA, purchaseQty: 24, initialStock: 0);
      await dbA.customStatement('PRAGMA busy_timeout = 5000');

      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      await dbB.customStatement('PRAGMA busy_timeout = 5000');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final serviceA = SupplierReturnService(dbA);
      final serviceB = SupplierReturnService(dbB);
      final input = SupplierReturnPostingInput(
        supplierId: supplierId,
        purchaseInvoiceId: invoiceId,
        lines: [
          SupplierReturnPostingLine(
            purchaseItemId: purchaseItemId,
            quantity: 12,
          ),
        ],
      );

      final outcomes = await Future.wait<Object?>([
        runConcurrentReturn(serviceA, input),
        runConcurrentReturn(serviceB, input),
      ]);

      expect(outcomes.whereType<int>().length, 2);
      final totalCredit = await creditReversalTotal(dbA);
      expect(totalCredit, lessThanOrEqualTo(100.0001));
      expect(totalCredit, greaterThan(0));
    });

    test('7) return + payment concurrency keeps credit cap intact', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b14pay_${DateTime.now().microsecondsSinceEpoch}.db';
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
      await seedPurchase(target: dbA, purchaseQty: 24, initialStock: 0);
      await dbA.customStatement('PRAGMA busy_timeout = 5000');

      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      await dbB.customStatement('PRAGMA busy_timeout = 5000');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final returnSvc = SupplierReturnService(dbA);
      final paySvc = SupplierAccountService(dbB);

      await Future.wait<Object?>([
        runConcurrentReturn(
          returnSvc,
          SupplierReturnPostingInput(
            supplierId: supplierId,
            purchaseInvoiceId: invoiceId,
            lines: [
              SupplierReturnPostingLine(
                purchaseItemId: purchaseItemId,
                quantity: 8,
              ),
            ],
          ),
        ),
        () async {
          for (var attempt = 0; attempt < 8; attempt++) {
            try {
              await paySvc.processPayment(
                idempotencyKey: b8SupplierPaymentIdempotencyKey(),
                supplierId: supplierId,
                amount: 40,
              );
              return true;
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
          throw StateError('payment exhausted busy retries');
        }(),
      ]);

      final totalCredit = await creditReversalTotal(dbA);
      final debt = await invoiceDebtAmount(dbA);
      expect(totalCredit, lessThanOrEqualTo(debt + 0.0001));
    });

    test('8) fully-paid return preserves supplier credit semantics', () async {
      await paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
        amount: 100,
      );
      expect(await supplierBalance(), closeTo(0, 0.0001));

      await returnService.postPurchaseLinkedReturn(postingInput(quantity: 4));

      expect(await creditReversalTotal(), closeTo(20, 0.0001));
      expect(await supplierBalance(), closeTo(-20, 0.0001));
    });

    test('9) accounting failure rolls back entire return transaction', () async {
      final failingService = SupplierReturnService.withAccountingPoster(
        db,
        accountingPoster: ({
          required int supplierId,
          required double amount,
          required int returnId,
          String note = '',
        }) async {
          throw Exception('forced accounting failure');
        },
      );

      await expectLater(
        failingService.postPurchaseLinkedReturn(postingInput(quantity: 2)),
        throwsA(
          isA<SupplierReturnPostingException>().having(
            (e) => e.code,
            'code',
            SupplierReturnPostingFailure.supplierAccountingFailure,
          ),
        ),
      );

      expect(await returnHeaderCount(), 0);
      expect(await returnTxnCount(), 0);
      expect(await creditReversalTotal(), 0);
      expect(await supplierBalance(), closeTo(100, 0.0001));
    });

    test('10) SR 2.3 quantity-cap regression still rejects over-return',
        () async {
      await returnService.postPurchaseLinkedReturn(postingInput(quantity: 30));

      await expectLater(
        returnService.postPurchaseLinkedReturn(postingInput(quantity: 1)),
        throwsA(
          isA<SupplierReturnPostingException>().having(
            (e) => e.code,
            'code',
            SupplierReturnPostingFailure.quantityExceedsReturnable,
          ),
        ),
      );

      expect(await returnedQuantity(), 30);
    });

    test('11) B3 supplier payment overpay guard still rejects', () async {
      await expectLater(
        paymentService.processPayment(
          idempotencyKey: b8SupplierPaymentIdempotencyKey(),
          supplierId: supplierId,
          amount: 150,
        ),
        throwsA(isA<SupplierPaymentExceedsPayableException>()),
      );
      expect(await supplierBalance(), closeTo(100, 0.0001));
    });

    test('12) B8 supplier payment idempotency still replays safely', () async {
      const key = 'b14-b8-idempotency-key';
      final first = await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 25,
      );
      final second = await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 25,
      );

      expect(first.supplierTransactionId, second.supplierTransactionId);
      expect(await supplierBalance(), closeTo(75, 0.0001));
    });

    test('13) supplier refund settlement regression still works', () async {
      await paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
        amount: 100,
      );
      await returnService.postPurchaseLinkedReturn(postingInput(quantity: 4));
      expect(await supplierBalance(), closeTo(-20, 0.0001));

      final result = await settlementService.settleCredit(
        idempotencyKey: supplierRefundTestIdempotencyKey(),
        supplierId: supplierId,
        amount: 20,
      );
      expect(result.supplierTransactionId, greaterThan(0));
      expect(await supplierBalance(), closeTo(0, 0.0001));
    });

    test('14) invariant credit reversal total <= invoice debt_amount', () async {
      await returnService.postPurchaseLinkedReturn(postingInput(quantity: 14));
      await returnService.postPurchaseLinkedReturn(postingInput(quantity: 8));

      final totalCredit = await creditReversalTotal();
      final debt = await invoiceDebtAmount();
      expect(totalCredit, lessThanOrEqualTo(debt + 0.0001));
    });
  });
}
