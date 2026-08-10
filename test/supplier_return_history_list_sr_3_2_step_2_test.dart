import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';
import 'package:lez_pos/features/returns/models/supplier_return_draft_models.dart';
import 'package:lez_pos/features/returns/models/supplier_return_history_models.dart';
import 'package:lez_pos/features/returns/providers/supplier_return_draft_provider.dart';
import 'package:lez_pos/features/returns/providers/supplier_return_service_provider.dart';
import 'package:lez_pos/features/returns/providers/supplier_returns_list_provider.dart';
import 'package:lez_pos/features/returns/repositories/supplier_return_read_repository.dart';

void main() {
  group('SR.3.2 Step 2 supplier returns history/list', () {
    late AppDatabase db;
    late SupplierReturnService service;
    late SupplierReturnReadRepository repo;
    late ProviderContainer container;
    late int supplierId;
    late int productId;
    late int invoiceId;
    late int purchaseItemId;

    Future<int> postReturn({double quantity = 2}) {
      return service.postPurchaseLinkedReturn(
        SupplierReturnPostingInput(
          supplierId: supplierId,
          purchaseInvoiceId: invoiceId,
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItemId,
              quantity: quantity,
            ),
          ],
        ),
      );
    }

    setUp(() async {
      db = AppDatabase.test();
      service = SupplierReturnService(db);
      repo = SupplierReturnReadRepository(db);
      container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider.overrideWithValue(repo),
          supplierReturnServiceProvider.overrideWithValue(service),
        ],
      );
      supplierId = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('Alpha Supplier')),
          );
      productId = await db.into(db.products).insert(
            const ProductsCompanion(name: Value('Part A')),
          );
      invoiceId = await db.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(supplierId),
          purchaseDate: Value(DateTime(2026, 5, 1)),
          total: const Value(100),
          invoiceNumber: const Value('PI-HIST-100'),
        ),
        items: [
          {'productId': productId, 'qty': 10.0, 'cost': 5.0},
        ],
      );
      purchaseItemId =
          (await db.purchasesDao.getItemsForInvoice(invoiceId)).single.id;
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('A) empty list', () async {
      expect(await repo.listSupplierReturns(), isEmpty);
      expect(await container.read(supplierReturnsListProvider.future), isEmpty);
    });

    test('B) one persisted supplier return appears', () async {
      await postReturn();
      final rows = await repo.listSupplierReturns();
      expect(rows, hasLength(1));
      expect(rows.single.lineCount, 1);
    });

    test('C) multiple returns appear correctly', () async {
      await postReturn(quantity: 1);
      await postReturn(quantity: 2);
      expect(await repo.listSupplierReturns(), hasLength(2));
    });

    test('D) supplier information is correct', () async {
      await postReturn();
      final row = (await repo.listSupplierReturns()).single;
      expect(row.supplierId, supplierId);
      expect(row.supplierName, 'Alpha Supplier');
    });

    test('E) purchase invoice reference is correct', () async {
      await postReturn();
      final row = (await repo.listSupplierReturns()).single;
      expect(row.purchaseInvoiceId, invoiceId);
      expect(row.purchaseInvoiceNumber, 'PI-HIST-100');
      expect(row.isPurchaseLinked, isTrue);
    });

    test('F) returned amount/value is correct', () async {
      await postReturn(quantity: 3);
      expect(
          (await repo.listSupplierReturns()).single.total, closeTo(15, 0.001));
    });

    test('G) refresh after successful posting reloads list', () async {
      expect(await container.read(supplierReturnsListProvider.future), isEmpty);
      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(
        SupplierReturnPurchaseOption(
          purchaseInvoiceId: invoiceId,
          supplierId: supplierId,
          supplierName: 'Alpha Supplier',
          invoiceNumber: 'PI-HIST-100',
          purchaseDate: DateTime(2026, 5, 1),
          totalAmount: 100,
          status: 'CONFIRMED',
        ),
      );
      notifier.setLineQuantity(purchaseItemId, 2);
      expect(await notifier.submitReturn(), isTrue);
      expect(await container.read(supplierReturnsListProvider.future),
          hasLength(1));
      expect(container.read(supplierReturnsRefreshProvider), 1);
    });

    test('H) failed posting does not refresh list', () async {
      final failContainer = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider.overrideWithValue(repo),
          supplierReturnServiceProvider.overrideWithValue(_FailingService(db)),
        ],
      );
      addTearDown(failContainer.dispose);
      final beforeTick = failContainer.read(supplierReturnsRefreshProvider);
      final notifier = failContainer.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(
        SupplierReturnPurchaseOption(
          purchaseInvoiceId: invoiceId,
          supplierId: supplierId,
          supplierName: 'Alpha Supplier',
          invoiceNumber: 'PI-HIST-100',
          purchaseDate: DateTime(2026, 5, 1),
          totalAmount: 100,
          status: 'CONFIRMED',
        ),
      );
      notifier.setLineQuantity(purchaseItemId, 2);
      expect(await notifier.submitReturn(), isFalse);
      expect(failContainer.read(supplierReturnsRefreshProvider), beforeTick);
      expect(await failContainer.read(supplierReturnsListProvider.future),
          isEmpty);
    });

    test('I) loading state', () async {
      final slow = _SlowListRepository();
      final slowContainer = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider.overrideWithValue(slow),
        ],
      );
      addTearDown(slowContainer.dispose);
      final sub = slowContainer.listen(supplierReturnsListProvider, (_, __) {});
      expect(sub.read(), isA<AsyncLoading<List<SupplierReturnListItem>>>());
      slow.completeRows([]);
      await Future<void>.delayed(Duration.zero);
      expect(sub.read(), isA<AsyncData<List<SupplierReturnListItem>>>());
      sub.close();
    });

    test('J) error state/retry via invalidate', () async {
      final throwing = _ThrowingListRepository();
      final errContainer = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider.overrideWithValue(throwing),
        ],
      );
      addTearDown(errContainer.dispose);
      final sub = errContainer.listen(supplierReturnsListProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(sub.read(), isA<AsyncError<List<SupplierReturnListItem>>>());
      throwing.shouldThrow = false;
      errContainer.invalidate(supplierReturnsListProvider);
      expect(
          await errContainer.read(supplierReturnsListProvider.future), isEmpty);
      sub.close();
    });

    test('K) detail view returns persisted lines', () async {
      await postReturn(quantity: 2);
      final id = (await repo.listSupplierReturns()).single.id;
      final detail = await repo.getSupplierReturnDetail(id);
      expect(detail, isNotNull);
      expect(detail!.lines, hasLength(1));
      expect(detail.lines.single.productName, 'Part A');
      expect(detail.lines.single.quantity, 2);
      expect(detail.total, closeTo(10, 0.001));
    });

    test('L) no write side effects from list/history', () async {
      await postReturn();
      final before = await db.returnsDao.getAllSupplierReturns();
      await repo.listSupplierReturns();
      await repo.getSupplierReturnDetail(before.single.id);
      await container.read(supplierReturnsListProvider.future);
      final after = await db.returnsDao.getAllSupplierReturns();
      expect(after.length, before.length);
      expect(after.single.total, before.single.total);
    });
  });
}

class _FailingService extends SupplierReturnService {
  _FailingService(super.db);
  @override
  Future<int> postPurchaseLinkedReturn(SupplierReturnPostingInput input) async {
    throw const SupplierReturnPostingException(
      SupplierReturnPostingFailure.stockInsufficient,
      'fail',
    );
  }
}

class _SlowListRepository extends SupplierReturnReadRepository {
  _SlowListRepository() : super(AppDatabase.test());
  final _completer = Completer<List<SupplierReturnListItem>>();
  void completeRows(List<SupplierReturnListItem> rows) {
    if (!_completer.isCompleted) _completer.complete(rows);
  }

  @override
  Future<List<SupplierReturnListItem>> listSupplierReturns({int limit = 100}) =>
      _completer.future;
}

class _ThrowingListRepository extends SupplierReturnReadRepository {
  _ThrowingListRepository() : super(AppDatabase.test());
  bool shouldThrow = true;
  @override
  Future<List<SupplierReturnListItem>> listSupplierReturns({int limit = 100}) {
    if (shouldThrow) throw StateError('list failed');
    return Future.value(const []);
  }
}
