import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/supplier_account_service.dart';
import 'package:lez_pos/core/services/supplier_refund_settlement_intent_fingerprint.dart';
import 'package:lez_pos/core/services/supplier_refund_settlement_service.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';
import 'package:lez_pos/features/returns/providers/supplier_refund_settlement_provider.dart';
import 'package:lez_pos/features/suppliers/providers/supplier_accounts_provider.dart';
import 'package:lez_pos/features/suppliers/supplier_refund_settlement_idempotency.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/supplier_payment_test_keys.dart';
import 'support/supplier_return_posting_helpers.dart';

void main() {
  group('SupplierRefundSettlementIntentFingerprint (B29)', () {
    test('T1 identical inputs deterministic fingerprint', () {
      final a = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 1,
        amount: 10,
        returnId: null,
        note: null,
      );
      final b = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 1,
        amount: 10,
        returnId: null,
        note: null,
      );
      expect(b, a);
    });

    test('T2 different supplierId different fingerprint', () {
      final a = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 1,
        amount: 10,
        returnId: null,
        note: null,
      );
      final b = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 2,
        amount: 10,
        returnId: null,
        note: null,
      );
      expect(b, isNot(a));
    });

    test('T3 different amount different fingerprint', () {
      final a = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 1,
        amount: 10,
        returnId: null,
        note: null,
      );
      final b = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 1,
        amount: 20,
        returnId: null,
        note: null,
      );
      expect(b, isNot(a));
    });

    test('T4 amount 6dp canonicalization same fingerprint', () {
      final a = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 1,
        amount: 10.123456789,
        returnId: null,
        note: null,
      );
      final b = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 1,
        amount: 10.123457,
        returnId: null,
        note: null,
      );
      expect(b, a);
    });

    test('T5 null returnId vs concrete returnId different fingerprint', () {
      final aggregate = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 1,
        amount: 10,
        returnId: null,
        note: null,
      );
      final linked = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 1,
        amount: 10,
        returnId: 42,
        note: null,
      );
      expect(linked, isNot(aggregate));
    });

    test('T6 note trimming null vs empty same fingerprint', () {
      final a = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 1,
        amount: 10,
        returnId: null,
        note: null,
      );
      final b = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 1,
        amount: 10,
        returnId: null,
        note: '   ',
      );
      expect(b, a);
    });

    test('T6 note material change different fingerprint', () {
      final a = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 1,
        amount: 10,
        returnId: null,
        note: 'alpha',
      );
      final b = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 1,
        amount: 10,
        returnId: null,
        note: 'beta',
      );
      expect(b, isNot(a));
    });
  });

  group('SupplierRefundSettlementIdempotencyState (B29)', () {
    late SupplierRefundSettlementIdempotencyState state;
    var uuidSeq = 0;

    String nextKey() => 'b29-refund-${++uuidSeq}';

    setUp(() {
      state = SupplierRefundSettlementIdempotencyState();
      uuidSeq = 0;
    });

    test('T7 same fingerprint reuses same UUID', () {
      final first = state.prepareSettlementKey(
        fingerprintHash: 'fp-a',
        generateUuid: nextKey,
      );
      final second = state.prepareSettlementKey(
        fingerprintHash: 'fp-a',
        generateUuid: nextKey,
      );
      expect(second, first);
      expect(uuidSeq, 1);
    });

    test('T8 different fingerprints different UUIDs', () {
      final k1 = state.prepareSettlementKey(
        fingerprintHash: 'fp-1',
        generateUuid: nextKey,
      );
      final k2 = state.prepareSettlementKey(
        fingerprintHash: 'fp-2',
        generateUuid: nextKey,
      );
      expect(k2, isNot(k1));
    });

    test('T11 success clears sticky slot', () {
      state.prepareSettlementKey(
        fingerprintHash: 'fp-done',
        generateUuid: nextKey,
      );
      state.clearSettlementKey('fp-done');
      expect(state.keyForFingerprint('fp-done'), isNull);
    });

    test('T12 failure retains sticky slot', () {
      state.prepareSettlementKey(
        fingerprintHash: 'fp-fail',
        generateUuid: nextKey,
      );
      expect(state.keyForFingerprint('fp-fail'), isNotNull);
    });

    test('T13 conflict retains UUID without rotation', () {
      const fp = 'fp-bound';
      final key = state.prepareSettlementKey(
        fingerprintHash: fp,
        generateUuid: nextKey,
      );
      expect(
        state.prepareSettlementKey(
          fingerprintHash: fp,
          generateUuid: nextKey,
        ),
        key,
      );
      expect(uuidSeq, 1);
    });

    test('T15 aggregate vs return-linked isolation', () {
      final fpAgg = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 5,
        amount: 15,
        returnId: null,
        note: null,
      );
      final fpRet = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: 5,
        amount: 15,
        returnId: 99,
        note: null,
      );
      final kAgg = state.prepareSettlementKey(
        fingerprintHash: fpAgg,
        generateUuid: nextKey,
      );
      final kRet = state.prepareSettlementKey(
        fingerprintHash: fpRet,
        generateUuid: nextKey,
      );
      expect(kRet, isNot(kAgg));
      expect(state.keysByFingerprintForTesting.length, 2);
    });
  });

  group('B29 supplier refund UI notifier sticky keys', () {
    late AppDatabase db;
    late int supplierId;
    late int invoiceId;
    late int purchaseItemId;
    late ProviderContainer container;

    Future<void> seedCredit({double credit = 50}) async {
      await SupplierAccountService(db).processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
        amount: 50,
      );
      await postSupplierReturnId(
        SupplierReturnService(db),
        SupplierReturnPostingInput(
          supplierId: supplierId,
          purchaseInvoiceId: invoiceId,
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItemId,
              quantity: credit / 5,
            ),
          ],
        ),
      );
    }

    setUp(() async {
      db = AppDatabase.test();
      supplierId = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('B29 Supplier')),
          );
      final productId = await db.into(db.products).insert(
            const ProductsCompanion(name: Value('Part')),
          );
      invoiceId = await db.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(supplierId),
          purchaseDate: Value(DateTime(2026, 6, 1)),
          total: const Value(50),
          paidAmount: const Value(0),
          debtAmount: const Value(50),
        ),
        items: [
          {'productId': productId, 'qty': 10.0, 'cost': 5.0},
        ],
      );
      purchaseItemId =
          (await db.purchasesDao.getItemsForInvoice(invoiceId)).single.id;
      container = ProviderContainer(
        overrides: [
          supplierRefundSettlementServiceProvider.overrideWithValue(
            SupplierRefundSettlementService(db),
          ),
          supplierAccountsDaoProvider.overrideWithValue(db.supplierAccountsDao),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('T9 reset does not destroy sticky binding', () {
      final notifier = container.read(supplierRefundSettlementProvider.notifier);
      const fp = 'b29-reset-fp';
      final key = notifier.settlementIdempotency.prepareSettlementKey(
        fingerprintHash: fp,
        generateUuid: () => 'b29-sticky-key',
      );
      notifier.reset();
      expect(
        notifier.settlementIdempotency.prepareSettlementKey(
          fingerprintHash: fp,
          generateUuid: () => 'new-mint',
        ),
        key,
      );
    });

    test('T10 same intent after reset reopen reuses key and replays', () async {
      await seedCredit();
      var attempts = 0;
      final failingThenOk = SupplierRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int supplierId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          attempts++;
          if (attempts == 1) {
            throw const SupplierRefundSettlementException(
              SupplierRefundSettlementFailure.amountExceedsCredit,
              'forced failure',
            );
          }
          return db.supplierAccountsDao.recordRefundInTransaction(
            supplierId: supplierId,
            amount: amount,
            returnId: returnId,
            note: note ?? '',
          );
        },
      );
      container.dispose();
      container = ProviderContainer(
        overrides: [
          supplierRefundSettlementServiceProvider.overrideWithValue(
            failingThenOk,
          ),
          supplierAccountsDaoProvider.overrideWithValue(db.supplierAccountsDao),
        ],
      );
      final notifier = container.read(supplierRefundSettlementProvider.notifier);
      notifier.init(
        supplierId: supplierId,
        supplierName: 'B29 Supplier',
        availableCredit: 50,
      );
      notifier.setAmountText('15');
      expect(await notifier.submit(), isFalse);
      final fp = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: supplierId,
        amount: 15,
        returnId: null,
        note: null,
      );
      final boundKey =
          notifier.settlementIdempotency.keyForFingerprint(fp);
      expect(boundKey, isNotNull);
      notifier.reset();
      notifier.init(
        supplierId: supplierId,
        supplierName: 'B29 Supplier',
        availableCredit: 50,
      );
      notifier.setAmountText('15');
      expect(
        notifier.settlementIdempotency.prepareSettlementKey(
          fingerprintHash: fp,
          generateUuid: () => 'unused',
        ),
        boundKey,
      );
      expect(await notifier.submit(), isTrue);
      expect(await _refundCount(db, supplierId), 1);
    });

    test('T16 double submit one service call', () async {
      await seedCredit();
      final gate = Completer<void>();
      final entered = Completer<void>();
      var callCount = 0;
      final service = SupplierRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int supplierId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          callCount++;
          if (!entered.isCompleted) entered.complete();
          await gate.future;
          return db.supplierAccountsDao.recordRefundInTransaction(
            supplierId: supplierId,
            amount: amount,
            returnId: returnId,
            note: note ?? '',
          );
        },
      );
      container.dispose();
      container = ProviderContainer(
        overrides: [
          supplierRefundSettlementServiceProvider.overrideWithValue(service),
          supplierAccountsDaoProvider.overrideWithValue(db.supplierAccountsDao),
        ],
      );
      final notifier = container.read(supplierRefundSettlementProvider.notifier);
      notifier.init(
        supplierId: supplierId,
        supplierName: 'B29 Supplier',
        availableCredit: 50,
      );
      notifier.setAmountText('10');
      final first = notifier.submit();
      await entered.future;
      final second = notifier.submit();
      expect(callCount, 1);
      expect(await second, isFalse);
      gate.complete();
      expect(await first, isTrue);
    });

    test(
        'SF-01/SF-02 post-commit refresh failure retains key reopen replay one REFUND',
        () async {
      await seedCredit();
      var refreshAttempts = 0;
      container.dispose();
      container = ProviderContainer(
        overrides: [
          supplierRefundSettlementServiceProvider.overrideWithValue(
            SupplierRefundSettlementService(db),
          ),
          supplierAccountsDaoProvider.overrideWithValue(db.supplierAccountsDao),
          supplierRefundPostSuccessRefreshProvider.overrideWithValue(
            (ref, supplierId) {
              refreshAttempts++;
              if (refreshAttempts == 1) {
                throw StateError('simulated post-commit refresh failure');
              }
              defaultSupplierRefundPostSuccessRefresh(ref, supplierId);
            },
          ),
        ],
      );
      final notifier = container.read(supplierRefundSettlementProvider.notifier);
      notifier.init(
        supplierId: supplierId,
        supplierName: 'B29 Supplier',
        availableCredit: 50,
      );
      notifier.setAmountText('12.5');
      expect(await notifier.submit(), isFalse);
      expect(await _refundCount(db, supplierId), 1);

      final fp = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: supplierId,
        amount: 12.5,
        returnId: null,
        note: null,
      );
      final boundKey =
          notifier.settlementIdempotency.keyForFingerprint(fp);
      expect(boundKey, isNotNull);

      notifier.reset();
      notifier.init(
        supplierId: supplierId,
        supplierName: 'B29 Supplier',
        availableCredit: 37.5,
      );
      notifier.setAmountText('12.5');
      expect(
        notifier.settlementIdempotency.prepareSettlementKey(
          fingerprintHash: fp,
          generateUuid: () => 'must-not-mint',
        ),
        boundKey,
      );
      expect(await notifier.submit(), isTrue);
      expect(await _refundCount(db, supplierId), 1);
      expect(
        notifier.settlementIdempotency.keyForFingerprint(fp),
        isNull,
      );
    });

    test('SF-04 conflict retains sticky UUID without rotation', () async {
      await seedCredit();
      const conflictKey = 'b29-conflict-key';
      await SupplierRefundSettlementService(db).settleCredit(
        supplierId: supplierId,
        amount: 10,
        idempotencyKey: conflictKey,
      );
      expect(await _refundCount(db, supplierId), 1);

      var uuidMints = 0;
      String mint() => 'b29-conflict-mint-${++uuidMints}';

      container.dispose();
      container = ProviderContainer(
        overrides: [
          supplierRefundSettlementServiceProvider.overrideWithValue(
            SupplierRefundSettlementService(db),
          ),
          supplierAccountsDaoProvider.overrideWithValue(db.supplierAccountsDao),
        ],
      );
      final notifier = container.read(supplierRefundSettlementProvider.notifier);
      notifier.init(
        supplierId: supplierId,
        supplierName: 'B29 Supplier',
        availableCredit: 40,
      );
      notifier.setAmountText('20');
      final fp = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: supplierId,
        amount: 20,
        returnId: null,
        note: null,
      );
      notifier.settlementIdempotency.prepareSettlementKey(
        fingerprintHash: fp,
        generateUuid: () => conflictKey,
      );
      expect(await notifier.submit(), isFalse);
      expect(
        notifier.settlementIdempotency.keyForFingerprint(fp),
        conflictKey,
      );
      expect(
        notifier.settlementIdempotency.prepareSettlementKey(
          fingerprintHash: fp,
          generateUuid: mint,
        ),
        conflictKey,
      );
      expect(uuidMints, 0);
      expect(await _refundCount(db, supplierId), 1);
    });
  });

  group('B29 + SR service replay', () {
    late AppDatabase db;
    late SupplierRefundSettlementService settlementService;
    late SupplierRefundSettlementIdempotencyState stickyKeys;
    late int supplierId;
    late int invoiceId;
    late int purchaseItemId;
    var uuidSeq = 0;
    var paymentKeySeq = 0;

    String nextSettlementKey() => 'b29-svc-${++uuidSeq}';

    String nextPaymentKey() => 'b29-pay-${++paymentKeySeq}';

    Future<void> seedCredit({double credit = 100}) async {
      await SupplierAccountService(db).processPayment(
        idempotencyKey: nextPaymentKey(),
        supplierId: supplierId,
        amount: 50,
      );
      await postSupplierReturnId(
        SupplierReturnService(db),
        SupplierReturnPostingInput(
          supplierId: supplierId,
          purchaseInvoiceId: invoiceId,
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItemId,
              quantity: credit / 5,
            ),
          ],
        ),
      );
    }

    setUp(() async {
      db = AppDatabase.test();
      settlementService = SupplierRefundSettlementService(db);
      stickyKeys = SupplierRefundSettlementIdempotencyState();
      uuidSeq = 0;
      paymentKeySeq = 0;
      supplierId = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('B29 Svc Supplier')),
          );
      final productId = await _insertProduct(db);
      invoiceId = await db.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(supplierId),
          purchaseDate: Value(DateTime(2026, 6, 1)),
          total: const Value(50),
          paidAmount: const Value(0),
          debtAmount: const Value(50),
        ),
        items: [
          {'productId': productId, 'qty': 10.0, 'cost': 5.0},
        ],
      );
      purchaseItemId =
          (await db.purchasesDao.getItemsForInvoice(invoiceId)).single.id;
      await seedCredit(credit: 50);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> runSettlement({
      required double amount,
      int? returnId,
      String? note,
      bool clearAfter = false,
    }) async {
      final fp = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: supplierId,
        amount: amount,
        returnId: returnId,
        note: note,
      );
      final key = stickyKeys.prepareSettlementKey(
        fingerprintHash: fp,
        generateUuid: nextSettlementKey,
      );
      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: amount,
        idempotencyKey: key,
        returnId: returnId,
        note: note,
      );
      if (clearAfter) {
        stickyKeys.clearSettlementKey(fp);
      }
    }

    test('T14 post-commit ambiguity same key one REFUND', () async {
      await runSettlement(amount: 40, note: 'once');
      expect(await _refundCount(db, supplierId), 1);

      final fp = SupplierRefundSettlementIntentFingerprint.compute(
        supplierId: supplierId,
        amount: 40,
        returnId: null,
        note: 'once',
      );
      final retryKey = stickyKeys.prepareSettlementKey(
        fingerprintHash: fp,
        generateUuid: nextSettlementKey,
      );
      expect(retryKey, 'b29-svc-1');

      final replay = await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 40,
        idempotencyKey: retryKey,
        note: 'once',
      );
      expect(replay.idempotentReplay, isTrue);
      expect(await _refundCount(db, supplierId), 1);
    });

    test('T16 concurrent same-key submit one REFUND', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b29_${DateTime.now().microsecondsSinceEpoch}.db';
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

      final sid = await dbA.into(dbA.suppliers).insert(
            const SuppliersCompanion(name: Value('B29 Concurrent')),
          );
      final invoiceId = await dbA.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(sid),
          purchaseDate: Value(DateTime(2026, 6, 1)),
          total: const Value(50),
          paidAmount: const Value(0),
          debtAmount: const Value(50),
        ),
        items: [
          {'productId': await _insertProduct(dbA), 'qty': 10.0, 'cost': 5.0},
        ],
      );
      final purchaseItemId =
          (await dbA.purchasesDao.getItemsForInvoice(invoiceId)).single.id;
      await SupplierAccountService(dbA).processPayment(
        idempotencyKey: 'b29-concurrent-pay',
        supplierId: sid,
        amount: 50,
      );
      await postSupplierReturnId(
        SupplierReturnService(dbA),
        SupplierReturnPostingInput(
          supplierId: sid,
          purchaseInvoiceId: invoiceId,
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItemId,
              quantity: 10,
            ),
          ],
        ),
      );

      final serviceA = SupplierRefundSettlementService(dbA);
      final serviceB = SupplierRefundSettlementService(dbB);
      const sharedKey = 'b29-shared-key';

      final results = await Future.wait([
        serviceA.settleCredit(
          supplierId: sid,
          amount: 30,
          idempotencyKey: sharedKey,
        ),
        serviceB.settleCredit(
          supplierId: sid,
          amount: 30,
          idempotencyKey: sharedKey,
        ),
      ]);

      final refunds = await (dbA.select(dbA.supplierTransactions)
            ..where((t) => t.supplierId.equals(sid) & t.type.equals('REFUND')))
          .get();
      expect(refunds.length, 1);
      expect(results.where((r) => r.idempotentReplay).length, 1);
      expect(results.where((r) => !r.idempotentReplay).length, 1);
    });
  });
}

Future<int> _refundCount(AppDatabase db, int supplierId) async {
  final rows = await (db.select(db.supplierTransactions)
        ..where((t) =>
            t.supplierId.equals(supplierId) & t.type.equals('REFUND')))
      .get();
  return rows.length;
}

Future<int> _insertProduct(AppDatabase db) => db.into(db.products).insert(
      const ProductsCompanion(name: Value('B29 Part')),
    );
