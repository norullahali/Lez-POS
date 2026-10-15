import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_refund_settlement_intent_fingerprint.dart';
import 'package:lez_pos/core/services/customer_refund_settlement_service.dart';
import 'package:lez_pos/features/customers/customer_refund_settlement_idempotency.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  group('CustomerRefundSettlementIntentFingerprint (B28)', () {
    test('T9 note null vs empty string same fingerprint', () {
      final a = CustomerRefundSettlementIntentFingerprint.compute(
        customerId: 1,
        amount: 10,
        returnId: null,
        note: null,
      );
      final b = CustomerRefundSettlementIntentFingerprint.compute(
        customerId: 1,
        amount: 10,
        returnId: null,
        note: '',
      );
      expect(b, a);
    });

    test('T10 note text change after trim new fingerprint', () {
      final a = CustomerRefundSettlementIntentFingerprint.compute(
        customerId: 1,
        amount: 10,
        returnId: null,
        note: 'first',
      );
      final b = CustomerRefundSettlementIntentFingerprint.compute(
        customerId: 1,
        amount: 10,
        returnId: null,
        note: 'second',
      );
      expect(b, isNot(a));
    });

    test('T8 returnId null vs concrete different fingerprint', () {
      final aggregate = CustomerRefundSettlementIntentFingerprint.compute(
        customerId: 1,
        amount: 10,
        returnId: null,
        note: null,
      );
      final linked = CustomerRefundSettlementIntentFingerprint.compute(
        customerId: 1,
        amount: 10,
        returnId: 42,
        note: null,
      );
      expect(linked, isNot(aggregate));
    });
  });

  group('CustomerRefundSettlementIdempotencyState (B28)', () {
    late CustomerRefundSettlementIdempotencyState state;
    var uuidSeq = 0;

    String nextKey() => 'b28-refund-${++uuidSeq}';

    setUp(() {
      state = CustomerRefundSettlementIdempotencyState();
      uuidSeq = 0;
    });

    test('T1 fresh intent mints UUID', () {
      final key = state.prepareSettlementKey(
        fingerprintHash: 'fp-a',
        generateUuid: nextKey,
      );
      expect(key, 'b28-refund-1');
    });

    test('T2 same fingerprint reuses UUID', () {
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

    test('T3 simulated reset/reopen same fingerprint reuses UUID', () {
      state.prepareSettlementKey(
        fingerprintHash: 'fp-reopen',
        generateUuid: nextKey,
      );
      final reopen = state.prepareSettlementKey(
        fingerprintHash: 'fp-reopen',
        generateUuid: nextKey,
      );
      expect(reopen, 'b28-refund-1');
    });

    test('T4 failure path retains key', () {
      state.prepareSettlementKey(
        fingerprintHash: 'fp-fail',
        generateUuid: nextKey,
      );
      expect(state.keyForFingerprint('fp-fail'), isNotNull);
    });

    test('T6 different fingerprint different UUID', () {
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

    test('T7 amount change new fingerprint new UUID', () {
      final fp1 = CustomerRefundSettlementIntentFingerprint.compute(
        customerId: 1,
        amount: 10,
        returnId: null,
        note: null,
      );
      final fp2 = CustomerRefundSettlementIntentFingerprint.compute(
        customerId: 1,
        amount: 20,
        returnId: null,
        note: null,
      );
      final k1 = state.prepareSettlementKey(
        fingerprintHash: fp1,
        generateUuid: nextKey,
      );
      final k2 = state.prepareSettlementKey(
        fingerprintHash: fp2,
        generateUuid: nextKey,
      );
      expect(k2, isNot(k1));
    });

    test('T11 conflict retains key', () {
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
    });

    test('T12 success clears key', () {
      state.prepareSettlementKey(
        fingerprintHash: 'fp-done',
        generateUuid: nextKey,
      );
      state.clearSettlementKey('fp-done');
      expect(state.keyForFingerprint('fp-done'), isNull);
    });

    test('T15 aggregate vs return-linked isolation', () {
      final fpAgg = CustomerRefundSettlementIntentFingerprint.compute(
        customerId: 5,
        amount: 15,
        returnId: null,
        note: null,
      );
      final fpRet = CustomerRefundSettlementIntentFingerprint.compute(
        customerId: 5,
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

  group('B28 + Phase C service replay', () {
    late AppDatabase db;
    late CustomerRefundSettlementService settlementService;
    late CustomerRefundSettlementIdempotencyState stickyKeys;
    late int customerId;
    var uuidSeq = 0;

    String nextSettlementKey() => 'b28-svc-${++uuidSeq}';

    setUp(() async {
      db = AppDatabase.test();
      settlementService = CustomerRefundSettlementService(db);
      stickyKeys = CustomerRefundSettlementIdempotencyState();
      uuidSeq = 0;
      customerId = await db.into(db.customers).insert(
            const CustomersCompanion(name: Value('B28 Customer')),
          );
      await db.customerAccountsDao.recordReturnInTransaction(
        customerId: customerId,
        amount: 100,
        returnId: 1001,
        note: 'credit seed',
      );
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> refundCount() async {
      final rows = await (db.select(db.customerTransactions)
            ..where((t) =>
                t.customerId.equals(customerId) & t.type.equals('REFUND')))
          .get();
      return rows.length;
    }

    Future<void> runSettlement({
      required double amount,
      int? returnId,
      String? note,
    }) async {
      final fp = CustomerRefundSettlementIntentFingerprint.compute(
        customerId: customerId,
        amount: amount,
        returnId: returnId,
        note: note,
      );
      final key = stickyKeys.prepareSettlementKey(
        fingerprintHash: fp,
        generateUuid: nextSettlementKey,
      );
      await settlementService.settleCredit(
        customerId: customerId,
        amount: amount,
        idempotencyKey: key,
        returnId: returnId,
        note: note,
      );
    }

    test('T5 post-commit replay with same key one REFUND', () async {
      await runSettlement(amount: 40, note: 'once');
      expect(await refundCount(), 1);

      final fp = CustomerRefundSettlementIntentFingerprint.compute(
        customerId: customerId,
        amount: 40,
        returnId: null,
        note: 'once',
      );
      final retryKey = stickyKeys.prepareSettlementKey(
        fingerprintHash: fp,
        generateUuid: nextSettlementKey,
      );
      expect(retryKey, 'b28-svc-1');

      final replay = await settlementService.settleCredit(
        customerId: customerId,
        amount: 40,
        idempotencyKey: retryKey,
        note: 'once',
      );
      expect(replay.idempotentReplay, isTrue);
      expect(await refundCount(), 1);
    });

    test('T13 replay success key cleared by caller', () async {
      final fp = CustomerRefundSettlementIntentFingerprint.compute(
        customerId: customerId,
        amount: 25,
        returnId: null,
        note: null,
      );
      final key = stickyKeys.prepareSettlementKey(
        fingerprintHash: fp,
        generateUuid: nextSettlementKey,
      );
      await settlementService.settleCredit(
        customerId: customerId,
        amount: 25,
        idempotencyKey: key,
      );
      await settlementService.settleCredit(
        customerId: customerId,
        amount: 25,
        idempotencyKey: key,
      );
      stickyKeys.clearSettlementKey(fp);
      expect(stickyKeys.keyForFingerprint(fp), isNull);
    });

    test('T16 concurrent same-key submit one REFUND', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b28_${DateTime.now().microsecondsSinceEpoch}.db';
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

      final cid = await dbA.into(dbA.customers).insert(
            const CustomersCompanion(name: Value('B28 Concurrent')),
          );
      await dbA.customerAccountsDao.recordReturnInTransaction(
        customerId: cid,
        amount: 80,
        returnId: 2002,
        note: 'seed',
      );

      final serviceA = CustomerRefundSettlementService(dbA);
      final serviceB = CustomerRefundSettlementService(dbB);
      const sharedKey = 'b28-shared-key';

      final results = await Future.wait([
        serviceA.settleCredit(
          customerId: cid,
          amount: 30,
          idempotencyKey: sharedKey,
        ),
        serviceB.settleCredit(
          customerId: cid,
          amount: 30,
          idempotencyKey: sharedKey,
        ),
      ]);

      final refunds = await (dbA.select(dbA.customerTransactions)
            ..where((t) => t.customerId.equals(cid) & t.type.equals('REFUND')))
          .get();
      expect(refunds.length, 1);
      expect(results.where((r) => r.idempotentReplay).length, 1);
      expect(results.where((r) => !r.idempotentReplay).length, 1);
    });
  });
}
