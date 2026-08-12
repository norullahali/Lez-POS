import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/supplier_account_service.dart';
import 'package:lez_pos/core/services/supplier_refund_settlement_service.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';
import 'package:lez_pos/features/returns/providers/supplier_refund_settlement_provider.dart';
import 'package:lez_pos/features/suppliers/providers/supplier_accounts_provider.dart';
import 'package:lez_pos/features/returns/providers/supplier_return_service_provider.dart';
import 'package:lez_pos/features/returns/utils/supplier_refund_settlement_messages.dart';

void main() {
  group('SR.3.3 Step 3.1 supplier refund UI foundation', () {
    late AppDatabase db;
    late int supplierId;
    late int productId;
    late int invoiceId;
    late int purchaseItemId;

    Future<void> seedCredit({double credit = 20}) async {
      await SupplierAccountService(db).processPayment(
        supplierId: supplierId,
        amount: 50,
      );
      await SupplierReturnService(db).postPurchaseLinkedReturn(
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
            const SuppliersCompanion(name: Value('UI Supplier')),
          );
      productId = await db.into(db.products).insert(
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
    });

    tearDown(() async => db.close());

    ProviderContainer containerWithService(
      SupplierRefundSettlementService service,
    ) {
      return ProviderContainer(
        overrides: [
          supplierRefundSettlementServiceProvider.overrideWithValue(service),
        ],
      );
    }

    test('A) refund action available when credit > 0', () async {
      await seedCredit(credit: 15);
      final container = ProviderContainer(
        overrides: [
          supplierAccountsDaoProvider.overrideWithValue(db.supplierAccountsDao),
        ],
      );
      addTearDown(container.dispose);
      final credit = await container
          .read(supplierAvailableCreditProvider(supplierId).future);
      expect(credit, closeTo(15, 0.001));
      container.read(supplierRefundSettlementProvider.notifier).init(
            supplierId: supplierId,
            supplierName: 'UI Supplier',
            availableCredit: credit,
          );
      expect(
        container.read(supplierRefundSettlementProvider)!.hasAvailableCredit,
        isTrue,
      );
    });

    test('B) refund action unavailable when credit = 0', () async {
      final container = ProviderContainer(
        overrides: [
          supplierAccountsDaoProvider.overrideWithValue(db.supplierAccountsDao),
        ],
      );
      addTearDown(container.dispose);
      final credit = await container
          .read(supplierAvailableCreditProvider(supplierId).future);
      expect(credit, 0);
      container.read(supplierRefundSettlementProvider.notifier).init(
            supplierId: supplierId,
            supplierName: 'UI Supplier',
            availableCredit: credit,
          );
      expect(
        container.read(supplierRefundSettlementProvider)!.hasAvailableCredit,
        isFalse,
      );
    });

    test('C) amount 0 rejected by UI validation', () {
      expect(validateRefundAmountText('0', 20), isNotNull);
      expect(validateRefundAmountText('0.0', 20), isNotNull);
    });

    test('D) negative amount rejected', () {
      expect(validateRefundAmountText('-5', 20), isNotNull);
    });

    test('E) amount greater than displayed credit rejected', () {
      expect(validateRefundAmountText('25', 20), isNotNull);
      expect(validateRefundAmountText('20.0002', 20), isNotNull);
    });

    test('F) valid amount reaches the canonical settlement service', () async {
      await seedCredit(credit: 20);
      var callCount = 0;
      double? capturedAmount;
      final service = SupplierRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int supplierId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          callCount++;
          capturedAmount = amount;
          await db.supplierAccountsDao.recordRefundInTransaction(
            supplierId: supplierId,
            amount: amount,
            returnId: returnId,
            note: note ?? '',
          );
        },
      );
      final container = containerWithService(service);
      addTearDown(container.dispose);
      final notifier =
          container.read(supplierRefundSettlementProvider.notifier);
      notifier.init(
        supplierId: supplierId,
        supplierName: 'UI Supplier',
        availableCredit: 20,
      );
      notifier.setAmountText('12.5');
      expect(await notifier.submit(), isTrue);
      expect(callCount, 1);
      expect(capturedAmount, closeTo(12.5, 0.001));
    });

    test('G) double submit triggers only one service call', () async {
      await seedCredit(credit: 20);
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
          await db.supplierAccountsDao.recordRefundInTransaction(
            supplierId: supplierId,
            amount: amount,
            returnId: returnId,
            note: note ?? '',
          );
        },
      );
      final container = containerWithService(service);
      addTearDown(container.dispose);
      final notifier =
          container.read(supplierRefundSettlementProvider.notifier);
      notifier.init(
        supplierId: supplierId,
        supplierName: 'UI Supplier',
        availableCredit: 20,
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

    test('H) business failure preserves dialog draft', () async {
      await seedCredit(credit: 20);
      final service = SupplierRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int supplierId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          throw const SupplierRefundSettlementException(
            SupplierRefundSettlementFailure.amountExceedsCredit,
            'settlement exceeds available credit',
          );
        },
      );
      final container = containerWithService(service);
      addTearDown(container.dispose);
      final notifier =
          container.read(supplierRefundSettlementProvider.notifier);
      notifier.init(
        supplierId: supplierId,
        supplierName: 'UI Supplier',
        availableCredit: 20,
      );
      notifier.setAmountText('10');
      notifier.setNote('draft note');
      expect(await notifier.submit(), isFalse);
      final state = container.read(supplierRefundSettlementProvider)!;
      expect(state.amountText, '10');
      expect(state.note, 'draft note');
      expect(state.errorMessage, isNotNull);
    });

    test('I) Arabic failure mapping exposes no raw exception text', () {
      for (final code in SupplierRefundSettlementFailure.values) {
        final message = supplierRefundSettlementFailureMessage(code);
        expect(message, isNot(contains('Exception')));
        expect(message, isNot(contains('failed')));
        expect(message, isNot(contains('supplier')));
      }
      expect(
        supplierRefundSettlementFailureMessage(
          SupplierRefundSettlementFailure.noSupplierCredit,
        ),
        'لا يوجد رصيد دائن متاح لهذا المورد',
      );
    });

    test('J) success refreshes relevant state', () async {
      await seedCredit(credit: 20);
      final service = SupplierRefundSettlementService(db);
      final container = containerWithService(service);
      addTearDown(container.dispose);
      final beforeTick = container.read(supplierReturnsRefreshProvider);
      final notifier =
          container.read(supplierRefundSettlementProvider.notifier);
      notifier.init(
        supplierId: supplierId,
        supplierName: 'UI Supplier',
        availableCredit: 20,
      );
      notifier.setAmountText('5');
      expect(await notifier.submit(), isTrue);
      expect(container.read(supplierReturnsRefreshProvider), beforeTick + 1);
      expect(
        container.read(supplierRefundSettlementProvider)!.status,
        SupplierRefundSettlementUiStatus.success,
      );
    });

    test('K) UI settlement path uses service only', () async {
      await seedCredit(credit: 20);
      var serviceCalls = 0;
      final service = SupplierRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int supplierId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          serviceCalls++;
          await db.supplierAccountsDao.recordRefundInTransaction(
            supplierId: supplierId,
            amount: amount,
            returnId: returnId,
            note: note ?? '',
          );
        },
      );
      final container = containerWithService(service);
      addTearDown(container.dispose);
      final beforeRefunds = (await (db.select(db.supplierTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      final notifier =
          container.read(supplierRefundSettlementProvider.notifier);
      notifier.init(
        supplierId: supplierId,
        supplierName: 'UI Supplier',
        availableCredit: 20,
      );
      notifier.setAmountText('7');
      expect(await notifier.submit(), isTrue);
      expect(serviceCalls, 1);
      final afterRefunds = (await (db.select(db.supplierTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      expect(afterRefunds, beforeRefunds + 1);
    });

    test('L) optional returnId is passed correctly when linked', () async {
      await seedCredit(credit: 20);
      int? capturedReturnId;
      final returnId = await SupplierReturnService(db).postPurchaseLinkedReturn(
        SupplierReturnPostingInput(
          supplierId: supplierId,
          purchaseInvoiceId: invoiceId,
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItemId,
              quantity: 1,
            ),
          ],
        ),
      );
      final service = SupplierRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int supplierId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          capturedReturnId = returnId;
          await db.supplierAccountsDao.recordRefundInTransaction(
            supplierId: supplierId,
            amount: amount,
            returnId: returnId,
            note: note ?? '',
          );
        },
      );
      final container = containerWithService(service);
      addTearDown(container.dispose);
      final notifier =
          container.read(supplierRefundSettlementProvider.notifier);
      notifier.init(
        supplierId: supplierId,
        supplierName: 'UI Supplier',
        availableCredit: 20,
        returnId: returnId,
        returnLabel: 'SR-LINK',
      );
      notifier.setAmountText('5');
      expect(await notifier.submit(), isTrue);
      expect(capturedReturnId, returnId);
    });

    test('opening dialog state does not write financial rows', () async {
      await seedCredit(credit: 20);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final beforeRefunds = (await (db.select(db.supplierTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      container.read(supplierRefundSettlementProvider.notifier).init(
            supplierId: supplierId,
            supplierName: 'UI Supplier',
            availableCredit: 20,
          );
      container
          .read(supplierRefundSettlementProvider.notifier)
          .setAmountText('9');
      container.read(supplierRefundSettlementProvider.notifier).setNote('note');
      final afterRefunds = (await (db.select(db.supplierTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      expect(afterRefunds, beforeRefunds);
    });
  });
}
