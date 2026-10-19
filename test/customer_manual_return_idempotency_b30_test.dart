import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/manual_return_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/manual_return_service.dart';
import 'package:lez_pos/features/returns/customer_manual_return_idempotency.dart';

import 'support/customer_manual_return_test_keys.dart';

ManualReturnSubmitIntent defaultIntent({
  required int productId,
  int? userId,
  double quantity = 1,
}) {
  return ManualReturnSubmitIntent(
    productId: productId,
    quantity: quantity,
    unitPrice: 0,
    reason: 'سبب الإرجاع',
    userId: userId ?? 1,
  );
}

void main() {
  const initialStock = 100.0;
  const userId = 1;

  group('ManualReturnIntentFingerprint (B30 T1-T3)', () {
    test('T1 deterministic fingerprint', () {
      final a = computeManualReturnIntentFingerprint(
        productId: 5,
        quantity: 1,
        unitPrice: 0,
        reason: 'test',
        userId: 1,
      );
      final b = computeManualReturnIntentFingerprint(
        productId: 5,
        quantity: 1,
        unitPrice: 0,
        reason: 'test',
        userId: 1,
      );
      expect(b, a);
    });

    test('T2 material payload change different fingerprint', () {
      final base = computeManualReturnIntentFingerprint(
        productId: 5,
        quantity: 1,
        unitPrice: 0,
        reason: 'test',
        userId: 1,
      );
      final changedQty = computeManualReturnIntentFingerprint(
        productId: 5,
        quantity: 2,
        unitPrice: 0,
        reason: 'test',
        userId: 1,
      );
      expect(changedQty, isNot(base));
    });

    test('T3 equivalent normalized payload same fingerprint', () {
      final a = computeManualReturnIntentFingerprint(
        productId: 5,
        quantity: 1.0000004,
        unitPrice: 0,
        reason: '  trimmed  ',
        userId: 1,
      );
      final b = computeManualReturnIntentFingerprint(
        productId: 5,
        quantity: 1.000000,
        unitPrice: 0,
        reason: 'trimmed',
        userId: 1,
      );
      expect(b, a);
    });
  });

  group('CustomerManualReturnIdempotencyState (B30)', () {
    late CustomerManualReturnIdempotencyState state;
    var seq = 0;

    String nextKey() => 'b30-key-${++seq}';

    setUp(() {
      state = CustomerManualReturnIdempotencyState();
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

    test('T8 conflict retains key without rotation (state)', () {
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

  group('CustomerManualReturnSubmitRunner integration (B30)', () {
    late AppDatabase db;
    late ManualReturnService service;
    late int productId;

    Future<int> returnCount() async =>
        (await db.select(db.customerReturns).get()).length;

    Future<double> stockLevel() async => db.stockDao.getStock(productId);

    setUp(() async {
      db = AppDatabase.test();
      service = ManualReturnService(db);
      productId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('B30 Manual Product'),
              barcode: Value('B30-MR-1'),
              currentStock: Value(initialStock),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test('T10 success clears only completed fingerprint slot (runner)', () async {
      final runner = CustomerManualReturnSubmitRunner();
      final intentComplete = defaultIntent(productId: productId, quantity: 1);
      final intentPending = defaultIntent(productId: productId, quantity: 2);

      var mintSeq = 0;
      String mint() => 'b30-t10-${++mintSeq}';

      final pendingKey = runner.idempotency.prepareReturnKey(
        fingerprintHash: intentPending.fingerprintHash,
        generateUuid: mint,
      );
      expect(mintSeq, 1);

      final outcome = await runner.submit(
        intent: intentComplete,
        generateUuid: mint,
        invokeService: (key) => service.processManualReturn(
          idempotencyKey: key,
          productId: intentComplete.productId,
          quantity: intentComplete.quantity,
          unitPrice: intentComplete.unitPrice,
          reason: intentComplete.reason,
          userId: intentComplete.userId,
        ),
        postSuccessRefresh: () async {},
      );
      expect(outcome, ManualReturnSubmitOutcome.success);
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
      final runner = CustomerManualReturnSubmitRunner();
      final intent = defaultIntent(productId: productId);
      var calls = 0;
      String? capturedKey;

      final first = await runner.submit(
        intent: intent,
        generateUuid: () {
          capturedKey ??= b10ManualReturnIdempotencyKey();
          return capturedKey!;
        },
        invokeService: (_) async {
          calls++;
          throw StateError('pre-commit');
        },
        postSuccessRefresh: () async {},
      );
      expect(first, ManualReturnSubmitOutcome.serviceFailure);
      expect(calls, 1);

      final bound = runner.idempotency.keyForFingerprint(intent.fingerprintHash);
      expect(bound, isNotNull);
      expect(bound, capturedKey);

      final second = await runner.submit(
        intent: intent,
        generateUuid: () => 'must-not-mint',
        invokeService: (key) async {
          calls++;
          expect(key, bound);
          return service.processManualReturn(
            idempotencyKey: key,
            productId: intent.productId,
            quantity: intent.quantity,
            unitPrice: intent.unitPrice,
            reason: intent.reason,
            userId: intent.userId,
          );
        },
        postSuccessRefresh: () async {},
      );
      expect(second, ManualReturnSubmitOutcome.success);
      expect(calls, 2);
      expect(await returnCount(), 1);
    });

    test('T6/T7 post-commit refresh failure retains key then replay one return',
        () async {
      final runner = CustomerManualReturnSubmitRunner();
      final intent = defaultIntent(productId: productId);
      var refreshAttempts = 0;

      final first = await runner.submit(
        intent: intent,
        generateUuid: b10ManualReturnIdempotencyKey,
        invokeService: (key) => service.processManualReturn(
          idempotencyKey: key,
          productId: intent.productId,
          quantity: intent.quantity,
          unitPrice: intent.unitPrice,
          reason: intent.reason,
          userId: intent.userId,
        ),
        postSuccessRefresh: () async {
          refreshAttempts++;
          if (refreshAttempts == 1) {
            throw StateError('simulated refresh failure');
          }
        },
      );
      expect(first, ManualReturnSubmitOutcome.postSuccessRefreshFailed);
      expect(await returnCount(), 1);
      expect(await stockLevel(), initialStock + 1);

      final bound = runner.idempotency.keyForFingerprint(intent.fingerprintHash);
      expect(bound, isNotNull);

      final second = await runner.submit(
        intent: intent,
        generateUuid: () => 'must-not-mint',
        invokeService: (key) => service.processManualReturn(
          idempotencyKey: key,
          productId: intent.productId,
          quantity: intent.quantity,
          unitPrice: intent.unitPrice,
          reason: intent.reason,
          userId: intent.userId,
        ),
        postSuccessRefresh: () async {},
      );
      expect(second, ManualReturnSubmitOutcome.success);
      expect(await returnCount(), 1);
      expect(await stockLevel(), initialStock + 1);
      expect(
        runner.idempotency.keyForFingerprint(intent.fingerprintHash),
        isNull,
      );
    });

    test('T4 reset/reopen preserves unresolved key', () async {
      final runner = CustomerManualReturnSubmitRunner();
      final intent = defaultIntent(productId: productId);
      final keyBefore = runner.idempotency.prepareReturnKey(
        fingerprintHash: intent.fingerprintHash,
        generateUuid: b10ManualReturnIdempotencyKey,
      );
      final keyAfterReopen = runner.idempotency.prepareReturnKey(
        fingerprintHash: intent.fingerprintHash,
        generateUuid: () => 'must-not-mint',
      );
      expect(keyAfterReopen, keyBefore);
    });

    test('T9 double submit one service call', () async {
      final runner = CustomerManualReturnSubmitRunner();
      final intent = defaultIntent(productId: productId);
      final gate = Completer<void>();
      final entered = Completer<void>();
      var calls = 0;

      Future<ManualReturnSubmitOutcome> invoke() => runner.submit(
            intent: intent,
            generateUuid: b10ManualReturnIdempotencyKey,
            invokeService: (key) async {
              calls++;
              if (!entered.isCompleted) entered.complete();
              await gate.future;
              return service.processManualReturn(
                idempotencyKey: key,
                productId: intent.productId,
                quantity: intent.quantity,
                unitPrice: intent.unitPrice,
                reason: intent.reason,
                userId: intent.userId,
              );
            },
            postSuccessRefresh: () async {},
          );

      final firstFuture = invoke();
      await entered.future;
      final second = await invoke();
      expect(second, ManualReturnSubmitOutcome.skippedInFlight);
      expect(calls, 1);
      gate.complete();
      expect(await firstFuture, ManualReturnSubmitOutcome.success);
    });

    test('T8 conflict retains key (runner synthetic)', () async {
      final runner = CustomerManualReturnSubmitRunner();
      final intent = defaultIntent(productId: productId);
      final outcome = await runner.submit(
        intent: intent,
        generateUuid: b10ManualReturnIdempotencyKey,
        invokeService: (_) async {
          throw const ManualReturnIdempotencyConflictException();
        },
        postSuccessRefresh: () async {},
      );
      expect(outcome, ManualReturnSubmitOutcome.idempotencyConflict);
      expect(
        runner.idempotency.keyForFingerprint(intent.fingerprintHash),
        isNotNull,
      );
    });

    test('T8 real service conflict retains key without DB mutation', () async {
      final runner = CustomerManualReturnSubmitRunner();
      final intentSealed = defaultIntent(productId: productId, quantity: 1);
      final intentConflict = defaultIntent(productId: productId, quantity: 2);
      final sealedKey = b10ManualReturnIdempotencyKey();

      await service.processManualReturn(
        idempotencyKey: sealedKey,
        productId: intentSealed.productId,
        quantity: intentSealed.quantity,
        unitPrice: intentSealed.unitPrice,
        reason: intentSealed.reason,
        userId: intentSealed.userId,
      );
      expect(await returnCount(), 1);
      final stockAfterSeal = await stockLevel();
      expect(stockAfterSeal, initialStock + 1);

      final outcome = await runner.submit(
        intent: intentConflict,
        generateUuid: () => sealedKey,
        invokeService: (key) => service.processManualReturn(
          idempotencyKey: key,
          productId: intentConflict.productId,
          quantity: intentConflict.quantity,
          unitPrice: intentConflict.unitPrice,
          reason: intentConflict.reason,
          userId: intentConflict.userId,
        ),
        postSuccessRefresh: () async {},
      );
      expect(outcome, ManualReturnSubmitOutcome.idempotencyConflict);
      expect(await returnCount(), 1);
      expect(await stockLevel(), stockAfterSeal);
      expect(
        runner.idempotency.keyForFingerprint(intentConflict.fingerprintHash),
        sealedKey,
      );
    });

    test('T11 intentional identical new return receives new UUID', () async {
      final runner = CustomerManualReturnSubmitRunner();
      final intent = defaultIntent(productId: productId);
      var mintSeq = 0;
      String mint() => 'b30-mint-${++mintSeq}';

      expect(
        await runner.submit(
          intent: intent,
          generateUuid: mint,
          invokeService: (key) => service.processManualReturn(
            idempotencyKey: key,
            productId: intent.productId,
            quantity: intent.quantity,
            unitPrice: intent.unitPrice,
            reason: intent.reason,
            userId: intent.userId,
          ),
          postSuccessRefresh: () async {},
        ),
        ManualReturnSubmitOutcome.success,
      );
      expect(await returnCount(), 1);
      expect(mintSeq, 1);

      expect(
        await runner.submit(
          intent: intent,
          generateUuid: mint,
          invokeService: (key) => service.processManualReturn(
            idempotencyKey: key,
            productId: intent.productId,
            quantity: intent.quantity,
            unitPrice: intent.unitPrice,
            reason: intent.reason,
            userId: intent.userId,
          ),
          postSuccessRefresh: () async {},
        ),
        ManualReturnSubmitOutcome.success,
      );
      expect(await returnCount(), 2);
      expect(mintSeq, 2);
      expect(await stockLevel(), initialStock + 2);
    });

    test('T13 payload change uses different key', () async {
      final runner = CustomerManualReturnSubmitRunner();
      final intentA = defaultIntent(productId: productId);
      final intentB = ManualReturnSubmitIntent(
        productId: productId,
        quantity: 2,
        unitPrice: 0,
        reason: 'سبب الإرجاع',
        userId: userId,
      );
      var mintSeq = 0;
      String mint() => 'b30-fp-${++mintSeq}';

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
  });
}
