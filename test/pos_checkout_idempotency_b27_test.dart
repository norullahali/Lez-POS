import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/pos_sale_fingerprint.dart';
import 'package:lez_pos/core/services/pos_sale_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/pos_sale_service.dart';
import 'package:lez_pos/features/pos/models/cart_item.dart';
import 'package:lez_pos/features/pos/models/cart_session.dart';
import 'package:lez_pos/features/pos/pos_checkout_idempotency.dart';
import 'package:lez_pos/features/products/models/product_model.dart';

void main() {
  group('PosCheckoutIdempotencyState (B27)', () {
    late PosCheckoutIdempotencyState state;
    var uuidSeq = 0;

    String nextKey() => 'b27-key-${++uuidSeq}';

    setUp(() {
      state = PosCheckoutIdempotencyState();
      uuidSeq = 0;
    });

    test('1) fresh checkout generates UUID', () {
      final key = state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp-a',
        generateUuid: nextKey,
      );
      expect(key, 'b27-key-1');
    });

    test('2) same intent reuses same UUID', () {
      final first = state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp-a',
        generateUuid: nextKey,
      );
      final second = state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp-a',
        generateUuid: nextKey,
      );
      expect(second, first);
      expect(uuidSeq, 1);
    });

    test('3) dialog reopen same intent reuses UUID', () {
      state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp-checkout',
        generateUuid: nextKey,
      );
      final reopen = state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp-checkout',
        generateUuid: nextKey,
      );
      expect(reopen, 'b27-key-1');
    });

    test('4) post-commit UI failure retains key', () {
      state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp-sold',
        generateUuid: nextKey,
      );
      expect(state.slot(1).idempotencyKey, isNotNull);
      expect(state.slot(1).boundFingerprintHash, 'fp-sold');
    });

    test('6) material cart change generates new key', () {
      final k1 = state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp-cart-a',
        generateUuid: nextKey,
      );
      final k2 = state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp-cart-b',
        generateUuid: nextKey,
      );
      expect(k2, isNot(k1));
      expect(uuidSeq, 2);
    });

    test('7) material payment change generates new key', () {
      final k1 = state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp-pay-cash',
        generateUuid: nextKey,
      );
      final k2 = state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp-pay-mixed',
        generateUuid: nextKey,
      );
      expect(k2, isNot(k1));
    });

    test('8) non-material rebuild preserves key', () {
      final k1 = state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp-stable',
        generateUuid: nextKey,
      );
      final k2 = state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp-stable',
        generateUuid: nextKey,
      );
      expect(k2, k1);
    });

    test('9) clearCheckoutKey clears slot', () {
      state.prepareCheckoutKey(
        cartSlotId: 2,
        fingerprintHash: 'fp',
        generateUuid: nextKey,
      );
      state.clearCheckoutKey(2);
      expect(state.slot(2).idempotencyKey, isNull);
    });

    test('10) successful checkout clears key', () {
      state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp',
        generateUuid: nextKey,
      );
      state.clearCheckoutKey(1);
      expect(state.slot(1).idempotencyKey, isNull);
    });

    test('12) conflict does not rotate key (caller retains state)', () {
      final key = state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp-bound',
        generateUuid: nextKey,
      );
      expect(state.slot(1).idempotencyKey, key);
      expect(
        state.prepareCheckoutKey(
          cartSlotId: 1,
          fingerprintHash: 'fp-bound',
          generateUuid: nextKey,
        ),
        key,
      );
    });

    test('13) two cart slots have independent keys', () {
      final k1 = state.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: 'fp',
        generateUuid: nextKey,
      );
      final k2 = state.prepareCheckoutKey(
        cartSlotId: 2,
        fingerprintHash: 'fp',
        generateUuid: nextKey,
      );
      expect(k1, isNot(k2));
    });

    test('14) in-flight guard blocks duplicate submit start', () {
      expect(canStartCheckoutSubmit(inFlight: true), isFalse);
      expect(canStartCheckoutSubmit(inFlight: false), isTrue);
    });
  });

  group('B27 + B5 persisted checkout replay', () {
    late AppDatabase db;
    late PosSaleService saleService;
    late PosCheckoutIdempotencyState checkoutKeys;
    late int productId;
    var uuidSeq = 0;

    String nextCheckoutKey() => 'b27-sale-${++uuidSeq}';

    setUp(() async {
      db = AppDatabase.test();
      saleService = PosSaleService(db);
      checkoutKeys = PosCheckoutIdempotencyState();
      uuidSeq = 0;
      productId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('B27 Product'),
              barcode: Value('B27-P'),
              currentStock: Value(50),
              costPrice: Value(3),
              sellPrice: Value(10),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    ProductModel productModel() => ProductModel(
          id: productId,
          name: 'B27 Product',
          barcode: 'B27-P',
          costPrice: 3,
          sellPrice: 10,
        );

    CartSession testCart({int slotId = 1}) {
      return CartSession(
        id: slotId,
        createdAt: DateTime(2026, 1, 1),
        items: [
          CartItem(product: productModel(), quantity: 1, unitPrice: 10),
        ],
      );
    }

    PaymentInfo cashPayment({double amount = 10, String key = 'unused'}) {
      return PaymentInfo(
        method: 'CASH',
        idempotencyKey: key,
        cashPaid: amount,
      );
    }

    String fingerprint(CartSession cart, PaymentInfo payment) {
      return PosSaleFingerprint.compute(
        sessionId: 1,
        cartSlotId: cart.id,
        items: cart.items,
        invoiceDiscount: cart.invoiceDiscount,
        loyaltyPointsUsed: 0,
        loyaltyDiscount: 0,
        customerId: null,
        payment: payment,
      );
    }

    Future<void> runCheckoutSale({
      required CartSession cart,
      required PaymentInfo payment,
      required String fingerprintHash,
    }) {
      final key = checkoutKeys.prepareCheckoutKey(
        cartSlotId: cart.id,
        fingerprintHash: fingerprintHash,
        generateUuid: nextCheckoutKey,
      );
      return saleService
          .processSale(
            idempotencyKey: key,
            fingerprintHash: fingerprintHash,
            invoice: SalesInvoicesCompanion(
              subtotal: const Value(10),
              total: const Value(10),
              paymentMethod: const Value('CASH'),
              cashPaid: const Value(10),
              debtAmount: const Value(0),
            ),
            items: [
              SaleItemsCompanion(
                productId: Value(productId),
                quantity: const Value(1),
                unitPrice: const Value(10),
                unitCost: const Value(3),
                total: const Value(10),
              ),
            ],
            netSaleTotal: 10,
          )
          .then((_) {});
    }

    Future<int> invoiceCount() async =>
        (await db.select(db.salesInvoices).get()).length;

    test('5) retry after committed sale uses same key and B5 replay', () async {
      final cart = testCart();
      final payment = cashPayment();
      final fp = fingerprint(cart, payment);

      await runCheckoutSale(cart: cart, payment: payment, fingerprintHash: fp);
      expect(await invoiceCount(), 1);

      final retryKey = checkoutKeys.prepareCheckoutKey(
        cartSlotId: cart.id,
        fingerprintHash: fp,
        generateUuid: nextCheckoutKey,
      );
      expect(retryKey, 'b27-sale-1');

      final replay = await saleService.processSale(
        idempotencyKey: retryKey,
        fingerprintHash: fp,
        invoice: SalesInvoicesCompanion(
          subtotal: const Value(10),
          total: const Value(10),
          paymentMethod: const Value('CASH'),
          cashPaid: const Value(10),
          debtAmount: const Value(0),
        ),
        items: [
          SaleItemsCompanion(
            productId: Value(productId),
            quantity: const Value(1),
            unitPrice: const Value(10),
            unitCost: const Value(3),
            total: const Value(10),
          ),
        ],
        netSaleTotal: 10,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(await invoiceCount(), 1);
    });

    test('11) idempotentReplay follows success semantics', () async {
      final cart = testCart();
      final payment = cashPayment();
      final fp = fingerprint(cart, payment);
      final key = checkoutKeys.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: fp,
        generateUuid: nextCheckoutKey,
      );
      final first = await saleService.processSale(
        idempotencyKey: key,
        fingerprintHash: fp,
        invoice: SalesInvoicesCompanion(
          subtotal: const Value(10),
          total: const Value(10),
          paymentMethod: const Value('CASH'),
          cashPaid: const Value(10),
          debtAmount: const Value(0),
        ),
        items: [
          SaleItemsCompanion(
            productId: Value(productId),
            quantity: const Value(1),
            unitPrice: const Value(10),
            unitCost: const Value(3),
            total: const Value(10),
          ),
        ],
        netSaleTotal: 10,
      );
      expect(first.idempotentReplay, isFalse);

      final second = await saleService.processSale(
        idempotencyKey: key,
        fingerprintHash: fp,
        invoice: SalesInvoicesCompanion(
          subtotal: const Value(10),
          total: const Value(10),
          paymentMethod: const Value('CASH'),
          cashPaid: const Value(10),
          debtAmount: const Value(0),
        ),
        items: [
          SaleItemsCompanion(
            productId: Value(productId),
            quantity: const Value(1),
            unitPrice: const Value(10),
            unitCost: const Value(3),
            total: const Value(10),
          ),
        ],
        netSaleTotal: 10,
      );
      expect(second.idempotentReplay, isTrue);
      checkoutKeys.clearCheckoutKey(1);
      expect(checkoutKeys.slot(1).idempotencyKey, isNull);
    });

    test('B5 conflict retains checkout key for same fingerprint binding', () async {
      final cart = testCart();
      final payment = cashPayment();
      final fp = fingerprint(cart, payment);
      final key = checkoutKeys.prepareCheckoutKey(
        cartSlotId: 1,
        fingerprintHash: fp,
        generateUuid: nextCheckoutKey,
      );
      await saleService.processSale(
        idempotencyKey: key,
        fingerprintHash: fp,
        invoice: SalesInvoicesCompanion(
          subtotal: const Value(10),
          total: const Value(10),
          paymentMethod: const Value('CASH'),
          cashPaid: const Value(10),
          debtAmount: const Value(0),
        ),
        items: [
          SaleItemsCompanion(
            productId: Value(productId),
            quantity: const Value(1),
            unitPrice: const Value(10),
            unitCost: const Value(3),
            total: const Value(10),
          ),
        ],
        netSaleTotal: 10,
      );

      await expectLater(
        saleService.processSale(
          idempotencyKey: key,
          fingerprintHash: 'different-fp',
          invoice: SalesInvoicesCompanion(
            subtotal: const Value(10),
            total: const Value(10),
            paymentMethod: const Value('CASH'),
            cashPaid: const Value(10),
            debtAmount: const Value(0),
          ),
          items: [
            SaleItemsCompanion(
              productId: Value(productId),
              quantity: const Value(1),
              unitPrice: const Value(10),
              unitCost: const Value(3),
              total: const Value(10),
            ),
          ],
          netSaleTotal: 10,
        ),
        throwsA(isA<PosSaleIdempotencyConflictException>()),
      );

      expect(
        checkoutKeys.prepareCheckoutKey(
          cartSlotId: 1,
          fingerprintHash: fp,
          generateUuid: nextCheckoutKey,
        ),
        key,
      );
      expect(await invoiceCount(), 1);
    });
  });
}
