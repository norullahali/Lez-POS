import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/theme/app_theme.dart';
import 'package:lez_pos/features/returns/models/supplier_return_draft_models.dart';
import 'package:lez_pos/features/returns/providers/supplier_return_draft_provider.dart';
import 'package:lez_pos/features/returns/repositories/supplier_return_read_repository.dart';
import 'package:lez_pos/features/returns/screens/supplier_returns_screen.dart';
import 'package:lez_pos/features/returns/screens/widgets/create_supplier_return_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupplierReturnReadRepository', () {
    late AppDatabase db;
    late SupplierReturnReadRepository repo;
    late int supplierId;
    late int productId;
    late int product2Id;
    late int invoiceId;
    late int purchaseItem1Id;
    late int purchaseItem2Id;

    setUp(() async {
      db = AppDatabase.test();
      repo = SupplierReturnReadRepository(db);

      supplierId = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('Supplier A')),
          );
      productId = await db.into(db.products).insert(
            const ProductsCompanion(name: Value('Widget')),
          );
      product2Id = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('Gadget'),
              barcode: Value('GADGET-SR31'),
            ),
          );

      invoiceId = await db.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(supplierId),
          purchaseDate: Value(DateTime(2026, 4, 1)),
          total: const Value(100),
          invoiceNumber: const Value('PI-100'),
        ),
        items: [
          {'productId': productId, 'qty': 10.0, 'cost': 5.0},
          {'productId': product2Id, 'qty': 8.0, 'cost': 5.0},
        ],
      );

      final items = await db.purchasesDao.getItemsForInvoice(invoiceId);
      purchaseItem1Id = items.firstWhere((i) => i.productId == productId).id;
      purchaseItem2Id = items.firstWhere((i) => i.productId == product2Id).id;
    });

    tearDown(() async => db.close());

    Future<void> seedLinkedReturn(int purchaseItemId, double qty) async {
      final returnId = await db.into(db.supplierReturns).insert(
            SupplierReturnsCompanion(
              supplierId: Value(supplierId),
              purchaseInvoiceId: Value(invoiceId),
              returnNumber:
                  Value('SR-SEED-${DateTime.now().microsecondsSinceEpoch}'),
            ),
          );
      await db.into(db.supplierReturnItems).insert(
            SupplierReturnItemsCompanion(
              returnId: Value(returnId),
              purchaseItemId: Value(purchaseItemId),
              productId: Value(productId),
              productName: const Value('Widget'),
              quantity: Value(qty),
              unitCost: const Value(5),
              total: Value(qty * 5),
            ),
          );
    }

    test('B) eligible purchases include selected invoice', () async {
      final options = await repo.getEligiblePurchases();
      expect(options.any((o) => o.purchaseInvoiceId == invoiceId), isTrue);
    });

    test('C/D) loads purchase items with SR.1 returnable quantities', () async {
      final lines = await repo.loadDraftLines(invoiceId);
      expect(lines, hasLength(2));

      final line1 =
          lines.firstWhere((l) => l.purchaseItemId == purchaseItem1Id);
      final daoReturnable = await db.returnsDao
          .getReturnableQuantityForPurchaseItem(purchaseItem1Id);
      expect(line1.returnableQty, daoReturnable);
      expect(line1.purchasedQty, 10);
    });

    test('E) same product on different lines stays isolated', () async {
      await seedLinkedReturn(purchaseItem1Id, 3);
      final lines = await repo.loadDraftLines(invoiceId);
      final line1 =
          lines.firstWhere((l) => l.purchaseItemId == purchaseItem1Id);
      final line2 =
          lines.firstWhere((l) => l.purchaseItemId == purchaseItem2Id);
      expect(line1.returnableQty, 7);
      expect(line2.returnableQty, 8);
    });

    test('F) previous returns reduce displayed available quantity', () async {
      await seedLinkedReturn(purchaseItem1Id, 4);
      final lines = await repo.loadDraftLines(invoiceId);
      final line1 =
          lines.firstWhere((l) => l.purchaseItemId == purchaseItem1Id);
      expect(line1.alreadyReturnedQty, 4);
      expect(line1.returnableQty, 6);
    });

    test('I) zero-returnable purchase lines are reported', () async {
      await seedLinkedReturn(purchaseItem1Id, 10);
      final lines = await repo.loadDraftLines(invoiceId);
      final line1 =
          lines.firstWhere((l) => l.purchaseItemId == purchaseItem1Id);
      expect(line1.returnableQty, 0);
    });

    test('J) read workflow has no posting side effects', () async {
      final returnsBefore = (await db.select(db.supplierReturns).get()).length;
      final stockBefore = await db.stockDao.getStock(productId);
      final balanceBefore = await db.supplierAccountsDao.getBalance(supplierId);

      await repo.getEligiblePurchases();
      await repo.loadDraftLines(invoiceId);

      expect((await db.select(db.supplierReturns).get()).length, returnsBefore);
      expect(await db.stockDao.getStock(productId), stockBefore);
      expect(
          await db.supplierAccountsDao.getBalance(supplierId), balanceBefore);
    });
  });

  group('SupplierReturnDraftNotifier', () {
    late AppDatabase db;
    late ProviderContainer container;
    late int supplierId;
    late int productId;
    late int invoiceId;
    late int purchaseItemId;

    setUp(() async {
      db = AppDatabase.test();
      container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider
              .overrideWithValue(SupplierReturnReadRepository(db)),
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

    SupplierReturnPurchaseOption option() {
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

    test('G) quantity above available is rejected at UI/state level', () async {
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(option());
      notifier.setLineQuantity(purchaseItemId, 6);
      final state = container.read(supplierReturnDraftProvider);
      expect(state.lineErrors[purchaseItemId], isNotNull);
      expect(state.canProceed, isFalse);
    });

    test('H) changing purchase clears previous draft lines', () async {
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(option());
      notifier.setLineQuantity(purchaseItemId, 2);
      notifier.backToPurchaseSelection();
      final state = container.read(supplierReturnDraftProvider);
      expect(state.lines, isEmpty);
      expect(state.selectedPurchase, isNull);
      expect(state.step, SupplierReturnDraftStep.selectPurchase);
    });

    test('draft total is presentation-only sum', () async {
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(option());
      notifier.setLineQuantity(purchaseItemId, 2);
      final state = container.read(supplierReturnDraftProvider);
      expect(state.draftTotal, 10);
    });
  });

  group('SR.3.1 hardening — same productId isolation (R-06)', () {
    late AppDatabase db;
    late ProviderContainer container;
    late int supplierId;
    late int productId;
    late int invoiceId;
    late int purchaseItem101Id;
    late int purchaseItem102Id;

    setUp(() async {
      db = AppDatabase.test();
      container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider
              .overrideWithValue(SupplierReturnReadRepository(db)),
        ],
      );

      supplierId = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('Same Product Supplier')),
          );
      productId = await db.into(db.products).insert(
            const ProductsCompanion(name: Value('Shared Product')),
          );
      invoiceId = await db.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(supplierId),
          purchaseDate: Value(DateTime(2026, 5, 1)),
          total: const Value(75),
          invoiceNumber: const Value('PI-SAME'),
        ),
        items: [
          {'productId': productId, 'qty': 10.0, 'cost': 5.0},
          {'productId': productId, 'qty': 5.0, 'cost': 5.0},
        ],
      );
      final items = await db.purchasesDao.getItemsForInvoice(invoiceId);
      expect(items, hasLength(2));
      purchaseItem101Id = items[0].id;
      purchaseItem102Id = items[1].id;
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('line quantities keyed by purchaseItemId not productId', () async {
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(
        SupplierReturnPurchaseOption(
          purchaseInvoiceId: invoiceId,
          supplierId: supplierId,
          supplierName: 'Same Product Supplier',
          invoiceNumber: 'PI-SAME',
          purchaseDate: DateTime(2026, 5, 1),
          totalAmount: 75,
          status: 'CONFIRMED',
        ),
      );

      final state = container.read(supplierReturnDraftProvider);
      final line101 =
          state.lines.firstWhere((l) => l.purchaseItemId == purchaseItem101Id);
      final line102 =
          state.lines.firstWhere((l) => l.purchaseItemId == purchaseItem102Id);

      expect(line101.returnableQty, 10);
      expect(line102.returnableQty, 5);

      notifier.setLineQuantity(purchaseItem101Id, 3);
      final afterFirst = container.read(supplierReturnDraftProvider);
      final updated101 = afterFirst.lines
          .firstWhere((l) => l.purchaseItemId == purchaseItem101Id);
      final updated102 = afterFirst.lines
          .firstWhere((l) => l.purchaseItemId == purchaseItem102Id);
      expect(updated101.selectedReturnQty, 3);
      expect(updated102.selectedReturnQty, 0);

      notifier.setLineQuantity(purchaseItem102Id, 2);
      final afterSecond = container.read(supplierReturnDraftProvider);
      expect(
        afterSecond.lines
            .firstWhere((l) => l.purchaseItemId == purchaseItem101Id)
            .selectedReturnQty,
        3,
      );
      expect(
        afterSecond.lines
            .firstWhere((l) => l.purchaseItemId == purchaseItem102Id)
            .selectedReturnQty,
        2,
      );
    });
  });

  group('SR.3.1 hardening — async race (R-04/R-05/R-07)', () {
    late ProviderContainer container;
    late _ControllableReadRepository controllableRepo;
    late SupplierReturnPurchaseOption purchaseA;
    late SupplierReturnPurchaseOption purchaseB;
    late List<SupplierReturnDraftLine> linesA;
    late List<SupplierReturnDraftLine> linesB;

    setUp(() {
      controllableRepo = _ControllableReadRepository();
      container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider
              .overrideWithValue(controllableRepo),
        ],
      );

      purchaseA = SupplierReturnPurchaseOption(
        purchaseInvoiceId: 1,
        supplierId: 10,
        supplierName: 'Supplier A',
        invoiceNumber: 'A-001',
        purchaseDate: DateTime(2026, 1, 1),
        totalAmount: 100,
        status: 'CONFIRMED',
      );
      purchaseB = SupplierReturnPurchaseOption(
        purchaseInvoiceId: 2,
        supplierId: 20,
        supplierName: 'Supplier B',
        invoiceNumber: 'B-002',
        purchaseDate: DateTime(2026, 2, 1),
        totalAmount: 200,
        status: 'CONFIRMED',
      );

      linesA = [
        const SupplierReturnDraftLine(
          purchaseItemId: 101,
          productId: 1,
          productName: 'Item A',
          purchasedQty: 10,
          alreadyReturnedQty: 0,
          returnableQty: 10,
          unitCost: 5,
        ),
      ];
      linesB = [
        const SupplierReturnDraftLine(
          purchaseItemId: 201,
          productId: 2,
          productName: 'Item B',
          purchasedQty: 8,
          alreadyReturnedQty: 0,
          returnableQty: 8,
          unitCost: 7,
        ),
      ];
    });

    tearDown(() {
      container.dispose();
    });

    test('B wins when A completes after B', () async {
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      final loadA = controllableRepo.enqueueLoad(1);
      final loadB = controllableRepo.enqueueLoad(2);

      final futureA = notifier.selectPurchase(purchaseA);
      final futureB = notifier.selectPurchase(purchaseB);

      loadB.complete(linesB);
      await futureB;
      var state = container.read(supplierReturnDraftProvider);
      expect(state.selectedPurchase?.purchaseInvoiceId, 2);
      expect(state.lines.single.purchaseItemId, 201);
      expect(state.loadingLines, isFalse);

      loadA.complete(linesA);
      await futureA;
      state = container.read(supplierReturnDraftProvider);
      expect(state.selectedPurchase?.purchaseInvoiceId, 2);
      expect(state.lines.single.purchaseItemId, 201);
      expect(state.loadingLines, isFalse);
    });

    test('backToPurchaseSelection ignores late A completion', () async {
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      final loadA = controllableRepo.enqueueLoad(1);

      final futureA = notifier.selectPurchase(purchaseA);
      notifier.backToPurchaseSelection();

      loadA.complete(linesA);
      await futureA;

      final state = container.read(supplierReturnDraftProvider);
      expect(state.step, SupplierReturnDraftStep.selectPurchase);
      expect(state.selectedPurchase, isNull);
      expect(state.lines, isEmpty);
      expect(state.loadingLines, isFalse);
    });

    test('stale A error does not overwrite active B selection', () async {
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      final loadA = controllableRepo.enqueueLoad(1);
      final loadB = controllableRepo.enqueueLoad(2);

      final futureA = notifier.selectPurchase(purchaseA);
      final futureB = notifier.selectPurchase(purchaseB);

      loadB.complete(linesB);
      await futureB;

      loadA.completeError(Exception('stale failure'));
      await futureA;

      final state = container.read(supplierReturnDraftProvider);
      expect(state.selectedPurchase?.purchaseInvoiceId, 2);
      expect(state.lines.single.purchaseItemId, 201);
      expect(state.errorMessage, isNull);
    });
  });

  group('validateDraftLineQuantity', () {
    const line = SupplierReturnDraftLine(
      purchaseItemId: 1,
      productId: 1,
      productName: 'X',
      purchasedQty: 10,
      alreadyReturnedQty: 2,
      returnableQty: 8,
      unitCost: 5,
    );

    test('accepts zero and valid quantities', () {
      expect(validateDraftLineQuantity(line, 0), isNull);
      expect(validateDraftLineQuantity(line, 8), isNull);
    });

    test('rejects excessive quantity', () {
      expect(validateDraftLineQuantity(line, 9), isNotNull);
    });
  });

  group('Create Supplier Return UI', () {
    testWidgets('A) + مرتجع مورد opens dialog not placeholder snackbar',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supplierReturnReadRepositoryProvider.overrideWithValue(
              _NoOpSupplierReturnReadRepository(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: SupplierReturnsScreen()),
            ),
          ),
        ),
      );

      await tester.tap(find.text('مرتجع مورد'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('مرتجعات الموردين سيتم إضافتها قريباً'), findsNothing);
      expect(find.byType(CreateSupplierReturnDialog), findsOneWidget);
      expect(find.text('اختيار فاتورة الشراء'), findsOneWidget);
    });

    testWidgets('R-01 rapid taps open only one dialog', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supplierReturnReadRepositoryProvider.overrideWithValue(
              _NoOpSupplierReturnReadRepository(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: SupplierReturnsScreen()),
            ),
          ),
        ),
      );

      final button = find.text('مرتجع مورد');
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CreateSupplierReturnDialog), findsOneWidget);
    });

    testWidgets('R-08 barrier dismiss resets draft on reopen', (tester) async {
      late ProviderContainer container;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              supplierReturnReadRepositoryProvider.overrideWithValue(
                _StatefulReadRepository(),
              ),
            ],
          ),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const _DialogTestHost(),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('فاتورة PI-OPEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final notifier = container.read(supplierReturnDraftProvider.notifier);
      final loaded = container.read(supplierReturnDraftProvider);
      expect(loaded.lines, isNotEmpty);
      notifier.setLineQuantity(loaded.lines.first.purchaseItemId, 2);
      expect(
          container.read(supplierReturnDraftProvider).hasSelectedQty, isTrue);

      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(container.read(supplierReturnDraftProvider).lines, isEmpty);
      expect(
          container.read(supplierReturnDraftProvider).selectedPurchase, isNull);

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final reopened = container.read(supplierReturnDraftProvider);
      expect(reopened.lines, isEmpty);
      expect(reopened.selectedPurchase, isNull);
      expect(reopened.hasSelectedQty, isFalse);
    });
  });
}

class _DialogTestHost extends ConsumerWidget {
  const _DialogTestHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: ElevatedButton(
          onPressed: () => showCreateSupplierReturnDialog(context, ref),
          child: const Text('open'),
        ),
      ),
    );
  }
}

class _NoOpSupplierReturnReadRepository extends SupplierReturnReadRepository {
  _NoOpSupplierReturnReadRepository() : super(AppDatabase.test());

  @override
  Future<List<SupplierReturnPurchaseOption>> getEligiblePurchases() async =>
      const [];

  @override
  Future<List<SupplierReturnDraftLine>> loadDraftLines(
          int purchaseInvoiceId) async =>
      const [];
}

class _StatefulReadRepository extends SupplierReturnReadRepository {
  _StatefulReadRepository() : super(AppDatabase.test());

  @override
  Future<List<SupplierReturnPurchaseOption>> getEligiblePurchases() async {
    return [
      SupplierReturnPurchaseOption(
        purchaseInvoiceId: 99,
        supplierId: 1,
        supplierName: 'Open Supplier',
        invoiceNumber: 'PI-OPEN',
        purchaseDate: DateTime(2026, 6, 1),
        totalAmount: 40,
        status: 'CONFIRMED',
      ),
    ];
  }

  @override
  Future<List<SupplierReturnDraftLine>> loadDraftLines(int invoiceId) async {
    return [
      const SupplierReturnDraftLine(
        purchaseItemId: 501,
        productId: 1,
        productName: 'Open Item',
        purchasedQty: 4,
        alreadyReturnedQty: 0,
        returnableQty: 4,
        unitCost: 10,
      ),
    ];
  }
}

class _ControllableReadRepository extends SupplierReturnReadRepository {
  _ControllableReadRepository() : super(AppDatabase.test());

  final Map<int, Completer<List<SupplierReturnDraftLine>>> _pending = {};

  _LoadHandle enqueueLoad(int invoiceId) {
    final completer = Completer<List<SupplierReturnDraftLine>>();
    _pending[invoiceId] = completer;
    return _LoadHandle(completer);
  }

  @override
  Future<List<SupplierReturnPurchaseOption>> getEligiblePurchases() async =>
      const [];

  @override
  Future<List<SupplierReturnDraftLine>> loadDraftLines(int invoiceId) async {
    final pending = _pending.remove(invoiceId);
    if (pending == null) {
      throw StateError('No pending load for invoice $invoiceId');
    }
    return pending.future;
  }
}

class _LoadHandle {
  _LoadHandle(this._completer);

  final Completer<List<SupplierReturnDraftLine>> _completer;

  void complete(List<SupplierReturnDraftLine> lines) {
    if (!_completer.isCompleted) _completer.complete(lines);
  }

  void completeError(Object error) {
    if (!_completer.isCompleted) _completer.completeError(error);
  }
}
