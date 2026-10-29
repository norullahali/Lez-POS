import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/constants/invoice_lifecycle.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/receipt_financials.dart';
import 'package:lez_pos/core/services/receipt_invoice_mapper.dart';
import 'package:lez_pos/core/services/receipt_service.dart';
import 'package:lez_pos/core/services/settings_service.dart';
import 'package:lez_pos/features/invoices/models/invoice_detail.dart';
import 'package:lez_pos/features/pos/models/invoice_models.dart';

InvoiceDetailData _fixtureDetail({DateTime? saleDate}) {
  final date = saleDate ?? DateTime(2024, 6, 15, 14, 30);
  return InvoiceDetailData(
    header: InvoiceDetailHeader(
      id: 1,
      invoiceNumber: 'INV-100',
      saleDate: date,
      customerName: 'General',
      cashierName: 'Cashier',
      paymentMethod: 'CASH',
      invoiceStatus: InvoiceLifecycleStatus.completed,
      subtotal: 100,
      discountTotal: 10,
      total: 90,
      cashPaid: 100,
      cardPaid: 0,
      changeAmount: 10,
    ),
    lines: const [
      InvoiceDetailLine(
        id: 1,
        productId: 1,
        productName: 'Product A',
        quantity: 2,
        unitPrice: 50,
        unitCost: 10,
        discount: 0,
        lineTotal: 100,
      ),
    ],
    showTax: true,
  );
}

void main() {
  test('tax display-only; grand total persisted', () {
    final data = InvoiceData(
      invoiceNumber: 'X',
      storeName: 'S',
      total: 90,
      headerSubtotal: 100,
      headerDiscountTotal: 10,
      showTax: true,
      items: [
        InvoiceItem(name: 'A', qty: 2, unitPrice: 50, lineTotal: 100),
      ],
    );
    expect(ReceiptFinancials.netBeforeTax(data), 90);
    expect(ReceiptFinancials.taxDisplayAmount(data), closeTo(13.5, 0.001));
    expect(ReceiptFinancials.grandTotal(data), 90);
  });

  test('line discount keeps persisted line total', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Discounted'),
            currentStock: Value(100),
            costPrice: Value(1),
          ),
        );
    final invoiceId = await db.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('DIS-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: const Value(90),
        total: const Value(90),
        paymentMethod: const Value('CASH'),
        cashPaid: const Value(90),
      ),
      items: [
        {
          'productId': productId,
          'qty': 2.0,
          'price': 50.0,
          'cost': 1.0,
          'discount': 10.0,
        },
      ],
    );
    final receipt = await loadPersistedReceiptData(invoiceId, db);
    final line = receipt.items.single;
    expect(line.lineTotal, 90);
    expect(line.lineDiscount, 10);
  });

  test('loadPersistedReceiptData is read-only', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('P'),
            currentStock: Value(50),
            costPrice: Value(1),
          ),
        );
    final invoiceId = await db.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('RO-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: const Value(10),
        total: const Value(10),
        paymentMethod: const Value('CASH'),
        cashPaid: const Value(10),
      ),
      items: [
        {'productId': productId, 'qty': 1.0, 'price': 10.0, 'cost': 1.0},
      ],
    );
    final before = (await db.select(db.salesInvoices).get()).length;
    await loadPersistedReceiptData(invoiceId, db);
    await loadPersistedReceiptData(invoiceId, db);
    final after = (await db.select(db.salesInvoices).get()).length;
    expect(after, before);
  });



  test('header discount and authoritative total', () {
    final data = InvoiceData(
      invoiceNumber: 'X',
      storeName: 'S',
      total: 85,
      headerSubtotal: 100,
      headerDiscountTotal: 15,
      showTax: true,
      items: const [],
    );
    expect(ReceiptFinancials.grandTotal(data), 85);
    expect(ReceiptFinancials.taxDisplayAmount(data), closeTo(12.75, 0.001));
  });

  test('signed return quantity from DB', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Return Item'),
            currentStock: Value(0),
            costPrice: Value(1),
          ),
        );
    final saleDate = DateTime(2023, 1, 10, 9);
    final invoiceId = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion(
            invoiceNumber: const Value('RET-1'),
            saleDate: Value(saleDate),
            subtotal: const Value(-20),
            total: const Value(-20),
            paymentMethod: const Value('CASH'),
          ),
        );
    await db.into(db.saleItems).insert(
          SaleItemsCompanion(
            invoiceId: Value(invoiceId),
            productId: Value(productId),
            quantity: const Value(-2),
            unitPrice: const Value(10),
            unitCost: const Value(1),
            total: const Value(-20),
          ),
        );
    final receipt = await loadPersistedReceiptData(invoiceId, db);
    expect(receipt.date, saleDate);
    expect(receipt.items.single.qty, -2);
    expect(receipt.total, -20);
  });

  test('mixed payment and debt from DB', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('P'),
            currentStock: Value(100),
            costPrice: Value(1),
          ),
        );
    final invoiceId = await db.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('MIX-'),
        subtotal: const Value(100),
        total: const Value(100),
        paymentMethod: const Value('MIXED'),
        cashPaid: const Value(40),
        cardPaid: const Value(30),
        debtAmount: const Value(30),
      ),
      items: [
        {'productId': productId, 'qty': 1.0, 'price': 100.0, 'cost': 1.0},
      ],
    );
    final receipt = await loadPersistedReceiptData(invoiceId, db);
    expect(receipt.cashPaid, 40);
    expect(receipt.cardPaid, 30);
    expect(receipt.debtAmount, 30);
    expect(receipt.paid, 70);
  });

  test('sale date stable on mapper reload', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final detail = _fixtureDetail(saleDate: DateTime(2022, 5, 1, 12));
    final mapped = await ReceiptInvoiceMapper.buildFromDetail(
      detail,
      SettingsService(db),
    );
    expect(mapped.date, DateTime(2022, 5, 1, 12));
  });
}
