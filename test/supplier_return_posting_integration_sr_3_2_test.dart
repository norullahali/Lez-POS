import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';
import 'package:lez_pos/features/returns/models/supplier_return_draft_models.dart';
import 'package:lez_pos/features/returns/providers/supplier_return_draft_provider.dart';
import 'package:lez_pos/features/returns/providers/supplier_return_service_provider.dart';
import 'package:lez_pos/features/returns/repositories/supplier_return_read_repository.dart';
import 'package:lez_pos/features/returns/utils/supplier_return_posting_messages.dart';

void main() {
  group('SR.3.2 posting integration', () {
    late AppDatabase db;
    late RecordingSupplierReturnService recordingService;
    late ProviderContainer container;
    late int supplierId;
    late int productId;
    late int invoiceId;
    late int purchaseItemId;

    SupplierReturnPurchaseOption purchaseOption() {
      return SupplierReturnPurchaseOption(
        purchaseInvoiceId: invoiceId,
        supplierId: supplierId,
        supplierName: 'Supplier B',
        invoiceNumber: 'PI-200',
        purchaseDate: DateTime(2026, 4, 2),
        totalAmount: 50,
        status: 'CONFIRMED',
      );
    }

    Future<void> seedValidDraft() async {
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(purchaseOption());
      notifier.setLineQuantity(purchaseItemId, 2);
    }

    setUp(() async {
      db = AppDatabase.test();
      recordingService = RecordingSupplierReturnService(db);
      container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider
              .overrideWithValue(SupplierReturnReadRepository(db)),
          supplierReturnServiceProvider.overrideWithValue(recordingService),
        ],
      );

      supplierId = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('Supplier B')),
          );
      productId = await db.into(db.products).insert(
            const ProductsCompanion(name: Value('Part')),
          );
      invoiceId = await db.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(supplierId),
          purchaseDate: Value(DateTime(2026, 4, 2)),
          total: const Value(50),
          invoiceNumber: const Value('PI-200'),
        ),
        items: [
          {'productId': productId, 'qty': 5.0, 'cost': 5.0},
        ],
      );
      final items = await db.purchasesDao.getItemsForInvoice(invoiceId);
      purchaseItemId = items.single.id;
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('A) valid draft posts once and succeeds', () async {
      await seedValidDraft();
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      final ok = await notifier.submitReturn();
      expect(ok, isTrue);
      expect(recordingService.callCount, 1);
      final state = container.read(supplierReturnDraftProvider);
      expect(state.postingStatus, SupplierReturnPostingStatus.success);
      expect(state.lastPostedReturnId, isNotNull);
    });

    test('B) save disabled when draft invalid', () async {
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(purchaseOption());
      final state = container.read(supplierReturnDraftProvider);
      expect(state.canSave, isFalse);
      final ok = await notifier.submitReturn();
      expect(ok, isFalse);
      expect(recordingService.callCount, 0);
    });

    test('C) double submit triggers only one service call', () async {
      await seedValidDraft();
      recordingService.holdNextPost = Completer<void>();
      final notifier = container.read(supplierReturnDraftProvider.notifier);

      final first = notifier.submitReturn();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(supplierReturnDraftProvider).isPosting, isTrue);
      expect(container.read(supplierReturnDraftProvider).canSave, isFalse);

      final second = notifier.submitReturn();
      expect(await second, isFalse);
      expect(recordingService.callCount, 1);

      recordingService.holdNextPost!.complete();
      expect(await first, isTrue);
      expect(recordingService.callCount, 1);
    });

    test('D) service failure keeps draft open', () async {
      await seedValidDraft();
      recordingService.failure = const SupplierReturnPostingException(
        SupplierReturnPostingFailure.quantityExceedsReturnable,
        'exceeds',
      );
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      final before = container.read(supplierReturnDraftProvider);
      final ok = await notifier.submitReturn();
      expect(ok, isFalse);
      final after = container.read(supplierReturnDraftProvider);
      expect(after.lines, isNotEmpty);
      expect(after.selectedPurchase, isNotNull);
      expect(
        after.lines.first.selectedReturnQty,
        before.lines.first.selectedReturnQty,
      );
      expect(after.postingStatus, SupplierReturnPostingStatus.failure);
    });

    test('E) typed failure maps to Arabic message', () async {
      await seedValidDraft();
      recordingService.failure = const SupplierReturnPostingException(
        SupplierReturnPostingFailure.stockInsufficient,
        'stock',
      );
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.submitReturn();
      final state = container.read(supplierReturnDraftProvider);
      expect(
        state.postingErrorMessage,
        supplierReturnPostingFailureMessage(
          SupplierReturnPostingFailure.stockInsufficient,
        ),
      );
      expect(state.postingErrorMessage, isNot(contains('stock')));
    });

    test('F) successful posting increments refresh tick', () async {
      final before = container.read(supplierReturnsRefreshProvider);
      await seedValidDraft();
      await container.read(supplierReturnDraftProvider.notifier).submitReturn();
      final after = container.read(supplierReturnsRefreshProvider);
      expect(after, before + 1);
    });

    test('G) draft not cleared before success', () async {
      await seedValidDraft();
      recordingService.holdNextPost = Completer<void>();
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      final future = notifier.submitReturn();
      await Future<void>.delayed(Duration.zero);
      final mid = container.read(supplierReturnDraftProvider);
      expect(mid.lines, isNotEmpty);
      expect(mid.selectedPurchase, isNotNull);
      expect(mid.hasSelectedQty, isTrue);
      recordingService.holdNextPost!.complete();
      await future;
    });

    test('H) reset clears draft after success path close', () async {
      await seedValidDraft();
      await container.read(supplierReturnDraftProvider.notifier).submitReturn();
      container.read(supplierReturnDraftProvider.notifier).reset();
      final state = container.read(supplierReturnDraftProvider);
      expect(state.lines, isEmpty);
      expect(state.selectedPurchase, isNull);
      expect(state.postingStatus, SupplierReturnPostingStatus.idle);
    });

    test('I) posting state blocks duplicate submission', () async {
      await seedValidDraft();
      recordingService.holdNextPost = Completer<void>();
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      notifier.submitReturn();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(supplierReturnDraftProvider).canSave, isFalse);
      recordingService.holdNextPost!.complete();
    });

    test('J) service input uses canonical SR.2 contract only', () async {
      await seedValidDraft();
      await container.read(supplierReturnDraftProvider.notifier).submitReturn();
      final input = recordingService.lastInput!;
      expect(input.supplierId, supplierId);
      expect(input.purchaseInvoiceId, invoiceId);
      expect(input.lines, hasLength(1));
      expect(input.lines.single.purchaseItemId, purchaseItemId);
      expect(input.lines.single.quantity, 2);
    });
  });

  group('buildPostingInputFromDraft', () {
    test('maps purchase context and selected lines only', () {
      final purchase = SupplierReturnPurchaseOption(
        purchaseInvoiceId: 10,
        supplierId: 5,
        supplierName: 'S',
        invoiceNumber: 'INV',
        purchaseDate: DateTime(2026, 1, 1),
        totalAmount: 100,
        status: 'CONFIRMED',
      );
      const lines = [
        SupplierReturnDraftLine(
          purchaseItemId: 101,
          productId: 1,
          productName: 'A',
          purchasedQty: 10,
          alreadyReturnedQty: 0,
          returnableQty: 10,
          unitCost: 5,
          selectedReturnQty: 3,
        ),
        SupplierReturnDraftLine(
          purchaseItemId: 102,
          productId: 2,
          productName: 'B',
          purchasedQty: 8,
          alreadyReturnedQty: 0,
          returnableQty: 8,
          unitCost: 7,
        ),
      ];

      final input = buildPostingInputFromDraft(
        purchase,
        lines,
        reason: ' damaged ',
        notes: '',
      );
      expect(input, isNotNull);
      expect(input!.lines, hasLength(1));
      expect(input.lines.single.purchaseItemId, 101);
      expect(input.lines.single.quantity, 3);
      expect(input.reason, 'damaged');
      expect(input.notes, isNull);
    });
  });
}

class RecordingSupplierReturnService extends SupplierReturnService {
  RecordingSupplierReturnService(super.db);

  int callCount = 0;
  SupplierReturnPostingInput? lastInput;
  SupplierReturnPostingException? failure;
  Completer<void>? holdNextPost;
  int _nextReturnId = 9001;

  @override
  Future<int> postPurchaseLinkedReturn(SupplierReturnPostingInput input) async {
    callCount++;
    lastInput = input;
    if (failure != null) throw failure!;
    if (holdNextPost != null) await holdNextPost!.future;
    return _nextReturnId++;
  }
}
