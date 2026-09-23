import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_refund_settlement_service.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';
import 'package:lez_pos/features/customers/providers/customer_accounts_provider.dart';
import 'package:lez_pos/features/customers/providers/customer_refund_settlement_provider.dart';
import 'package:lez_pos/features/customers/screens/widgets/customer_credit_refund_entry.dart';
import 'package:lez_pos/features/customers/screens/widgets/customer_refund_settlement_dialog.dart';
import 'package:lez_pos/features/customers/utils/customer_refund_settlement_messages.dart';
import 'package:lez_pos/features/returns/models/customer_return_history_models.dart';
import 'package:lez_pos/features/returns/providers/customer_return_detail_provider.dart';
import 'package:lez_pos/features/returns/repositories/customer_return_read_repository.dart';

void main() {
  group('Phase C Step 2.7C remaining refundable UI/provider', () {
    late AppDatabase db;
    late int customerId;
    late int productId;
    late int invoiceId;
    late CustomerReturnReadRepository readRepo;

    Future<void> seedCredit({double credit = 20}) async {
      invoiceId = await db.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber: Value('RR-${DateTime.now().microsecondsSinceEpoch}'),
          subtotal: const Value(50),
          total: const Value(50),
          debtAmount: const Value(50),
          customerId: Value(customerId),
          paymentMethod: const Value('DEBT'),
        ),
        items: [
          {'productId': productId, 'qty': 10.0, 'price': 5.0, 'cost': 5.0},
        ],
      );
      await db.customerAccountsDao.recordSale(
        customerId: customerId,
        amount: 50,
        invoiceId: invoiceId,
        note: 'test sale',
      );
      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 50 + credit,
        note: 'overpayment',
      );
    }

    Future<int> seedLinkedReturn({double returnTotal = 50}) async {
      await seedCredit();
      final saleItemId =
          (await db.salesDao.getItemsForInvoice(invoiceId)).single.id;
      await PartialReturnService(db).processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: 1,
        lines: [
          PartialReturnLine(
            saleItemId: saleItemId,
            productId: productId,
            quantity: returnTotal / 5,
            unitPrice: 5,
            unitCost: 5,
          ),
        ],
      );
      return (await db.select(db.customerReturns).get()).last.id;
    }

    Future<int> seedCashLinkedReturn() async {
      invoiceId = await db.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber:
              Value('CASH-RR-${DateTime.now().microsecondsSinceEpoch}'),
          subtotal: const Value(20),
          total: const Value(20),
          debtAmount: const Value(0),
          customerId: Value(customerId),
          paymentMethod: const Value('CASH'),
        ),
        items: [
          {'productId': productId, 'qty': 2.0, 'price': 10.0, 'cost': 5.0},
        ],
      );
      final saleItemId =
          (await db.salesDao.getItemsForInvoice(invoiceId)).single.id;
      await PartialReturnService(db).processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: 1,
        lines: [
          PartialReturnLine(
            saleItemId: saleItemId,
            productId: productId,
            quantity: 1,
            unitPrice: 10,
            unitCost: 5,
          ),
        ],
      );
      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 100,
        note: 'unrelated aggregate credit',
      );
      return (await db.select(db.customerReturns).get()).last.id;
    }

    Future<int> seedUnlinkedReturn() async {
      return db.into(db.customerReturns).insert(
            CustomerReturnsCompanion(
              returnNumber:
                  Value('RET-UNLINK-${DateTime.now().microsecondsSinceEpoch}'),
              total: const Value(10),
              reason: const Value('manual return'),
            ),
          );
    }

    setUp(() async {
      db = AppDatabase.test();
      readRepo = CustomerReturnReadRepository(db);
      customerId = await db.into(db.customers).insert(
            const CustomersCompanion(name: Value('Remaining Customer')),
          );
      productId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('RR Product'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
          );
    });

    tearDown(() async => db.close());

    ProviderContainer containerWithRepo({CustomerReturnReadRepository? repo}) {
      return ProviderContainer(
        overrides: [
          customerReturnReadRepositoryProvider
              .overrideWithValue(repo ?? readRepo),
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        ],
      );
    }

    ProviderContainer containerWithService(
      CustomerRefundSettlementService service,
    ) {
      return ProviderContainer(
        overrides: [
          customerRefundSettlementServiceProvider.overrideWithValue(service),
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
          customerReturnReadRepositoryProvider.overrideWithValue(readRepo),
        ],
      );
    }

    Finder refundButtonFinder() => find.widgetWithText(
        ElevatedButton, CustomerCreditRefundEntry.refundButtonLabel);

    Future<void> pumpLinkedEntry(
      WidgetTester tester, {
      required int returnId,
      required ReturnRefundableSnapshot snapshot,
      double credit = 20,
      CustomerReturnReadRepository? repoOverride,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerReturnReadRepositoryProvider
                .overrideWithValue(repoOverride ?? readRepo),
            customerAccountsDaoProvider
                .overrideWithValue(db.customerAccountsDao),
            customerAvailableCreditProvider(customerId)
                .overrideWith((ref) async => credit),
            customerReturnRemainingRefundableProvider(returnId)
                .overrideWith((ref) async => snapshot),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: CustomerCreditRefundEntry(
                  customerId: customerId,
                  customerName: 'Remaining Customer',
                  returnId: returnId,
                  returnLabel: 'RET-LINK',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pumpUntilFound(
      WidgetTester tester,
      Finder finder, {
      int maxAttempts = 30,
    }) async {
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (tester.any(finder)) {
          return;
        }
      }
      fail('Timed out waiting for $finder');
    }

    testWidgets('A) linked return displays remaining amount', (tester) async {
      late int returnId;
      late ReturnRefundableSnapshot snapshot;
      await tester.runAsync(() async {
        returnId = await seedLinkedReturn();
        snapshot = (await readRepo.getReturnRefundableSnapshot(returnId))!;
      });

      await pumpLinkedEntry(
        tester,
        returnId: returnId,
        snapshot: snapshot,
      );
      expect(
        find.textContaining(
          CustomerCreditRefundEntry.aggregateCreditLabelPrefix,
        ),
        findsOneWidget,
      );
      expect(refundButtonFinder(), findsOneWidget);
    });

    test('B) settled_amount reduces remaining amount', () async {
      final returnId = await seedLinkedReturn();
      final before = await readRepo.getReturnRefundableSnapshot(returnId);
      expect(before, isNotNull);
      expect(before!.remainingRefundable, greaterThan(0));

      await db.customStatement(
        'UPDATE customer_returns SET settled_amount = 20 WHERE id = ?',
        [returnId],
      );

      final after = await readRepo.getReturnRefundableSnapshot(returnId);
      expect(
        after!.remainingRefundable,
        closeTo(before.remainingRefundable - 20, 0.001),
      );
    });

    testWidgets('C) zero remaining displays 0 and disables submit/button',
        (tester) async {
      late int returnId;
      late ReturnRefundableSnapshot snapshot;
      await tester.runAsync(() async {
        returnId = await seedLinkedReturn();
        await db.customStatement(
          'UPDATE customer_returns SET settled_amount = 9999 WHERE id = ?',
          [returnId],
        );
        snapshot = (await readRepo.getReturnRefundableSnapshot(returnId))!;
      });

      await pumpLinkedEntry(
        tester,
        returnId: returnId,
        snapshot: snapshot,
      );
      expect(find.textContaining(': 0 '), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(refundButtonFinder()).onPressed,
        isNull,
      );

      final container = containerWithRepo();
      addTearDown(container.dispose);
      container.read(customerRefundSettlementProvider.notifier).init(
            customerId: customerId,
            customerName: 'Remaining Customer',
            availableCredit: 20,
            returnId: returnId,
            maxReturnRefundable: 0,
          );
      container
          .read(customerRefundSettlementProvider.notifier)
          .setAmountText('5');
      final state = container.read(customerRefundSettlementProvider);
      expect(state!.canSubmit, isFalse);
    });

    test('D) two return IDs remain independent', () async {
      final returnIdA = await seedLinkedReturn();
      final returnIdB = await seedLinkedReturn();
      expect(returnIdA, isNot(returnIdB));

      final container = containerWithRepo();
      addTearDown(container.dispose);
      final valueA = await container.read(
        customerReturnRemainingRefundableProvider(returnIdA).future,
      );
      final valueB = await container.read(
        customerReturnRemainingRefundableProvider(returnIdB).future,
      );
      expect(valueA!.returnId, returnIdA);
      expect(valueB!.returnId, returnIdB);
    });

    testWidgets('E) returnId null preserves existing UI', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerAvailableCreditProvider(customerId)
                .overrideWith((ref) async => 25),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: CustomerCreditRefundEntry(
                  customerId: customerId,
                  customerName: 'Remaining Customer',
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(
        find.textContaining(CustomerCreditRefundEntry.returnRemainingLabel),
        findsNothing,
      );
      expect(
        find.textContaining(
          CustomerCreditRefundEntry.aggregateCreditLabelPrefix,
        ),
        findsOneWidget,
      );
    });

    testWidgets('F) aggregate customer credit remains visible', (tester) async {
      late int returnId;
      late ReturnRefundableSnapshot snapshot;
      await tester.runAsync(() async {
        returnId = await seedLinkedReturn();
        snapshot = (await readRepo.getReturnRefundableSnapshot(returnId))!;
      });

      await pumpLinkedEntry(
        tester,
        returnId: returnId,
        snapshot: snapshot,
      );
      expect(
        find.textContaining(
          CustomerCreditRefundEntry.aggregateCreditLabelPrefix,
        ),
        findsOneWidget,
      );
    });

    test('G) successful refund invalidates remaining amount', () async {
      final returnId = await seedLinkedReturn();
      final service = CustomerRefundSettlementService(db);
      final container = containerWithService(service);
      addTearDown(container.dispose);

      final before = await container.read(
        customerReturnRemainingRefundableProvider(returnId).future,
      );
      expect(before!.remainingRefundable, greaterThan(10));

      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Remaining Customer',
        availableCredit: 20,
        returnId: returnId,
        maxReturnRefundable: before.remainingRefundable,
      );
      notifier.setAmountText('10');
      expect(await notifier.submit(), isTrue);

      container.invalidate(customerAvailableCreditProvider(customerId));
      container.invalidate(customerReturnRemainingRefundableProvider(returnId));
      final after = await container.read(
        customerReturnRemainingRefundableProvider(returnId).future,
      );
      expect(
        after!.remainingRefundable,
        closeTo(before.remainingRefundable - 10, 0.001),
      );
    });

    testWidgets('H) cash invoice linked return displays zero and blocks refund',
        (tester) async {
      late int returnId;
      late ReturnRefundableSnapshot snapshot;
      await tester.runAsync(() async {
        returnId = await seedCashLinkedReturn();
        snapshot = (await readRepo.getReturnRefundableSnapshot(returnId))!;
      });

      await pumpLinkedEntry(
        tester,
        returnId: returnId,
        snapshot: snapshot,
      );
      expect(find.textContaining(': 0 '), findsOneWidget);
      expect(
        find.textContaining(
          CustomerCreditRefundEntry.aggregateCreditLabelPrefix,
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<ElevatedButton>(refundButtonFinder()).onPressed,
        isNull,
      );
    });

    test('I) historical settled_amount is respected', () async {
      final returnId = await seedLinkedReturn();
      await db.customStatement(
        'UPDATE customer_returns SET settled_amount = 15 WHERE id = ?',
        [returnId],
      );
      final snapshot = await readRepo.getReturnRefundableSnapshot(returnId);
      expect(snapshot!.settledAmount, 15);
      expect(
        snapshot.remainingRefundable,
        closeTo(snapshot.creditCap - 15, 0.001),
      );
    });

    testWidgets('J) provider error does not display false zero',
        (tester) async {
      late int returnId;
      await tester.runAsync(() async {
        returnId = await seedLinkedReturn();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerReturnReadRepositoryProvider.overrideWithValue(readRepo),
            customerAccountsDaoProvider
                .overrideWithValue(db.customerAccountsDao),
            customerAvailableCreditProvider(customerId)
                .overrideWith((ref) async => 20),
            customerReturnRemainingRefundableProvider(returnId).overrideWith(
              (ref) async => throw StateError('forced snapshot failure'),
            ),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: CustomerCreditRefundEntry(
                  customerId: customerId,
                  customerName: 'Remaining Customer',
                  returnId: returnId,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.textContaining(': 0 '), findsNothing);
      expect(
        tester.widget<ElevatedButton>(refundButtonFinder()).onPressed,
        isNull,
      );
    });

    test('K) amount above return remaining is blocked client-side', () {
      expect(
        validateCustomerRefundAmountText(
          '25',
          100,
          maxReturnRefundable: 20,
        ),
        customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.amountExceedsReturnRefundableAmount,
        ),
      );
    });

    test('L) existing Arabic failure messages are reused', () {
      expect(
        validateCustomerRefundAmountText(
          '5',
          100,
          maxReturnRefundable: 0,
        ),
        customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.noReturnRefundableAmount,
        ),
      );
    });

    testWidgets('dialog shows return remaining row when linked',
        (tester) async {
      late int returnId;
      late ReturnRefundableSnapshot snapshot;
      await tester.runAsync(() async {
        returnId = await seedLinkedReturn();
        snapshot = (await readRepo.getReturnRefundableSnapshot(returnId))!;
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerReturnReadRepositoryProvider.overrideWithValue(readRepo),
            customerAccountsDaoProvider
                .overrideWithValue(db.customerAccountsDao),
            customerAvailableCreditProvider(customerId)
                .overrideWith((ref) async => 20),
            customerReturnRemainingRefundableProvider(returnId)
                .overrideWith((ref) async => snapshot),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Consumer(
                builder: (context, ref, _) {
                  return Scaffold(
                    body: ElevatedButton(
                      onPressed: () {
                        showCustomerRefundSettlementDialog(
                          context,
                          ref,
                          customerId: customerId,
                          customerName: 'Remaining Customer',
                          availableCredit: 20,
                          returnId: returnId,
                          returnLabel: 'RET-DLG',
                        );
                      },
                      child: const Text('open'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.textContaining(
          CustomerRefundSettlementDialog.returnRemainingLabel,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          CustomerRefundSettlementDialog.availableCreditLabel,
        ),
        findsOneWidget,
      );
    });
  });
}

class _ThrowingReturnReadRepository extends CustomerReturnReadRepository {
  _ThrowingReturnReadRepository(super.db);

  @override
  Future<ReturnRefundableSnapshot?> getReturnRefundableSnapshot(int returnId) {
    throw StateError('forced snapshot failure');
  }
}
