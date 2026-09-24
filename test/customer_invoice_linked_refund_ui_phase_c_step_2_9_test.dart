import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/constants/invoice_lifecycle.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_refund_settlement_service.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';
import 'package:lez_pos/features/auth/permissions/permission_keys.dart';
import 'package:lez_pos/features/auth/providers/permission_provider.dart';
import 'package:lez_pos/features/customers/providers/customer_accounts_provider.dart';
import 'package:lez_pos/features/customers/providers/customer_refund_settlement_provider.dart';
import 'package:lez_pos/features/customers/screens/widgets/customer_credit_refund_entry.dart';
import 'package:lez_pos/features/customers/utils/customer_refund_settlement_messages.dart';
import 'package:lez_pos/features/invoices/models/invoice_detail.dart';
import 'package:lez_pos/features/invoices/providers/invoice_history_provider.dart';
import 'package:lez_pos/features/invoices/widgets/invoice_details_dialog.dart';
import 'package:lez_pos/features/returns/models/customer_return_history_models.dart';
import 'package:lez_pos/features/returns/providers/customer_return_detail_provider.dart';
import 'package:lez_pos/features/returns/providers/partial_return_provider.dart';
import 'package:lez_pos/features/returns/repositories/customer_return_read_repository.dart';

void main() {
  group('Phase C Step 2.9 invoice details linked refund wiring', () {
    late AppDatabase db;
    late CustomerReturnReadRepository readRepo;
    late int customerId;
    late int productId;
    late int invoiceId;

    InvoiceDetailData buildDetail({
      required int id,
      required int detailCustomerId,
      required String customerName,
      String invoiceStatus = InvoiceLifecycleStatus.completed,
      String paymentMethod = 'DEBT',
    }) {
      return InvoiceDetailData(
        header: InvoiceDetailHeader(
          id: id,
          invoiceNumber: 'INV-2.9',
          saleDate: DateTime(2026, 1, 15, 10, 30),
          customerId: detailCustomerId,
          customerName: customerName,
          cashierName: 'Cashier',
          paymentMethod: paymentMethod,
          invoiceStatus: invoiceStatus,
          subtotal: 50,
          discountTotal: 0,
          total: 50,
          cashPaid: paymentMethod == 'CASH' ? 50 : 0,
          cardPaid: 0,
          changeAmount: 0,
        ),
        lines: const [
          InvoiceDetailLine(
            id: 1,
            productId: 1,
            productName: 'Test Product',
            quantity: 10,
            unitPrice: 5,
            unitCost: 5,
            discount: 0,
            lineTotal: 50,
          ),
        ],
        showTax: false,
      );
    }

    Future<void> seedCredit({double credit = 20}) async {
      invoiceId = await db.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber: Value('INV-${DateTime.now().microsecondsSinceEpoch}'),
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

    Future<int> seedPartialReturn({double qty = 2}) async {
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
            quantity: qty,
            unitPrice: 5,
            unitCost: 5,
          ),
        ],
      );
      return (await db.returnsDao.findCustomerReturnByOriginalInvoiceId(
        invoiceId,
      ))!
          .id;
    }

    Future<int> seedCashPartialReturn() async {
      invoiceId = await db.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber: Value('CASH-${DateTime.now().microsecondsSinceEpoch}'),
          subtotal: const Value(20),
          total: const Value(20),
          debtAmount: const Value(0),
          cashPaid: const Value(20),
          customerId: Value(customerId),
          paymentMethod: const Value('CASH'),
        ),
        items: [
          {'productId': productId, 'qty': 2.0, 'price': 10.0, 'cost': 5.0},
        ],
      );
      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 100,
        note: 'unrelated aggregate credit',
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
      return (await db.returnsDao.findCustomerReturnByOriginalInvoiceId(
        invoiceId,
      ))!
          .id;
    }

    Future<void> seedLegacyPartialWithoutHeader() async {
      await seedCredit();
      final saleItemId =
          (await db.salesDao.getItemsForInvoice(invoiceId)).single.id;
      await db.into(db.saleItemReturns).insert(
            SaleItemReturnsCompanion.insert(
              saleInvoiceId: invoiceId,
              saleItemId: saleItemId,
              productId: productId,
              returnedQuantity: 1,
              unitPriceAtReturn: 5,
              returnTotal: 5,
              returnedByUserId: 1,
            ),
          );
    }

    List<Override> dialogOverrides({
      required InvoiceDetailData detail,
      double creditOverride = 20,
      CustomerReturnReadRepository? repoOverride,
      CustomerReturn? linkedHeader,
      bool linkedHeaderResolved = false,
      ReturnRefundableSnapshot? returnSnapshot,
    }) {
      final repo = repoOverride ?? readRepo;
      return [
        invoiceDetailProvider(detail.header.id)
            .overrideWith((ref) async => detail),
        invoicePartialReturnQtysProvider(detail.header.id)
            .overrideWith((ref) async => <int, double>{}),
        invoiceLinkedCustomerReturnProvider(detail.header.id).overrideWith(
          (ref) async {
            if (linkedHeaderResolved) return linkedHeader;
            return repo.findInvoiceLinkedHeader(detail.header.id);
          },
        ),
        customerReturnReadRepositoryProvider.overrideWithValue(repo),
        partialReturnServiceProvider
            .overrideWith((ref) => PartialReturnService(db)),
        customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        permissionProvider(PermissionKeys.posFullRefund)
            .overrideWith((ref) => true),
        customerAvailableCreditProvider(detail.header.customerId!)
            .overrideWith((ref) async => creditOverride),
        if (returnSnapshot != null)
          customerReturnRemainingRefundableProvider(returnSnapshot.returnId)
              .overrideWith((ref) async => returnSnapshot),
      ];
    }

    setUp(() async {
      db = AppDatabase.test();
      readRepo = CustomerReturnReadRepository(db);
      customerId = await db.into(db.customers).insert(
            const CustomersCompanion(name: Value('Invoice Linked Customer')),
          );
      productId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('Linked Product'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
          );
    });

    tearDown(() async => db.close());

    Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
      for (var attempt = 0; attempt < 40; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (tester.any(finder)) return;
      }
      fail('Timed out waiting for $finder');
    }

    Future<CustomerCreditRefundEntry> readEntry(
      WidgetTester tester, {
      int? expectReturnId,
    }) async {
      await pumpUntilFound(tester, find.byType(CustomerCreditRefundEntry));
      for (var attempt = 0; attempt < 40; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
        final entry = tester.widget<CustomerCreditRefundEntry>(
          find.byType(CustomerCreditRefundEntry),
        );
        if (expectReturnId != null) {
          if (entry.returnId == expectReturnId) return entry;
        } else if (attempt >= 5) {
          return entry;
        }
      }
      return tester.widget<CustomerCreditRefundEntry>(
        find.byType(CustomerCreditRefundEntry),
      );
    }

    test('A) credit invoice with no return keeps returnId null', () async {
      await seedCredit();
      final header = await readRepo.findInvoiceLinkedHeader(invoiceId);
      expect(header, isNull);
    });

    test('B) partial return wires returnId to customer_returns.id', () async {
      final returnId = await seedPartialReturn();
      final header = await readRepo.findInvoiceLinkedHeader(invoiceId);
      expect(header, isNotNull);
      expect(header!.id, returnId);
    });

    test('C) full return reuses the same linked header', () async {
      final partialReturnId = await seedPartialReturn(qty: 2);
      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'full finish',
        returnedByUserId: 1,
      );
      final header = await readRepo.findInvoiceLinkedHeader(invoiceId);
      expect(header, isNotNull);
      expect(header!.id, partialReturnId);
    });

    test('D) returnLabel matches displayCustomerReturnNumber semantics',
        () async {
      await seedPartialReturn();
      final header = (await readRepo.findInvoiceLinkedHeader(invoiceId))!;
      expect(
        displayCustomerReturnNumber(
          id: header.id,
          returnNumber: header.returnNumber,
        ),
        header.returnNumber.isNotEmpty ? header.returnNumber : '#${header.id}',
      );
    });

    testWidgets('E) linked entry shows Step 2.7C remaining refund row',
        (tester) async {
      late int returnId;
      late CustomerReturn linkedHeader;
      late ReturnRefundableSnapshot returnSnapshot;
      await tester.runAsync(() async {
        returnId = await seedPartialReturn();
        linkedHeader = (await readRepo.findInvoiceLinkedHeader(invoiceId))!;
        returnSnapshot =
            (await readRepo.getReturnRefundableSnapshot(returnId))!;
      });

      final detail = buildDetail(
        id: invoiceId,
        detailCustomerId: customerId,
        customerName: 'Invoice Linked Customer',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: dialogOverrides(
            detail: detail,
            linkedHeader: linkedHeader,
            linkedHeaderResolved: true,
            returnSnapshot: returnSnapshot,
          ),
          child: MaterialApp(
            home: InvoiceDetailsDialog(invoiceId: invoiceId),
          ),
        ),
      );

      final entry = await readEntry(tester, expectReturnId: returnId);
      expect(entry.returnId, returnId);
      await pumpUntilFound(
        tester,
        find.textContaining(CustomerCreditRefundEntry.returnRemainingLabel),
      );
    });

    test('F) invoice details refund uses per-return cap via settleCredit',
        () async {
      final returnId = await seedPartialReturn(qty: 10);
      final service = CustomerRefundSettlementService(db);
      final beforeSettled =
          await db.returnsDao.getSettledAmountForCustomerReturn(returnId);

      await service.settleCredit(
        customerId: customerId,
        amount: 50,
        returnId: returnId,
      );

      final refunds = await (db.select(db.customerTransactions)
            ..where((t) => t.type.equals('REFUND')))
          .get();
      expect(refunds.last.referenceId, returnId);
      expect(
        await db.returnsDao.getSettledAmountForCustomerReturn(returnId),
        beforeSettled! + 50,
      );
    });

    testWidgets('G) cash invoice links header but disables refund',
        (tester) async {
      late int returnId;
      late CustomerReturn linkedHeader;
      late ReturnRefundableSnapshot returnSnapshot;
      await tester.runAsync(() async {
        returnId = await seedCashPartialReturn();
        linkedHeader = (await readRepo.findInvoiceLinkedHeader(invoiceId))!;
        returnSnapshot =
            (await readRepo.getReturnRefundableSnapshot(returnId))!;
        expect(returnSnapshot.remainingRefundable, 0);
      });

      final detail = buildDetail(
        id: invoiceId,
        detailCustomerId: customerId,
        customerName: 'Invoice Linked Customer',
        paymentMethod: 'CASH',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: dialogOverrides(
            detail: detail,
            creditOverride: 50,
            linkedHeader: linkedHeader,
            linkedHeaderResolved: true,
            returnSnapshot: returnSnapshot,
          ),
          child: MaterialApp(
            home: InvoiceDetailsDialog(invoiceId: invoiceId),
          ),
        ),
      );

      final entry = await readEntry(tester, expectReturnId: returnId);
      expect(entry.returnId, returnId);
      await pumpUntilFound(
        tester,
        find.textContaining(CustomerCreditRefundEntry.returnRemainingLabel),
      );
      expect(
        find.textContaining('0'),
        findsWidgets,
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(
                ElevatedButton,
                CustomerCreditRefundEntry.refundButtonLabel,
              ),
            )
            .onPressed,
        isNull,
      );
    });

    test('H) legacy partial without customer_returns header stays unlinked',
        () async {
      await seedLegacyPartialWithoutHeader();
      final header = await readRepo.findInvoiceLinkedHeader(invoiceId);
      expect(header, isNull);
    });

    test('I) provider sees header after partial return creation', () async {
      await seedCredit();
      final container = ProviderContainer(
        overrides: [
          customerReturnReadRepositoryProvider.overrideWithValue(readRepo),
        ],
      );
      addTearDown(container.dispose);

      final before = await container.read(
        invoiceLinkedCustomerReturnProvider(invoiceId).future,
      );
      expect(before, isNull);

      final saleItemId =
          (await db.salesDao.getItemsForInvoice(invoiceId)).single.id;
      await PartialReturnService(db).processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: 1,
        lines: [
          PartialReturnLine(
            saleItemId: saleItemId,
            productId: productId,
            quantity: 2,
            unitPrice: 5,
            unitCost: 5,
          ),
        ],
      );

      container.invalidate(invoiceLinkedCustomerReturnProvider(invoiceId));
      final after = await container.read(
        invoiceLinkedCustomerReturnProvider(invoiceId).future,
      );
      expect(after, isNotNull);
      expect(after!.originalInvoiceId, invoiceId);
    });

    testWidgets('J) invoice ID and sale item ID are never passed as returnId',
        (tester) async {
      const testInvoiceId = 42;
      final detail = buildDetail(
        id: testInvoiceId,
        detailCustomerId: customerId,
        customerName: 'Invoice Linked Customer',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            invoiceDetailProvider(testInvoiceId)
                .overrideWith((ref) async => detail),
            invoicePartialReturnQtysProvider(testInvoiceId)
                .overrideWith((ref) async => <int, double>{}),
            invoiceLinkedCustomerReturnProvider(testInvoiceId)
                .overrideWith((ref) async => null),
            customerAvailableCreditProvider(customerId)
                .overrideWith((ref) async => 20),
            permissionProvider(PermissionKeys.posFullRefund)
                .overrideWith((ref) => true),
          ],
          child: MaterialApp(
            home: InvoiceDetailsDialog(invoiceId: testInvoiceId),
          ),
        ),
      );

      final entry = await readEntry(tester);
      expect(entry.returnId, isNull);
      expect(entry.returnId, isNot(testInvoiceId));
      expect(entry.returnId, isNot(detail.lines.first.id));
    });

    testWidgets('K) no-return invoice details keeps aggregate-only entry',
        (tester) async {
      await tester.runAsync(() async {
        await seedCredit();
      });

      final detail = buildDetail(
        id: invoiceId,
        detailCustomerId: customerId,
        customerName: 'Invoice Linked Customer',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: dialogOverrides(
            detail: detail,
            linkedHeader: null,
            linkedHeaderResolved: true,
          ),
          child: MaterialApp(
            home: InvoiceDetailsDialog(invoiceId: invoiceId),
          ),
        ),
      );

      final entry = await readEntry(tester);
      expect(entry.returnId, isNull);
      expect(entry.returnLabel, isNull);
      expect(
        find.textContaining(CustomerCreditRefundEntry.returnRemainingLabel),
        findsNothing,
      );
    });

    test('client validation blocks amount above per-return remaining', () {
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
  });
}
