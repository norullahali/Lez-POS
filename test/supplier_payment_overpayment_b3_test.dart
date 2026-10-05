import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/supplier_account_service.dart';
import 'package:lez_pos/core/services/supplier_payment_exceeds_payable_exception.dart';
import 'package:lez_pos/core/services/supplier_refund_settlement_service.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/supplier_payment_test_keys.dart';
import 'support/supplier_refund_test_keys.dart';
import 'support/supplier_return_posting_helpers.dart';

void main() {
  late AppDatabase db;
  late SupplierAccountService paymentService;
  late SupplierReturnService returnService;
  late SupplierRefundSettlementService settlementService;
  late FinancialLedgerRepository ledger;
  late int supplierId;
  late int productId;
  late int purchaseItemId;
  late int invoiceId;

  const ledgerFilter = CashLedgerFilter(
    page: 0,
    pageSize: 1000,
    dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
  );

  setUp(() async {
    db = AppDatabase.test();
    paymentService = SupplierAccountService(db);
    returnService = SupplierReturnService(db);
    settlementService = SupplierRefundSettlementService(db);
    ledger = FinancialLedgerRepository(db);

    supplierId = await db.into(db.suppliers).insert(
          const SuppliersCompanion(name: Value('B3 Payment Supplier')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(name: Value('B3 Part')),
        );

    invoiceId = await db.purchasesDao.savePurchaseInvoice(
      header: PurchaseInvoicesCompanion(
        supplierId: Value(supplierId),
        purchaseDate: Value(DateTime(2026, 3, 1)),
        total: const Value(100),
        paidAmount: const Value(0),
        debtAmount: const Value(100),
      ),
      items: [
        {'productId': productId, 'qty': 20.0, 'cost': 5.0},
      ],
    );

    final items = await db.purchasesDao.getItemsForInvoice(invoiceId);
    purchaseItemId = items.single.id;
  });

  tearDown(() async {
    await db.close();
  });

  Future<double> balance() =>
      db.supplierAccountsDao.calculateBalanceFromTransactions(supplierId);

  Future<int> paymentTxnCount() async =>
      (await (db.select(db.supplierTransactions)
                ..where((t) =>
                    t.supplierId.equals(supplierId) & t.type.equals('PAYMENT')))
              .get())
          .length;

  Future<double> paymentTotalAbs() async {
    final rows = await (db.select(db.supplierTransactions)
          ..where((t) =>
              t.supplierId.equals(supplierId) & t.type.equals('PAYMENT')))
        .get();
    return rows.fold<double>(0, (sum, row) => sum + row.amount.abs());
  }

  Future<int> logCount() async => (await db.select(db.logsTable).get()).length;

  Future<List<dynamic>> supplierPaymentLedgerEvents() async {
    final page = await ledger.getEntries(ledgerFilter);
    return page.entries
        .where((e) => e.eventType == CashLedgerEventType.supplierPayment)
        .toList();
  }

  Future<void> seedCredit20() async {
    await paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
      amount: 100,
    );
    await postSupplierReturnId(returnService, 
      SupplierReturnPostingInput(
        supplierId: supplierId,
        purchaseInvoiceId: invoiceId,
        lines: [
          SupplierReturnPostingLine(
            purchaseItemId: purchaseItemId,
            quantity: 4,
          ),
        ],
      ),
    );
    expect(await balance(), closeTo(-20, 0.001));
  }

  group('B3 supplier payment atomic overpayment guard', () {
    test('1) valid partial payment succeeds', () async {
      expect(await balance(), closeTo(100, 0.001));

      await paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
        amount: 30,
      );

      expect(await balance(), closeTo(70, 0.001));
      expect(await paymentTxnCount(), 1);
    });

    test('2) valid full payment succeeds', () async {
      await paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
        amount: 100,
      );

      expect(await balance(), closeTo(0, 0.001));
      expect(await paymentTxnCount(), 1);
    });

    test('3) exact outstanding balance payment succeeds', () async {
      await paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
        amount: 40,
      );
      expect(await balance(), closeTo(60, 0.001));

      await paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
        amount: 60,
      );

      expect(await balance(), closeTo(0, 0.001));
      expect(await paymentTxnCount(), 2);
    });

    test('4) overpayment is rejected', () async {
      expect(await balance(), closeTo(100, 0.001));

      await expectLater(
        paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
          amount: 110,
        ),
        throwsA(isA<SupplierPaymentExceedsPayableException>()),
      );

      expect(await balance(), closeTo(100, 0.001));
      expect(await paymentTxnCount(), 0);
    });

    test('5) zero payment rejected with ArgumentError', () async {
      await expectLater(
        paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
          amount: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await paymentTxnCount(), 0);
    });

    test('6) negative payment rejected with ArgumentError', () async {
      await expectLater(
        paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
          amount: -5,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await paymentTxnCount(), 0);
    });

    test('7) supplier balance after valid payment is correct', () async {
      await paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
        amount: 25,
      );

      final cached =
          await db.supplierAccountsDao.getBalance(supplierId);
      final authoritative = await balance();
      expect(authoritative, closeTo(75, 0.001));
      expect(cached, closeTo(authoritative, 0.001));
    });

    test('8) negative supplier credit balance rejects further payment',
        () async {
      await seedCredit20();
      expect(await balance(), closeTo(-20, 0.001));

      await expectLater(
        paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
          amount: 10,
        ),
        throwsA(isA<SupplierPaymentExceedsPayableException>()),
      );

      expect(await balance(), closeTo(-20, 0.001));
    });

    test('9) rejected overpayment creates no supplier PAYMENT transaction',
        () async {
      await expectLater(
        paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
          amount: 150,
        ),
        throwsA(isA<SupplierPaymentExceedsPayableException>()),
      );

      expect(await paymentTxnCount(), 0);
      expect(await paymentTotalAbs(), 0);
    });

    test('10) rejected overpayment creates no cash ledger side effect',
        () async {
      final ledgerBefore = await supplierPaymentLedgerEvents();

      await expectLater(
        paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
          amount: 150,
        ),
        throwsA(isA<SupplierPaymentExceedsPayableException>()),
      );

      final ledgerAfter = await supplierPaymentLedgerEvents();
      expect(ledgerAfter.length, ledgerBefore.length);
    });

    test('11) successful payment creates one derived SUPPLIER_PAYMENT entry',
        () async {
      final ledgerBefore = await supplierPaymentLedgerEvents();

      await paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
        amount: 40,
      );

      final ledgerAfter = await supplierPaymentLedgerEvents();
      expect(ledgerAfter.length, ledgerBefore.length + 1);
      expect(await paymentTxnCount(), 1);
    });

    test('12) rejected payment leaves logs unchanged', () async {
      final logsBefore = await logCount();

      await expectLater(
        paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
          amount: 200,
        ),
        throwsA(isA<SupplierPaymentExceedsPayableException>()),
      );

      expect(await logCount(), logsBefore);
    });

    test('13) concurrent payments cannot produce invalid final payable',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b3_${DateTime.now().microsecondsSinceEpoch}.db';
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

      final serviceA = SupplierAccountService(dbA);
      final serviceB = SupplierAccountService(dbB);

      final sid = await dbA.into(dbA.suppliers).insert(
            const SuppliersCompanion(name: Value('Concurrent Supplier')),
          );
      final pid = await dbA.into(dbA.products).insert(
            const ProductsCompanion(name: Value('Concurrent Part')),
          );

      await dbA.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(sid),
          purchaseDate: Value(DateTime(2026, 3, 1)),
          total: const Value(100),
          paidAmount: const Value(0),
          debtAmount: const Value(100),
        ),
        items: [
          {'productId': pid, 'qty': 20.0, 'cost': 5.0},
        ],
      );

      final results = await Future.wait<bool>([
        () async {
          try {
            await serviceA.processPayment(
              idempotencyKey: b8SupplierPaymentIdempotencyKey(),
              supplierId: sid,
              amount: 60,
            );
            return true;
          } catch (_) {
            return false;
          }
        }(),
        () async {
          try {
            await serviceB.processPayment(
              idempotencyKey: b8SupplierPaymentIdempotencyKey(),
              supplierId: sid,
              amount: 60,
            );
            return true;
          } catch (_) {
            return false;
          }
        }(),
      ]);

      final successCount = results.where((ok) => ok).length;
      expect(successCount, lessThanOrEqualTo(1));

      final finalBalance = await dbA.supplierAccountsDao
          .calculateBalanceFromTransactions(sid);
      expect(finalBalance, greaterThanOrEqualTo(0));

      final paymentRows = await (dbA.select(dbA.supplierTransactions)
            ..where((t) =>
                t.supplierId.equals(sid) & t.type.equals('PAYMENT')))
          .get();
      final totalPaid =
          paymentRows.fold<double>(0, (sum, row) => sum + row.amount.abs());
      expect(totalPaid, lessThanOrEqualTo(100));
      expect(finalBalance, closeTo(100 - totalPaid, 0.001));
    });

    test('14) supplier refund settlement remains unaffected after B3 guard',
        () async {
      await seedCredit20();

      final result = await settlementService.settleCredit(
        idempotencyKey: supplierRefundTestIdempotencyKey(),
        supplierId: supplierId,
        amount: 20,
      );

      expect(result.supplierTransactionId, greaterThan(0));
      expect(await balance(), closeTo(0, 0.001));
    });
  });
}
