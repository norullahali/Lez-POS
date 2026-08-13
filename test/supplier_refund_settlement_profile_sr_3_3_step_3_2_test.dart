import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/supplier_account_service.dart';
import 'package:lez_pos/core/services/supplier_refund_settlement_service.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';
import 'package:lez_pos/features/returns/providers/supplier_refund_settlement_provider.dart';
import 'package:lez_pos/features/suppliers/providers/supplier_accounts_provider.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:lez_pos/features/returns/screens/widgets/supplier_credit_refund_entry.dart';
import 'package:lez_pos/features/returns/utils/supplier_refund_settlement_messages.dart';

void main() {
  group('SR.3.3 Step 3.2 supplier profile refund entry', () {
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
            const SuppliersCompanion(name: Value('Profile Supplier')),
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
          supplierAccountsDaoProvider.overrideWithValue(db.supplierAccountsDao),
        ],
      );
    }

    Finder refundButtonFinder() =>
        find.widgetWithText(ElevatedButton, 'استرداد من المورد');

    test('A) supplier profile shows available credit', () async {
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
    });

    testWidgets('B) refund button enabled when credit > 0', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supplierAvailableCreditProvider(supplierId)
                .overrideWith((ref) async => 30),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SupplierCreditRefundEntry(
                  supplierId: supplierId,
                  supplierName: 'Profile Supplier',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('رصيد المورد الدائن'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(refundButtonFinder()).onPressed,
          isNotNull);
    });

    testWidgets('C) refund button disabled when credit = 0', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supplierAvailableCreditProvider(supplierId)
                .overrideWith((ref) async => 0),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SupplierCreditRefundEntry(
                  supplierId: supplierId,
                  supplierName: 'Profile Supplier',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('لا يوجد رصيد دائن متاح لهذا المورد'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(refundButtonFinder()).onPressed,
          isNull);
    });

    test('D) opening refund dialog creates zero financial side effects',
        () async {
      await seedCredit(credit: 20);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final beforeRefunds = (await (db.select(db.supplierTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      container.read(supplierRefundSettlementProvider.notifier).init(
            supplierId: supplierId,
            supplierName: 'Profile Supplier',
            availableCredit: 20,
          );
      container
          .read(supplierRefundSettlementProvider.notifier)
          .setAmountText('9');
      final afterRefunds = (await (db.select(db.supplierTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      expect(afterRefunds, beforeRefunds);
    });

    test('E) profile entry calls the canonical settlement service', () async {
      await seedCredit(credit: 20);
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
        supplierName: 'Profile Supplier',
        availableCredit: 20,
      );
      notifier.setAmountText('12');
      expect(await notifier.submit(), isTrue);
      expect(callCount, 1);
    });

    test('F) valid refund succeeds', () async {
      await seedCredit(credit: 20);
      final container =
          containerWithService(SupplierRefundSettlementService(db));
      addTearDown(container.dispose);
      final notifier =
          container.read(supplierRefundSettlementProvider.notifier);
      notifier.init(
        supplierId: supplierId,
        supplierName: 'Profile Supplier',
        availableCredit: 20,
      );
      notifier.setAmountText('8');
      expect(await notifier.submit(), isTrue);
      expect(
        container.read(supplierRefundSettlementProvider)!.status,
        SupplierRefundSettlementUiStatus.success,
      );
    });

    test('G) successful refund refreshes supplier credit', () async {
      await seedCredit(credit: 50);
      final container =
          containerWithService(SupplierRefundSettlementService(db));
      addTearDown(container.dispose);
      final before = await container
          .read(supplierAvailableCreditProvider(supplierId).future);
      expect(before, closeTo(50, 0.001));
      final notifier =
          container.read(supplierRefundSettlementProvider.notifier);
      notifier.init(
        supplierId: supplierId,
        supplierName: 'Profile Supplier',
        availableCredit: before,
      );
      notifier.setAmountText('30');
      expect(await notifier.submit(), isTrue);
      container.invalidate(supplierAvailableCreditProvider(supplierId));
      final after = await container
          .read(supplierAvailableCreditProvider(supplierId).future);
      expect(after, closeTo(20, 0.001));
    });

    test('H) failed refund preserves dialog state', () async {
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
        supplierName: 'Profile Supplier',
        availableCredit: 20,
      );
      notifier.setAmountText('10');
      notifier.setNote('profile note');
      expect(await notifier.submit(), isFalse);
      final state = container.read(supplierRefundSettlementProvider)!;
      expect(state.amountText, '10');
      expect(state.note, 'profile note');
      expect(state.errorMessage, isNotNull);
    });

    test('J) double submit results in exactly one service call', () async {
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
        supplierName: 'Profile Supplier',
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

    test('I) Arabic failure message mapped correctly', () {
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

    test('K) no direct DAO financial write from UI', () async {
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
        supplierName: 'Profile Supplier',
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

    test('L) optional returnId remains null from supplier profile', () async {
      await seedCredit(credit: 20);
      int? capturedReturnId = -1;
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
        supplierName: 'Profile Supplier',
        availableCredit: 20,
      );
      notifier.setAmountText('5');
      expect(await notifier.submit(), isTrue);
      expect(capturedReturnId, isNull);
    });

    test('M) cash ledger is not directly written by UI path', () async {
      await seedCredit(credit: 20);
      const ledgerFilter = CashLedgerFilter(
        page: 0,
        pageSize: 1000,
        dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
      );
      final ledger = FinancialLedgerRepository(db);
      final before = (await ledger.getEntries(ledgerFilter))
          .entries
          .where((e) => e.eventType == CashLedgerEventType.supplierRefund)
          .length;
      final container =
          containerWithService(SupplierRefundSettlementService(db));
      addTearDown(container.dispose);
      final notifier =
          container.read(supplierRefundSettlementProvider.notifier);
      notifier.init(
        supplierId: supplierId,
        supplierName: 'Profile Supplier',
        availableCredit: 20,
      );
      notifier.setAmountText('6');
      expect(await notifier.submit(), isTrue);
      final after = (await ledger.getEntries(ledgerFilter))
          .entries
          .where((e) => e.eventType == CashLedgerEventType.supplierRefund)
          .length;
      expect(after, before + 1);
    });

    test('N) credit changing before submit is rejected by service', () async {
      await seedCredit(credit: 20);
      final container =
          containerWithService(SupplierRefundSettlementService(db));
      addTearDown(container.dispose);
      final notifier =
          container.read(supplierRefundSettlementProvider.notifier);
      notifier.init(
        supplierId: supplierId,
        supplierName: 'Profile Supplier',
        availableCredit: 20,
      );
      notifier.setAmountText('15');
      await db.supplierAccountsDao.recordRefundInTransaction(
        supplierId: supplierId,
        amount: 18,
        note: 'drain credit',
      );
      expect(await notifier.submit(), isFalse);
      final state = container.read(supplierRefundSettlementProvider)!;
      expect(state.errorMessage, isNotNull);
      expect(state.amountText, '15');
    });
  });
}
