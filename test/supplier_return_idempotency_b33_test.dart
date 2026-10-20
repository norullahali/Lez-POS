import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lez_pos/core/constants/movement_types.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/supplier_return_fingerprint.dart';
import 'package:lez_pos/core/services/supplier_return_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/supplier_return_posting_result.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';
import 'package:lez_pos/features/returns/models/supplier_return_draft_models.dart';
import 'package:lez_pos/features/returns/providers/supplier_return_draft_provider.dart';
import 'package:lez_pos/features/returns/providers/supplier_return_service_provider.dart';
import 'package:lez_pos/features/returns/repositories/supplier_return_read_repository.dart';
import 'package:lez_pos/features/returns/supplier_return_submit_idempotency.dart';

import 'support/supplier_return_posting_helpers.dart';

SupplierReturnPostingInput b33PostingInput({
  required int supplierId,
  required int invoiceId,
  required int purchaseItemId,
  double quantity = 2,
  String? reason,
  String? notes,
  List<SupplierReturnPostingLine>? lines,
}) {
  return SupplierReturnPostingInput(
    supplierId: supplierId,
    purchaseInvoiceId: invoiceId,
    lines: lines ??
        [
          SupplierReturnPostingLine(
            purchaseItemId: purchaseItemId,
            quantity: quantity,
          ),
        ],
    reason: reason,
    notes: notes,
  );
}

SupplierReturnPurchaseOption b33PurchaseOption({
  required int invoiceId,
  required int supplierId,
  String invoiceNumber = 'PI-B33',
}) {
  return SupplierReturnPurchaseOption(
    purchaseInvoiceId: invoiceId,
    supplierId: supplierId,
    supplierName: 'B33 Supplier',
    invoiceNumber: invoiceNumber,
    purchaseDate: DateTime(2026, 5, 1),
    totalAmount: 100,
    status: 'CONFIRMED',
  );
}

class _FailOnceSupplierReturnService extends SupplierReturnService {
  _FailOnceSupplierReturnService(super.db);

  bool failNext = true;
  int postCalls = 0;
  final List<String> keysUsed = [];

  @override
  Future<SupplierReturnPostingResult> postPurchaseLinkedReturn({
    required String idempotencyKey,
    required SupplierReturnPostingInput input,
  }) async {
    postCalls++;
    keysUsed.add(idempotencyKey);
    if (failNext) {
      failNext = false;
      throw Exception('forced first submit failure');
    }
    return super.postPurchaseLinkedReturn(
      idempotencyKey: idempotencyKey,
      input: input,
    );
  }
}

class _ConflictTwiceService extends SupplierReturnService {
  _ConflictTwiceService(super.db);

  int calls = 0;
  String? lastKey;

  @override
  Future<SupplierReturnPostingResult> postPurchaseLinkedReturn({
    required String idempotencyKey,
    required SupplierReturnPostingInput input,
  }) async {
    calls++;
    lastKey = idempotencyKey;
    throw const SupplierReturnIdempotencyConflictException();
  }
}

class _HoldAfterCommitService extends SupplierReturnService {
  _HoldAfterCommitService(super.db);

  Completer<void>? holdAfterCommit;

  @override
  Future<SupplierReturnPostingResult> postPurchaseLinkedReturn({
    required String idempotencyKey,
    required SupplierReturnPostingInput input,
  }) async {
    final result = await super.postPurchaseLinkedReturn(
      idempotencyKey: idempotencyKey,
      input: input,
    );
    if (holdAfterCommit != null) {
      await holdAfterCommit!.future;
    }
    return result;
  }
}

void main() {
  group('B33 supplier return UI idempotency', () {
    late AppDatabase db;
    late SupplierReturnService service;
    late int supplierId;
    late int productId;
    late int invoiceId;
    late int purchaseItemId;
    late int invoiceId2;

    Future<int> supplierReturnCount() async =>
        (await db.select(db.supplierReturns).get()).length;

    Future<int> idempotencyRowCount() async =>
        (await db.select(db.supplierReturnIdempotency).get()).length;

    Future<int> returnOutLedgerCount() async =>
        (await (db.select(db.stockLedger)
              ..where(
                  (l) => l.movementType.equals(StockMovementType.returnOut.code)))
            .get())
            .length;

    Future<int> supplierReturnTxnCount() async =>
        (await (db.select(db.supplierTransactions)
              ..where((t) => t.type.equals('RETURN')))
            .get())
            .length;

    Future<void> seedSecondInvoice() async {
      invoiceId2 = await db.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(supplierId),
          purchaseDate: Value(DateTime(2026, 5, 2)),
          total: const Value(80),
          invoiceNumber: const Value('PI-B33-2'),
        ),
        items: [
          {'productId': productId, 'qty': 10.0, 'cost': 4.0},
        ],
      );
    }

    setUp(() async {
      db = AppDatabase.test();
      service = SupplierReturnService(db);

      supplierId = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('B33 Supplier')),
          );
      productId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('B33 Part'),
              currentStock: Value(0),
            ),
          );
      invoiceId = await db.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(supplierId),
          purchaseDate: Value(DateTime(2026, 5, 1)),
          total: const Value(100),
          invoiceNumber: const Value('PI-B33'),
          debtAmount: const Value(100),
        ),
        items: [
          {'productId': productId, 'qty': 30.0, 'cost': 5.0},
        ],
      );
      final items = await db.purchasesDao.getItemsForInvoice(invoiceId);
      purchaseItemId = items.single.id;
      await seedSecondInvoice();
    });

    tearDown(() async => db.close());

    test('T1 fingerprint delegation and line order independence', () {
      final purchase = b33PurchaseOption(
        invoiceId: invoiceId,
        supplierId: supplierId,
      );
      final lines = [
        SupplierReturnDraftLine(
          purchaseItemId: purchaseItemId,
          productId: productId,
          productName: 'P',
          purchasedQty: 10,
          alreadyReturnedQty: 0,
          returnableQty: 10,
          unitCost: 5,
          selectedReturnQty: 2,
        ),
      ];
      final input = buildPostingInputFromDraft(
        purchase,
        lines,
        reason: ' damaged ',
        notes: '',
      )!;
      expect(
        computeSupplierReturnIntentFingerprint(input),
        SupplierReturnFingerprint.compute(input),
      );

      final unordered = b33PostingInput(
        supplierId: supplierId,
        invoiceId: invoiceId,
        purchaseItemId: purchaseItemId,
        lines: [
          SupplierReturnPostingLine(purchaseItemId: purchaseItemId, quantity: 2),
          SupplierReturnPostingLine(purchaseItemId: purchaseItemId, quantity: 1),
        ],
      );
      final ordered = b33PostingInput(
        supplierId: supplierId,
        invoiceId: invoiceId,
        purchaseItemId: purchaseItemId,
        lines: [
          SupplierReturnPostingLine(purchaseItemId: purchaseItemId, quantity: 1),
          SupplierReturnPostingLine(purchaseItemId: purchaseItemId, quantity: 2),
        ],
      );
      expect(
        SupplierReturnFingerprint.compute(unordered),
        SupplierReturnFingerprint.compute(ordered),
      );
    });

    test('T2 same intent same UUID', () {
      final state = SupplierReturnIdempotencyState();
      var n = 0;
      const fp = 'fp-same';
      final k1 = state.prepareReturnKey(
        fingerprintHash: fp,
        generateUuid: () => 'key-${++n}',
      );
      final k2 = state.prepareReturnKey(
        fingerprintHash: fp,
        generateUuid: () => 'key-${++n}',
      );
      expect(k2, k1);
      expect(n, 1);
    });

    test('T3 changed qty new UUID', () {
      final inputA = b33PostingInput(
        supplierId: supplierId,
        invoiceId: invoiceId,
        purchaseItemId: purchaseItemId,
        quantity: 2,
      );
      final inputB = b33PostingInput(
        supplierId: supplierId,
        invoiceId: invoiceId,
        purchaseItemId: purchaseItemId,
        quantity: 3,
      );
      final state = SupplierReturnIdempotencyState();
      var n = 0;
      final kA = state.prepareReturnKey(
        fingerprintHash: computeSupplierReturnIntentFingerprint(inputA),
        generateUuid: () => 'k-${++n}',
      );
      final kB = state.prepareReturnKey(
        fingerprintHash: computeSupplierReturnIntentFingerprint(inputB),
        generateUuid: () => 'k-${++n}',
      );
      expect(kB, isNot(kA));
    });

    test('T4 conflict retains key', () async {
      final runner = SupplierReturnSubmitRunner();
      final input = b33PostingInput(
        supplierId: supplierId,
        invoiceId: invoiceId,
        purchaseItemId: purchaseItemId,
      );
      final intent = SupplierReturnSubmitIntent(input: input);
      final fp = intent.fingerprintHash;
      var n = 0;

      final conflictService = _ConflictTwiceService(db);
      Future<SupplierReturnSubmitOutcome> runOnce() => runner.submit(
            intent: intent,
            generateUuid: () => 'conflict-key-${++n}',
            isSubmitStillCurrent: () => true,
            invokeService: (key) => conflictService.postPurchaseLinkedReturn(
              idempotencyKey: key,
              input: input,
            ),
            postSuccessRefresh: (_) async {},
          );

      expect(await runOnce(), SupplierReturnSubmitOutcome.idempotencyConflict);
      expect(await runOnce(), SupplierReturnSubmitOutcome.idempotencyConflict);
      expect(conflictService.calls, 2);
      expect(conflictService.lastKey, runner.idempotency.keyForFingerprint(fp));
      expect(n, 1);
    });

    test('T5 pre-commit failure retains key', () async {
      final spy = _FailOnceSupplierReturnService(db);
      final container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider
              .overrideWithValue(SupplierReturnReadRepository(db)),
          supplierReturnServiceProvider.overrideWithValue(spy),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(
        b33PurchaseOption(invoiceId: invoiceId, supplierId: supplierId),
      );
      notifier.setLineQuantity(purchaseItemId, 2);

      expect(await notifier.submitReturn(), isFalse);
      expect(await notifier.submitReturn(), isTrue);
      expect(spy.postCalls, 2);
      expect(spy.keysUsed[0], spy.keysUsed[1]);
      expect(await supplierReturnCount(), 1);
    });

    test('T6 post-commit refresh failure retains key and replays', () async {
      final runner = SupplierReturnSubmitRunner();
      final input = b33PostingInput(
        supplierId: supplierId,
        invoiceId: invoiceId,
        purchaseItemId: purchaseItemId,
      );
      final intent = SupplierReturnSubmitIntent(input: input);
      final fp = intent.fingerprintHash;

      final first = await runner.submit(
        intent: intent,
        generateUuid: () => 'b33-refresh-fail-key',
        isSubmitStillCurrent: () => true,
        invokeService: (key) => service.postPurchaseLinkedReturn(
          idempotencyKey: key,
          input: input,
        ),
        postSuccessRefresh: (_) async {
          throw Exception('refresh fail');
        },
      );
      expect(first, SupplierReturnSubmitOutcome.postSuccessRefreshFailed);
      expect(runner.idempotency.keyForFingerprint(fp), isNotNull);
      expect(await supplierReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await returnOutLedgerCount(), 1);
      expect(await supplierReturnTxnCount(), 1);

      final second = await runner.submit(
        intent: intent,
        generateUuid: () => 'should-not-mint',
        isSubmitStillCurrent: () => true,
        invokeService: (key) => service.postPurchaseLinkedReturn(
          idempotencyKey: key,
          input: input,
        ),
        postSuccessRefresh: (_) async {},
      );
      expect(second, SupplierReturnSubmitOutcome.success);
      expect(await supplierReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await returnOutLedgerCount(), 1);
      expect(await supplierReturnTxnCount(), 1);
    });

    test('T7 success clears slot for fingerprint', () async {
      final runner = SupplierReturnSubmitRunner();
      final input = b33PostingInput(
        supplierId: supplierId,
        invoiceId: invoiceId,
        purchaseItemId: purchaseItemId,
      );
      final intent = SupplierReturnSubmitIntent(input: input);
      final fp = intent.fingerprintHash;

      await runner.submit(
        intent: intent,
        generateUuid: () => 'b33-clear-slot',
        isSubmitStillCurrent: () => true,
        invokeService: (key) => service.postPurchaseLinkedReturn(
          idempotencyKey: key,
          input: input,
        ),
        postSuccessRefresh: (_) async {},
      );
      expect(runner.idempotency.keyForFingerprint(fp), isNull);

      final nextKey = runner.idempotency.prepareReturnKey(
        fingerprintHash: fp,
        generateUuid: () => 'b33-new-op-key',
      );
      expect(nextKey, 'b33-new-op-key');
    });

    test('T8 in-flight duplicate does not double-call service', () async {
      final hold = Completer<void>();
      final recording = _FailOnceSupplierReturnService(db)..failNext = false;
      final runner = SupplierReturnSubmitRunner();
      final input = b33PostingInput(
        supplierId: supplierId,
        invoiceId: invoiceId,
        purchaseItemId: purchaseItemId,
      );
      final intent = SupplierReturnSubmitIntent(input: input);

      var invokeCount = 0;
      Future<SupplierReturnSubmitOutcome> invoke() => runner.submit(
            intent: intent,
            generateUuid: () => 'in-flight-key',
            isSubmitStillCurrent: () => true,
            invokeService: (key) async {
              invokeCount++;
              await hold.future;
              return recording.postPurchaseLinkedReturn(
                idempotencyKey: key,
                input: input,
              );
            },
            postSuccessRefresh: (_) async {},
          );

      final f1 = invoke();
      await Future<void>.delayed(Duration.zero);
      final f2 = invoke();
      expect(await f2, SupplierReturnSubmitOutcome.skippedInFlight);
      expect(invokeCount, 1);
      hold.complete();
      expect(await f1, SupplierReturnSubmitOutcome.success);
      expect(invokeCount, 1);
    });

    test('T9 reset preserves map entry', () async {
      final spy = _FailOnceSupplierReturnService(db);
      final container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider
              .overrideWithValue(SupplierReturnReadRepository(db)),
          supplierReturnServiceProvider.overrideWithValue(spy),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(
        b33PurchaseOption(invoiceId: invoiceId, supplierId: supplierId),
      );
      notifier.setLineQuantity(purchaseItemId, 2);
      final input = buildPostingInputFromDraft(
        notifier.state.selectedPurchase!,
        notifier.state.lines,
      )!;
      final fp = computeSupplierReturnIntentFingerprint(input);

      expect(await notifier.submitReturn(), isFalse);
      notifier.reset();
      expect(
        notifier.submitRunnerForTesting.idempotency.keyForFingerprint(fp),
        isNotNull,
      );
    });

    test('T10 purchase switch retains prior fingerprint slot', () async {
      final container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider
              .overrideWithValue(SupplierReturnReadRepository(db)),
          supplierReturnServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(supplierReturnDraftProvider.notifier);
      final purchaseA = b33PurchaseOption(invoiceId: invoiceId, supplierId: supplierId);
      await notifier.selectPurchase(purchaseA);
      notifier.setLineQuantity(purchaseItemId, 2);
      final inputA = buildPostingInputFromDraft(
        purchaseA,
        notifier.state.lines,
      )!;
      final fpA = computeSupplierReturnIntentFingerprint(inputA);
      final keyBefore = notifier.submitRunnerForTesting.idempotency
          .prepareReturnKey(
        fingerprintHash: fpA,
        generateUuid: () => 'key-a',
      );

      final items2 = await db.purchasesDao.getItemsForInvoice(invoiceId2);
      final purchaseB = b33PurchaseOption(
        invoiceId: invoiceId2,
        supplierId: supplierId,
        invoiceNumber: 'PI-B33-2',
      );
      await notifier.selectPurchase(purchaseB);
      expect(
        notifier.submitRunnerForTesting.idempotency.keyForFingerprint(fpA),
        keyBefore,
      );

      await notifier.selectPurchase(purchaseA);
      notifier.setLineQuantity(purchaseItemId, 2);
      final keyAfter = notifier.submitRunnerForTesting.idempotency
          .prepareReturnKey(
        fingerprintHash: fpA,
        generateUuid: () => 'key-a-new',
      );
      expect(keyAfter, keyBefore);
    });

    test('T11 notifier E2E refresh fail then replay', () async {
      final container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider
              .overrideWithValue(SupplierReturnReadRepository(db)),
          supplierReturnServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(
        b33PurchaseOption(invoiceId: invoiceId, supplierId: supplierId),
      );
      notifier.setLineQuantity(purchaseItemId, 2);
      final input = buildPostingInputFromDraft(
        notifier.state.selectedPurchase!,
        notifier.state.lines,
      )!;
      final fp = computeSupplierReturnIntentFingerprint(input);

      notifier.failNextPostSuccessRefreshForTesting = true;
      expect(await notifier.submitReturn(), isFalse);
      expect(
        notifier.submitRunnerForTesting.idempotency.keyForFingerprint(fp),
        isNotNull,
      );
      expect(await supplierReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await returnOutLedgerCount(), 1);
      expect(await supplierReturnTxnCount(), 1);

      final stickyKey =
          notifier.submitRunnerForTesting.idempotency.keyForFingerprint(fp)!;
      expect(await notifier.submitReturn(), isTrue);
      expect(
        notifier.submitRunnerForTesting.idempotency.keyForFingerprint(fp),
        isNull,
      );
      expect(await supplierReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await returnOutLedgerCount(), 1);
      expect(await supplierReturnTxnCount(), 1);
      expect(stickyKey, isNotEmpty);
    });

    test('T12 intent A to B after failure uses distinct keys', () async {
      final spy = _FailOnceSupplierReturnService(db);
      final container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider
              .overrideWithValue(SupplierReturnReadRepository(db)),
          supplierReturnServiceProvider.overrideWithValue(spy),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(
        b33PurchaseOption(invoiceId: invoiceId, supplierId: supplierId),
      );
      notifier.setLineQuantity(purchaseItemId, 2);
      expect(await notifier.submitReturn(), isFalse);

      notifier.setLineQuantity(purchaseItemId, 3);
      expect(await notifier.submitReturn(), isTrue);
      expect(spy.keysUsed.length, 2);
      expect(spy.keysUsed[0], isNot(spy.keysUsed[1]));
    });

    test('T13 reconstruct intent A after editing to B', () async {
      final spy = _FailOnceSupplierReturnService(db);
      final container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider
              .overrideWithValue(SupplierReturnReadRepository(db)),
          supplierReturnServiceProvider.overrideWithValue(spy),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(
        b33PurchaseOption(invoiceId: invoiceId, supplierId: supplierId),
      );
      notifier.setLineQuantity(purchaseItemId, 2);
      expect(await notifier.submitReturn(), isFalse);
      final keyA = spy.keysUsed.single;

      notifier.setLineQuantity(purchaseItemId, 3);
      notifier.setLineQuantity(purchaseItemId, 2);
      expect(await notifier.submitReturn(), isTrue);
      expect(spy.keysUsed.last, keyA);
      expect(await supplierReturnCount(), 1);
    });

    test('T14 two fingerprints never share a key', () {
      final state = SupplierReturnIdempotencyState();
      var n = 0;
      final inputA = b33PostingInput(
        supplierId: supplierId,
        invoiceId: invoiceId,
        purchaseItemId: purchaseItemId,
        quantity: 1,
      );
      final inputB = b33PostingInput(
        supplierId: supplierId,
        invoiceId: invoiceId,
        purchaseItemId: purchaseItemId,
        quantity: 2,
      );
      final kA = state.prepareReturnKey(
        fingerprintHash: computeSupplierReturnIntentFingerprint(inputA),
        generateUuid: () => 'k-${++n}',
      );
      final kB = state.prepareReturnKey(
        fingerprintHash: computeSupplierReturnIntentFingerprint(inputB),
        generateUuid: () => 'k-${++n}',
      );
      expect(kA, isNot(kB));
    });

    test('T15 backToPurchaseSelection retains map without in-flight post', () async {
      final spy = _FailOnceSupplierReturnService(db);
      final container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider
              .overrideWithValue(SupplierReturnReadRepository(db)),
          supplierReturnServiceProvider.overrideWithValue(spy),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(supplierReturnDraftProvider.notifier);
      final purchase = b33PurchaseOption(invoiceId: invoiceId, supplierId: supplierId);
      await notifier.selectPurchase(purchase);
      notifier.setLineQuantity(purchaseItemId, 2);
      expect(await notifier.submitReturn(), isFalse);
      final keyA = spy.keysUsed.single;

      notifier.backToPurchaseSelection();
      await notifier.selectPurchase(purchase);
      notifier.setLineQuantity(purchaseItemId, 2);
      expect(await notifier.submitReturn(), isTrue);
      expect(spy.keysUsed.last, keyA);
    });

    test('T16 stale completion after reset does not clear key', () async {
      final holdService = _HoldAfterCommitService(db);
      final hold = Completer<void>();
      holdService.holdAfterCommit = hold;

      final container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider
              .overrideWithValue(SupplierReturnReadRepository(db)),
          supplierReturnServiceProvider.overrideWithValue(holdService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(
        b33PurchaseOption(invoiceId: invoiceId, supplierId: supplierId),
      );
      notifier.setLineQuantity(purchaseItemId, 2);
      final input = buildPostingInputFromDraft(
        notifier.state.selectedPurchase!,
        notifier.state.lines,
      )!;
      final fp = computeSupplierReturnIntentFingerprint(input);

      final submitFuture = notifier.submitReturn();
      await Future<void>.delayed(Duration.zero);
      notifier.reset();
      hold.complete();
      expect(await submitFuture, isFalse);
      expect(
        notifier.submitRunnerForTesting.idempotency.keyForFingerprint(fp),
        isNotNull,
      );
      expect(
        container.read(supplierReturnDraftProvider).postingStatus,
        SupplierReturnPostingStatus.idle,
      );
    });

    test('T17 stale completion after commit still allows single return replay', () async {
      final holdService = _HoldAfterCommitService(db);
      final hold = Completer<void>();
      holdService.holdAfterCommit = hold;

      final container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider
              .overrideWithValue(SupplierReturnReadRepository(db)),
          supplierReturnServiceProvider.overrideWithValue(holdService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(
        b33PurchaseOption(invoiceId: invoiceId, supplierId: supplierId),
      );
      notifier.setLineQuantity(purchaseItemId, 2);

      final submitFuture = notifier.submitReturn();
      await Future<void>.delayed(Duration.zero);
      notifier.reset();
      hold.complete();
      expect(await submitFuture, isFalse);
      expect(await supplierReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);

      await notifier.selectPurchase(
        b33PurchaseOption(invoiceId: invoiceId, supplierId: supplierId),
      );
      notifier.setLineQuantity(purchaseItemId, 2);
      expect(await notifier.submitReturn(), isTrue);
      expect(await supplierReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await returnOutLedgerCount(), 1);
      expect(await supplierReturnTxnCount(), 1);
    });
  });
}
