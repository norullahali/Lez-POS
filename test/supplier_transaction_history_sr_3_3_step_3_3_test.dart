import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/supplier_refund_settlement_service.dart';
import 'package:lez_pos/core/theme/app_colors.dart';
import 'package:lez_pos/features/suppliers/providers/supplier_accounts_provider.dart';
import 'package:lez_pos/features/suppliers/screens/widgets/supplier_transactions_tab.dart';
import 'package:lez_pos/features/suppliers/utils/supplier_transaction_display.dart';

void main() {
  group('SR.3.3 Step 3.3 supplier transaction history display', () {
    final moneyFormat = NumberFormat('#,##0.##');
    final createdAt = DateTime(2026, 8, 13, 10, 30);

    SupplierTransaction sampleTx({
      required int id,
      required String type,
      required double amount,
      int? referenceId,
      String note = '',
    }) {
      return SupplierTransaction(
        id: id,
        supplierId: 1,
        type: type,
        referenceId: referenceId,
        amount: amount,
        createdAt: createdAt,
        note: note,
      );
    }

    Future<void> pumpListTile(
      WidgetTester tester, {
      required SupplierTransaction transaction,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SupplierTransactionListTile(
                transaction: transaction,
                moneyFormat: moneyFormat,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Color trailingAmountColor(WidgetTester tester) {
      final trailing = tester.widget<Text>(find.byType(Text).last);
      return trailing.style!.color!;
    }

    testWidgets('A) PURCHASE display', (tester) async {
      await pumpListTile(
        tester,
        transaction: sampleTx(id: 1, type: 'PURCHASE', amount: 120),
      );

      expect(find.byIcon(Icons.shopping_cart_rounded), findsOneWidget);
      expect(find.text('\u0634\u0631\u0627\u0621'), findsOneWidget);
      expect(find.textContaining('+120'), findsOneWidget);
      expect(trailingAmountColor(tester), AppColors.error);
      expect(
          find.textContaining(
              '\u0641\u0627\u062a\u0648\u0631\u0629 \u0645\u0634\u062a\u0631\u064a\u0627\u062a'),
          findsNothing);
    });

    testWidgets('B) PAYMENT display', (tester) async {
      await pumpListTile(
        tester,
        transaction: sampleTx(id: 2, type: 'PAYMENT', amount: -50),
      );

      expect(find.byIcon(Icons.payments_rounded), findsOneWidget);
      expect(
          find.text(
              '\u062f\u0641\u0639\u0629 \u0644\u0644\u0645\u0648\u0631\u062f'),
          findsOneWidget);
      expect(find.textContaining('-50'), findsOneWidget);
      expect(trailingAmountColor(tester), AppColors.success);
    });

    testWidgets('C) RETURN display', (tester) async {
      await pumpListTile(
        tester,
        transaction: sampleTx(
          id: 3,
          type: 'RETURN',
          amount: -20,
          referenceId: 99,
        ),
      );

      expect(find.byIcon(Icons.assignment_return_rounded), findsOneWidget);
      expect(
          find.text(
              '\u0645\u0631\u062a\u062c\u0639 \u0628\u0636\u0627\u0639\u0629'),
          findsOneWidget);
      expect(find.textContaining('-20'), findsOneWidget);
      expect(
          find.textContaining('\u0645\u0631\u062c\u0639: #99'), findsOneWidget);
      expect(trailingAmountColor(tester), AppColors.warning);
      expect(find.byIcon(Icons.shopping_cart_rounded), findsNothing);
      expect(
          find.text(
              '\u0627\u0633\u062a\u0631\u062f\u0627\u062f \u0646\u0642\u062f\u064a'),
          findsNothing);
    });

    testWidgets('D) REFUND display', (tester) async {
      await pumpListTile(
        tester,
        transaction: sampleTx(
          id: 4,
          type: 'REFUND',
          amount: 30,
          referenceId: 12,
        ),
      );

      expect(find.byIcon(Icons.call_received_rounded), findsOneWidget);
      expect(
          find.text(
              '\u0627\u0633\u062a\u0631\u062f\u0627\u062f \u0646\u0642\u062f\u064a'),
          findsOneWidget);
      expect(find.textContaining('+30'), findsOneWidget);
      expect(
          find.textContaining('\u0645\u0631\u062c\u0639: #12'), findsOneWidget);
      expect(trailingAmountColor(tester), AppColors.success);
      expect(find.byIcon(Icons.shopping_cart_rounded), findsNothing);
      expect(find.text('\u0634\u0631\u0627\u0621'), findsNothing);
    });

    testWidgets('E) mixed transaction history', (tester) async {
      final transactions = [
        sampleTx(id: 1, type: 'PURCHASE', amount: 100),
        sampleTx(id: 2, type: 'PAYMENT', amount: -40),
        sampleTx(id: 3, type: 'RETURN', amount: -15),
        sampleTx(id: 4, type: 'REFUND', amount: 10),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ListView(
                children: transactions
                    .map(
                      (tx) => SupplierTransactionListTile(
                        transaction: tx,
                        moneyFormat: moneyFormat,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('\u0634\u0631\u0627\u0621'), findsOneWidget);
      expect(
          find.text(
              '\u062f\u0641\u0639\u0629 \u0644\u0644\u0645\u0648\u0631\u062f'),
          findsOneWidget);
      expect(
          find.text(
              '\u0645\u0631\u062a\u062c\u0639 \u0628\u0636\u0627\u0639\u0629'),
          findsOneWidget);
      expect(
          find.text(
              '\u0627\u0633\u062a\u0631\u062f\u0627\u062f \u0646\u0642\u062f\u064a'),
          findsOneWidget);
      expect(find.byIcon(Icons.shopping_cart_rounded), findsOneWidget);
      expect(find.byIcon(Icons.payments_rounded), findsOneWidget);
      expect(find.byIcon(Icons.assignment_return_rounded), findsOneWidget);
      expect(find.byIcon(Icons.call_received_rounded), findsOneWidget);
    });

    testWidgets('F) empty history', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supplierHistoryProvider(42).overrideWith(
              (ref) => Stream.value(<SupplierTransaction>[]),
            ),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SupplierTransactionsTab(
                  supplierId: 42,
                  moneyFormat: moneyFormat,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
          find.text(
              '\u0644\u0627 \u062a\u0648\u062c\u062f \u062d\u0631\u0643\u0627\u062a \u0645\u0627\u0644\u064a\u0629'),
          findsOneWidget);
    });

    testWidgets('G) rendering list tiles has no financial side effects',
        (tester) async {
      final transactions = [
        sampleTx(id: 1, type: 'PURCHASE', amount: 80),
        sampleTx(id: 2, type: 'REFUND', amount: 20),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ListView(
                children: transactions
                    .map(
                      (tx) => SupplierTransactionListTile(
                        transaction: tx,
                        moneyFormat: moneyFormat,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SupplierTransactionListTile), findsNWidgets(2));
    });

    test('G2) display mapping does not write supplier_transactions', () async {
      final db = AppDatabase.test();
      addTearDown(db.close);

      final supplierId = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('History Supplier')),
          );
      await db.supplierAccountsDao.applyTransaction(
        supplierId: supplierId,
        type: 'PURCHASE',
        amount: 80,
        note: 'seed purchase',
      );

      final history = await db.supplierAccountsDao.getHistory(supplierId);
      final txnCountBefore =
          (await db.select(db.supplierTransactions).get()).length;

      for (final tx in history) {
        final presentation = resolveSupplierTransactionPresentation(tx);
        expect(presentation.titleFor(tx), isNotEmpty);
      }

      final txnCountAfter =
          (await db.select(db.supplierTransactions).get()).length;
      expect(txnCountAfter, txnCountBefore);
    });

    test('H) REFUND integration display', () async {
      final db = AppDatabase.test();
      addTearDown(db.close);

      final supplierId = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('Refund Display Supplier')),
          );
      await db.supplierAccountsDao.applyTransaction(
        supplierId: supplierId,
        type: 'PURCHASE',
        amount: 50,
      );
      await db.supplierAccountsDao.applyTransaction(
        supplierId: supplierId,
        type: 'PAYMENT',
        amount: -50,
      );
      await db.supplierAccountsDao.recordReturnInTransaction(
        supplierId: supplierId,
        amount: 20,
        returnId: 1,
      );

      await SupplierRefundSettlementService(db).settleCredit(
        supplierId: supplierId,
        amount: 20,
      );

      final refundTxn = (await db.supplierAccountsDao.getHistory(supplierId))
          .firstWhere((tx) => tx.type == 'REFUND');
      final presentation = resolveSupplierTransactionPresentation(refundTxn);

      expect(presentation.defaultLabel,
          '\u0627\u0633\u062a\u0631\u062f\u0627\u062f \u0646\u0642\u062f\u064a');
      expect(presentation.icon, Icons.call_received_rounded);
      expect(presentation.amountColor, AppColors.success);
      expect(refundTxn.type, 'REFUND');
      expect(refundTxn.amount, 20);
    });

    test('mapping distinguishes RETURN from REFUND semantics', () {
      final returnPresentation = resolveSupplierTransactionPresentation(
        sampleTx(id: 1, type: 'RETURN', amount: -10),
      );
      final refundPresentation = resolveSupplierTransactionPresentation(
        sampleTx(id: 2, type: 'REFUND', amount: 10),
      );

      expect(returnPresentation.defaultLabel,
          '\u0645\u0631\u062a\u062c\u0639 \u0628\u0636\u0627\u0639\u0629');
      expect(refundPresentation.defaultLabel,
          '\u0627\u0633\u062a\u0631\u062f\u0627\u062f \u0646\u0642\u062f\u064a');
      expect(returnPresentation.icon, Icons.assignment_return_rounded);
      expect(refundPresentation.icon, Icons.call_received_rounded);
      expect(returnPresentation.amountColor, isNot(AppColors.error));
      expect(refundPresentation.amountColor, AppColors.success);
    });
  });
}
