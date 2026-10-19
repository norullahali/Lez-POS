import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/pos_sale_service.dart';
import 'package:lez_pos/core/services/quick_return_idempotency_conflict_exception.dart';
import 'package:lez_pos/features/returns/customer_quick_return_idempotency.dart';

import 'support/customer_quick_return_test_keys.dart';

QuickReturnSubmitIntent defaultIntent({
  required int productId,
  int? userId,
  double quantity = 1,
  double? refundAmount,
  String reason = 'بدون فاتورة',
  int? approvedByUserId,
}) {
  final qty = quantity;
  return QuickReturnSubmitIntent(
    productId: productId,
    quantity: qty,
    refundAmount: refundAmount ?? 10.0 * qty,
    reason: reason,
    userId: userId ?? 1,
    approvedByUserId: approvedByUserId,
  );
}

Future<void> invokeQuickReturn(
  PosSaleService service,
  QuickReturnSubmitIntent intent,
  String key,
) async {
  await service.processQuickReturn(
    idempotencyKey: key,
    productId: intent.productId,
    quantity: intent.quantity,
    refundAmount: intent.refundAmount,
    userId: intent.userId,
    reason: intent.reason,
    approvedByUserId: intent.approvedByUserId,
  );
}

void main() {
  const initialStock = 100.0;
  const userId = 1;
  const sellPrice = 10.0;

  group('QuickReturnIntentFingerprint (B31 T1-T3, T14)', () {
    test('T1 deterministic fingerprint', () {
      final a = computeQuickReturnIntentFingerprint(
        productId: 5,
        quantity: 1,
        refundAmount: 10,
        reason: 'test',
        userId: 1,
      );
      final b = computeQuickReturnIntentFingerprint(
        productId: 5,
        quantity: 1,
        refundAmount: 10,
        reason: 'test',
        userId: 1,
      );
      expect(b, a);
    });

    test('T2 material payload change different fingerprint', () {
      final base = computeQuickReturnIntentFingerprint(
        productId: 5,
        quantity: 1,
        refundAmount: 10,
        reason: 'test',
        userId: 1,
      );
      final changedQty = computeQuickReturnIntentFingerprint(
        productId: 5,
        quantity: 2,
        refundAmount: 20,
        reason: 'test',
        userId: 1,
      );
      expect(changedQty, isNot(base));
    });

    test('T3 equivalent normalized payload same fingerprint', () {
      final a = computeQuickReturnIntentFingerprint(
        productId: 5,
        quantity: 1.0000004,
        refundAmount: 10.0000004,
        reason: '  trimmed  ',
        userId: 1,
      );
      final b = computeQuickReturnIntentFingerprint(
        productId: 5,
        quantity: 1.000000,
        refundAmount: 10.000000,
        reason: 'trimmed',
        userId: 1,
      );
      expect(b, a);
    });

    test('T14 approvedByUserId changes fingerprint', () {
      final without = computeQuickReturnIntentFingerprint(
        productId: 5,
        quantity: 1,
        refundAmount: 10,
        reason: 'test',
        userId: 1,
        approvedByUserId: null,
      );
      final withApproval = computeQuickReturnIntentFingerprint(
        productId: 5,
        quantity: 1,
        refundAmount: 10,
        reason: 'test',
        userId: 1,
        approvedByUserId: 99,
      );
      expect(withApproval, isNot(without));
    });
  });

  group('CustomerQuickReturnIdempotencyState (B31)', () {
    late CustomerQuickReturnIdempotencyState state;
    var seq = 0;

    String nextKey() => 'b31-key-${++seq}';

    setUp(() {
      state = CustomerQuickReturnIdempotencyState();
      seq = 0;
    });

    test('T12 independent intents independent keys', () {
      final k1 = state.prepareReturnKey(
        fingerprintHash: 'fp-a',
        generateUuid: nextKey,
      );
      final k2 = state.prepareReturnKey(
        fingerprintHash: 'fp-b',
        generateUuid: nextKey,
      );
      expect(k2, isNot(k1));
      expect(state.keysByFingerprintForTesting.length, 2);
    });

    test('T8s conflict retains key without rotation (state)', () {
      const fp = 'fp-conflict';
      final key = state.prepareReturnKey(
        fingerprintHash: fp,
        generateUuid: nextKey,
      );
      expect(
        state.prepareReturnKey(
          fingerprintHash: fp,
          generateUuid: nextKey,
        ),
        key,
      );
      expect(seq, 1);
    });
  });

  group('CustomerQuickReturnSubmitRunner integration (B31)', () {
    late AppDatabase db;
    late PosSaleService service;
    late int productId;

    Future<int> returnCount() async =>
        (await db.select(db.customerReturns).get()).length;

    Future<double> stockLevel() async => db.stockDao.getStock(productId);

    setUp(() async {
      db = AppDatabase.test();
      service = PosSaleService(db);
      productId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('B31 Quick Return Product'),
              barcode: Value('B31-QR-1'),
              currentStock: Value(initialStock),
              costPrice: Value(5),
              sellPrice: Value(sellPrice),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test('T10 success clears only completed fingerprint slot (runner)', () async {
      final runner = CustomerQuickReturnSubmitRunner();
      final intentComplete = defaultIntent(productId: productId, quantity: 1);
      final intentPending = defaultIntent(productId: productId, quantity: 2);

      var mintSeq = 0;
      String mint() => 'b31-t10-${++mintSeq}';

      final pendingKey = runner.idempotency.prepareReturnKey(
        fingerprintHash: intentPending.fingerprintHash,
        generateUuid: mint,
      );
      expect(mintSeq, 1);

      final outcome = await runner.submit(
        intent: intentComplete,
        generateUuid: mint,
        invokeService: (key) =>
            invokeQuickReturn(service, intentComplete, key),
        postSuccessRefresh: () async {},
      );
      expect(outcome, QuickReturnSubmitOutcome.success);
      expect(await returnCount(), 1);

      expect(
        runner.idempotency.keyForFingerprint(intentComplete.fingerprintHash),
        isNull,
      );
      expect(
        runner.idempotency.keyForFingerprint(intentPending.fingerprintHash),
        pendingKey,
      );
      expect(runner.idempotency.keysByFingerprintForTesting.length, 1);
      expect(mintSeq, 2);
    });

    test('T5 pre-commit failure retains key', () async {
      final runner = CustomerQuickReturnSubmitRunner();
      final intent = defaultIntent(productId: productId);
      var calls = 0;
      String? capturedKey;

      final first = await runner.submit(
        intent: intent,
        generateUuid: () {
          capturedKey ??= b9QuickReturnIdempotencyKey();
          return capturedKey!;
        },
        invokeService: (_) async {
          calls++;
          throw StateError('pre-commit');
        },
        postSuccessRefresh: () async {},
      );
      expect(first, QuickReturnSubmitOutcome.serviceFailure);
      expect(calls, 1);

      final bound = runner.idempotency.keyForFingerprint(intent.fingerprintHash);
      expect(bound, isNotNull);
      expect(bound, capturedKey);

      final second = await runner.submit(
        intent: intent,
        generateUuid: () => 'must-not-mint',
        invokeService: (key) async {
          calls++;
          await invokeQuickReturn(service, intent, key);
        },
        postSuccessRefresh: () async {},
      );
      expect(second, QuickReturnSubmitOutcome.success);
      expect(calls, 2);
      expect(await returnCount(), 1);
    });

    test('T6/T7 post-commit refresh failure retains key then replay one return',
        () async {
      final runner = CustomerQuickReturnSubmitRunner();
      final intent = defaultIntent(productId: productId);
      var refreshAttempts = 0;

      final first = await runner.submit(
        intent: intent,
        generateUuid: b9QuickReturnIdempotencyKey,
        invokeService: (key) => invokeQuickReturn(service, intent, key),
        postSuccessRefresh: () async {
          refreshAttempts++;
          if (refreshAttempts == 1) {
            throw StateError('simulated refresh failure');
          }
        },
      );
      expect(first, QuickReturnSubmitOutcome.postSuccessRefreshFailed);
      expect(await returnCount(), 1);
      expect(await stockLevel(), initialStock + 1);

      final bound = runner.idempotency.keyForFingerprint(intent.fingerprintHash);
      expect(bound, isNotNull);

      final second = await runner.submit(
        intent: intent,
        generateUuid: () => 'must-not-mint',
        invokeService: (key) => invokeQuickReturn(service, intent, key),
        postSuccessRefresh: () async {},
      );
      expect(second, QuickReturnSubmitOutcome.success);
      expect(await returnCount(), 1);
      expect(await stockLevel(), initialStock + 1);
      expect(
        runner.idempotency.keyForFingerprint(intent.fingerprintHash),
        isNull,
      );
    });

    test('T4 reset/reopen preserves unresolved key', () async {
      final runner = CustomerQuickReturnSubmitRunner();
      final intent = defaultIntent(productId: productId);
      final keyBefore = runner.idempotency.prepareReturnKey(
        fingerprintHash: intent.fingerprintHash,
        generateUuid: b9QuickReturnIdempotencyKey,
      );
      final keyAfterReopen = runner.idempotency.prepareReturnKey(
        fingerprintHash: intent.fingerprintHash,
        generateUuid: () => 'must-not-mint',
      );
      expect(keyAfterReopen, keyBefore);
    });

    test('T9 double submit one service call', () async {
      final runner = CustomerQuickReturnSubmitRunner();
      final intent = defaultIntent(productId: productId);
      final gate = Completer<void>();
      final entered = Completer<void>();
      var calls = 0;

      Future<QuickReturnSubmitOutcome> invoke() => runner.submit(
            intent: intent,
            generateUuid: b9QuickReturnIdempotencyKey,
            invokeService: (key) async {
              calls++;
              if (!entered.isCompleted) entered.complete();
              await gate.future;
              await invokeQuickReturn(service, intent, key);
            },
            postSuccessRefresh: () async {},
          );

      final firstFuture = invoke();
      await entered.future;
      final second = await invoke();
      expect(second, QuickReturnSubmitOutcome.skippedInFlight);
      expect(calls, 1);
      gate.complete();
      expect(await firstFuture, QuickReturnSubmitOutcome.success);
    });

    test('T8 conflict retains key (runner synthetic)', () async {
      final runner = CustomerQuickReturnSubmitRunner();
      final intent = defaultIntent(productId: productId);
      final outcome = await runner.submit(
        intent: intent,
        generateUuid: b9QuickReturnIdempotencyKey,
        invokeService: (_) async {
          throw const QuickReturnIdempotencyConflictException();
        },
        postSuccessRefresh: () async {},
      );
      expect(outcome, QuickReturnSubmitOutcome.idempotencyConflict);
      expect(
        runner.idempotency.keyForFingerprint(intent.fingerprintHash),
        isNotNull,
      );
    });

    test('T8 real service conflict retains key without DB mutation', () async {
      final runner = CustomerQuickReturnSubmitRunner();
      final intentSealed = defaultIntent(productId: productId, quantity: 1);
      final intentConflict = defaultIntent(productId: productId, quantity: 2);
      final sealedKey = b9QuickReturnIdempotencyKey();

      await invokeQuickReturn(service, intentSealed, sealedKey);
      expect(await returnCount(), 1);
      final stockAfterSeal = await stockLevel();
      expect(stockAfterSeal, initialStock + 1);

      final outcome = await runner.submit(
        intent: intentConflict,
        generateUuid: () => sealedKey,
        invokeService: (key) => invokeQuickReturn(service, intentConflict, key),
        postSuccessRefresh: () async {},
      );
      expect(outcome, QuickReturnSubmitOutcome.idempotencyConflict);
      expect(await returnCount(), 1);
      expect(await stockLevel(), stockAfterSeal);
      expect(
        runner.idempotency.keyForFingerprint(intentConflict.fingerprintHash),
        sealedKey,
      );
    });

    test('T11 intentional identical new return receives new UUID', () async {
      final runner = CustomerQuickReturnSubmitRunner();
      final intent = defaultIntent(productId: productId);
      var mintSeq = 0;
      String mint() => 'b31-mint-${++mintSeq}';

      expect(
        await runner.submit(
          intent: intent,
          generateUuid: mint,
          invokeService: (key) => invokeQuickReturn(service, intent, key),
          postSuccessRefresh: () async {},
        ),
        QuickReturnSubmitOutcome.success,
      );
      expect(await returnCount(), 1);
      expect(mintSeq, 1);

      expect(
        await runner.submit(
          intent: intent,
          generateUuid: mint,
          invokeService: (key) => invokeQuickReturn(service, intent, key),
          postSuccessRefresh: () async {},
        ),
        QuickReturnSubmitOutcome.success,
      );
      expect(await returnCount(), 2);
      expect(mintSeq, 2);
      expect(await stockLevel(), initialStock + 2);
    });

    test('T13 payload change uses different key', () async {
      final runner = CustomerQuickReturnSubmitRunner();
      final intentA = defaultIntent(productId: productId);
      final intentB = QuickReturnSubmitIntent(
        productId: productId,
        quantity: 2,
        refundAmount: 20,
        reason: 'بدون فاتورة',
        userId: userId,
      );
      var mintSeq = 0;
      String mint() => 'b31-fp-${++mintSeq}';

      final keyA = runner.idempotency.prepareReturnKey(
        fingerprintHash: intentA.fingerprintHash,
        generateUuid: mint,
      );
      final keyB = runner.idempotency.prepareReturnKey(
        fingerprintHash: intentB.fingerprintHash,
        generateUuid: mint,
      );
      expect(keyB, isNot(keyA));
      expect(mintSeq, 2);
    });

    test('T14 service seals fingerprint including approvedByUserId', () async {
      final managerId = await db.into(db.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'B31 Manager',
              username: 'b31_mgr_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final key = b9QuickReturnIdempotencyKey();
      final intent = defaultIntent(
        productId: productId,
        approvedByUserId: managerId,
      );
      expect(intent.fingerprintHash, isNotEmpty);

      await invokeQuickReturn(service, intent, key);

      final row = await (db.select(db.customerQuickReturnIdempotency)
            ..where((t) => t.idempotencyKey.equals(key)))
          .getSingle();
      expect(row.fingerprintHash, intent.fingerprintHash);
    });
  });
}
