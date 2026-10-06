import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/constants/movement_types.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/supplier_account_service.dart';
import 'package:lez_pos/core/services/supplier_return_fingerprint.dart';
import 'package:lez_pos/core/services/supplier_return_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/supplier_return_posting_result.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';
import 'package:lez_pos/features/returns/models/supplier_return_draft_models.dart';
import 'package:lez_pos/features/returns/providers/supplier_return_draft_provider.dart';
import 'package:lez_pos/features/returns/providers/supplier_return_service_provider.dart';
import 'package:lez_pos/features/returns/repositories/supplier_return_read_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/supplier_payment_test_keys.dart';
import 'support/supplier_return_posting_helpers.dart';
import 'support/supplier_return_test_keys.dart';

Future<({sqlite3.Database rawDb, String path})> openSimulatedV42RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b15_v42_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement(
      'DROP TABLE IF EXISTS supplier_return_idempotency');
  await bootstrap.customStatement('PRAGMA user_version = 42');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 42);
  return (rawDb: rawDb, path: dbPath);
}

class _CountingSupplierReturnService extends SupplierReturnService {
  _CountingSupplierReturnService(super.db);

  bool failFirstCall = true;
  int postCalls = 0;
  final List<String> keysUsed = [];

  @override
  Future<SupplierReturnPostingResult> postPurchaseLinkedReturn({
    required String idempotencyKey,
    required SupplierReturnPostingInput input,
  }) async {
    postCalls++;
    keysUsed.add(idempotencyKey);
    if (failFirstCall) {
      failFirstCall = false;
      throw Exception('forced first submit failure');
    }
    return super.postPurchaseLinkedReturn(
      idempotencyKey: idempotencyKey,
      input: input,
    );
  }
}

Future<Object?> _tryPost(
  SupplierReturnService service,
  SupplierReturnPostingInput input,
  String idempotencyKey,
) async {
  try {
    return await postSupplierReturn(
      service,
      input,
      idempotencyKey: idempotencyKey,
    );
  } on SupplierReturnIdempotencyConflictException {
    return 'conflict';
  }
}

void main() {
  late AppDatabase db;
  late SupplierReturnService service;
  late int supplierId;
  late int productId;
  late int purchaseItemId;
  late int invoiceId;

  SupplierReturnPostingInput postingInput({
    List<SupplierReturnPostingLine>? lines,
    String? reason,
    String? notes,
  }) {
    return SupplierReturnPostingInput(
      supplierId: supplierId,
      purchaseInvoiceId: invoiceId,
      lines: lines ??
          [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItemId,
              quantity: 2,
            ),
          ],
      reason: reason,
      notes: notes,
    );
  }

  setUp(() async {
    db = AppDatabase.test();
    service = SupplierReturnService(db);

    supplierId = await db.into(db.suppliers).insert(
          const SuppliersCompanion(name: Value('B15 Supplier')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('B15 Part'),
            currentStock: Value(0),
          ),
        );

    invoiceId = await db.purchasesDao.savePurchaseInvoice(
      header: PurchaseInvoicesCompanion(
        supplierId: Value(supplierId),
        purchaseDate: Value(DateTime(2026, 3, 1)),
        total: const Value(100),
        paidAmount: const Value(0),
        debtAmount: const Value(100),
      ),
      items: [
        {'productId': productId, 'qty': 30.0, 'cost': 5.0},
      ],
    );

    final items = await db.purchasesDao.getItemsForInvoice(invoiceId);
    purchaseItemId = items.single.id;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> supplierReturnCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.supplierReturns).get()).length;
  }

  Future<int> idempotencyRowCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.supplierReturnIdempotency).get()).length;
  }

  Future<int> returnOutLedgerCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await (target.select(target.stockLedger)
          ..where(
              (l) => l.movementType.equals(StockMovementType.returnOut.code)))
        .get())
        .length;
  }

  Future<int> supplierReturnTxnCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await (target.select(target.supplierTransactions)
          ..where((t) => t.type.equals('RETURN')))
        .get())
        .length;
  }

  Future<double> supplierBalance([AppDatabase? database]) async {
    final target = database ?? db;
    return target.supplierAccountsDao.getBalance(supplierId);
  }

  Future<double> productStock([AppDatabase? database]) async {
    final target = database ?? db;
    return target.stockDao.getStock(productId);
  }


  Future<double> invoiceDebtAmount([AppDatabase? database]) async {
    final target = database ?? db;
    final row = await (target.select(target.purchaseInvoices)
          ..where((p) => p.id.equals(invoiceId)))
        .getSingle();
    return row.debtAmount;
  }
  Future<double> creditReversalTotal([AppDatabase? database]) async {
    final target = database ?? db;
    return target.supplierAccountsDao.getCreditReversalTotalForPurchaseInvoice(
      supplierId: supplierId,
      purchaseInvoiceId: invoiceId,
    );
  }

  Future<bool> idempotencyTableExists(AppDatabase database) async {
    final rows = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='supplier_return_idempotency'",
    ).get();
    return rows.isNotEmpty;
  }

  Future<void> seedConcurrentDatabase(AppDatabase target) async {
    final sid = await target.into(target.suppliers).insert(
          const SuppliersCompanion(name: Value('B15 Concurrent Supplier')),
        );
    final pid = await target.into(target.products).insert(
          const ProductsCompanion(
            name: Value('B15 Concurrent Part'),
            currentStock: Value(0),
          ),
        );
    final iid = await target.purchasesDao.savePurchaseInvoice(
      header: PurchaseInvoicesCompanion(
        supplierId: Value(sid),
        purchaseDate: Value(DateTime(2026, 3, 1)),
        total: const Value(100),
        paidAmount: const Value(0),
        debtAmount: const Value(100),
      ),
      items: [
        {'productId': pid, 'qty': 30.0, 'cost': 5.0},
      ],
    );
    supplierId = sid;
    productId = pid;
    invoiceId = iid;
    final items = await target.purchasesDao.getItemsForInvoice(iid);
    purchaseItemId = items.single.id;
  }

  group('B15 supplier purchase-linked return idempotency', () {
    test('A) first submit succeeds', () async {
      final key = b15SupplierReturnIdempotencyKey();
      final result = await postSupplierReturn(
        service,
        postingInput(),
        idempotencyKey: key,
      );

      expect(result.idempotentReplay, isFalse);
      expect(result.supplierReturnId, greaterThan(0));
      expect(await supplierReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await returnOutLedgerCount(), 1);
      expect(await supplierReturnTxnCount(), 1);
      expect(await productStock(), closeTo(28, 0.001)); // 30 - 2
    });

    test('B) same key + same fingerprint replays', () async {
      final key = b15SupplierReturnIdempotencyKey();
      await postSupplierReturn(service, postingInput(), idempotencyKey: key);
      final replay = await postSupplierReturn(
        service,
        postingInput(),
        idempotencyKey: key,
      );
      expect(replay.idempotentReplay, isTrue);
    });

    test('C) replay returns same supplierReturnId', () async {
      final key = b15SupplierReturnIdempotencyKey();
      final first = await postSupplierReturn(
        service,
        postingInput(),
        idempotencyKey: key,
      );
      final second = await postSupplierReturn(
        service,
        postingInput(),
        idempotencyKey: key,
      );
      expect(second.supplierReturnId, first.supplierReturnId);
    });

    test('D) replay creates no second supplier_returns row', () async {
      final key = b15SupplierReturnIdempotencyKey();
      await postSupplierReturn(service, postingInput(), idempotencyKey: key);
      await postSupplierReturn(service, postingInput(), idempotencyKey: key);
      expect(await supplierReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('E) replay creates no second stock ledger returnOut', () async {
      final key = b15SupplierReturnIdempotencyKey();
      await postSupplierReturn(service, postingInput(), idempotencyKey: key);
      await postSupplierReturn(service, postingInput(), idempotencyKey: key);
      expect(await returnOutLedgerCount(), 1);
    });

    test('F) replay creates no second supplier RETURN transaction', () async {
      final key = b15SupplierReturnIdempotencyKey();
      await postSupplierReturn(service, postingInput(), idempotencyKey: key);
      await postSupplierReturn(service, postingInput(), idempotencyKey: key);
      expect(await supplierReturnTxnCount(), 1);
    });

    test('G) same key + different fingerprint conflicts', () async {
      final key = b15SupplierReturnIdempotencyKey();
      await postSupplierReturn(service, postingInput(), idempotencyKey: key);
      await expectLater(
        postSupplierReturn(
          service,
          postingInput(
            lines: [
              SupplierReturnPostingLine(
                purchaseItemId: purchaseItemId,
                quantity: 3,
              ),
            ],
          ),
          idempotencyKey: key,
        ),
        throwsA(isA<SupplierReturnIdempotencyConflictException>()),
      );
    });

    test('H) conflict creates no mutation', () async {
      final key = b15SupplierReturnIdempotencyKey();
      await postSupplierReturn(service, postingInput(), idempotencyKey: key);
      final balanceAfterFirst = await supplierBalance();
      final stockAfterFirst = await productStock();

      await expectLater(
        postSupplierReturn(
          service,
          postingInput(
            lines: [
              SupplierReturnPostingLine(
                purchaseItemId: purchaseItemId,
                quantity: 4,
              ),
            ],
          ),
          idempotencyKey: key,
        ),
        throwsA(isA<SupplierReturnIdempotencyConflictException>()),
      );

      expect(await supplierReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await returnOutLedgerCount(), 1);
      expect(await supplierReturnTxnCount(), 1);
      expect(await supplierBalance(), balanceAfterFirst);
      expect(await productStock(), stockAfterFirst);
    });

    test('I) sequential retry after successful commit replays', () async {
      final key = b15SupplierReturnIdempotencyKey();
      final first = await postSupplierReturn(
        service,
        postingInput(),
        idempotencyKey: key,
      );
      expect(first.idempotentReplay, isFalse);

      final second = await postSupplierReturn(
        service,
        postingInput(),
        idempotencyKey: key,
      );
      expect(second.idempotentReplay, isTrue);
      expect(second.supplierReturnId, first.supplierReturnId);
    });

    test('J) retry after simulated failure succeeds fresh', () async {
      final key = b15SupplierReturnIdempotencyKey();
      final failingService = SupplierReturnService(
        db,
        preSealHook: () async {
          throw Exception('forced');
        },
      );

      await expectLater(
        postSupplierReturn(failingService, postingInput(), idempotencyKey: key),
        throwsA(isA<Exception>()),
      );
      expect(await supplierReturnCount(), 0);
      expect(await idempotencyRowCount(), 0);

      final retry = await postSupplierReturn(
        service,
        postingInput(),
        idempotencyKey: key,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await supplierReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('K) two connections same key same fingerprint commits once', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b15_conc_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 10000');
      rawB.execute('PRAGMA busy_timeout = 10000');
      addTearDown(() {
        rawA.dispose();
        rawB.dispose();
        File(dbPath).deleteSync();
      });

      final dbA = AppDatabase.test(NativeDatabase.opened(rawA));
      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      await seedConcurrentDatabase(dbA);

      final serviceA = SupplierReturnService(dbA);
      final serviceB = SupplierReturnService(dbB);
      final sameKey = b15SupplierReturnIdempotencyKey();
      final input = postingInput();

      final outcomes = await Future.wait([
        postSupplierReturn(serviceA, input, idempotencyKey: sameKey),
        postSupplierReturn(serviceB, input, idempotencyKey: sameKey),
      ]);

      expect(await supplierReturnCount(dbA), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(outcomes.map((r) => r.supplierReturnId).toSet().length, 1);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(outcomes.where((r) => !r.idempotentReplay).length, 1);
    });

    test('L) two connections same key different fingerprint one conflict',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b15_conf_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 10000');
      rawB.execute('PRAGMA busy_timeout = 10000');
      addTearDown(() {
        rawA.dispose();
        rawB.dispose();
        File(dbPath).deleteSync();
      });

      final dbA = AppDatabase.test(NativeDatabase.opened(rawA));
      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      await seedConcurrentDatabase(dbA);

      final serviceA = SupplierReturnService(dbA);
      final serviceB = SupplierReturnService(dbB);
      final sameKey = b15SupplierReturnIdempotencyKey();
      final inputA = postingInput();
      final inputB = postingInput(
        lines: [
          SupplierReturnPostingLine(
            purchaseItemId: purchaseItemId,
            quantity: 3,
          ),
        ],
      );

      final outcomes = await Future.wait<Object?>([
        _tryPost(serviceA, inputA, sameKey),
        _tryPost(serviceB, inputB, sameKey),
      ]);

      expect(await supplierReturnCount(dbA), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(outcomes.whereType<SupplierReturnPostingResult>().length, 1);
      expect(outcomes.where((o) => o == 'conflict').length, 1);
    });

    test('M) B14 cap for different keys credits at most invoice debt', () async {
      final key1 = b15SupplierReturnIdempotencyKey();
      final key2 = b15SupplierReturnIdempotencyKey();

      await postSupplierReturn(
        service,
        postingInput(
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItemId,
              quantity: 16,
            ),
          ],
        ),
        idempotencyKey: key1,
      );

      await postSupplierReturn(
        service,
        postingInput(
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItemId,
              quantity: 8,
            ),
          ],
        ),
        idempotencyKey: key2,
      );

      expect(await supplierReturnCount(), 2);
      expect(await idempotencyRowCount(), 2);
      expect(await creditReversalTotal(), closeTo(100, 0.0001));
      expect(await supplierReturnTxnCount(), 2);
    });

    test('N) SR2.3 quantity cap rejects second key after 10 qty return', () async {
      final capProductId = await db.into(db.products).insert(
            ProductsCompanion(
              name: const Value('B15 Cap Part'),
              barcode: Value(
                  'B15-CAP-${DateTime.now().microsecondsSinceEpoch}'),
            ),
          );
      final capInvoiceId = await db.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(supplierId),
          purchaseDate: Value(DateTime(2026, 3, 2)),
          total: const Value(100),
          paidAmount: const Value(0),
          debtAmount: const Value(100),
        ),
        items: [
          {'productId': capProductId, 'qty': 10.0, 'cost': 10.0},
        ],
      );
      final capItems = await db.purchasesDao.getItemsForInvoice(capInvoiceId);
      final capPurchaseItemId = capItems.single.id;

      final key1 = b15SupplierReturnIdempotencyKey();
      final key2 = b15SupplierReturnIdempotencyKey();

      await postSupplierReturn(
        service,
        SupplierReturnPostingInput(
          supplierId: supplierId,
          purchaseInvoiceId: capInvoiceId,
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: capPurchaseItemId,
              quantity: 10,
            ),
          ],
        ),
        idempotencyKey: key1,
      );

      await expectLater(
        postSupplierReturn(
          service,
          SupplierReturnPostingInput(
            supplierId: supplierId,
            purchaseInvoiceId: capInvoiceId,
            lines: [
              SupplierReturnPostingLine(
                purchaseItemId: capPurchaseItemId,
                quantity: 1,
              ),
            ],
          ),
          idempotencyKey: key2,
        ),
        throwsA(
          isA<SupplierReturnPostingException>().having(
            (e) => e.code,
            'code',
            SupplierReturnPostingFailure.quantityExceedsReturnable,
          ),
        ),
      );
      expect(await supplierReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('O) accounting failure rolls back return and idempotency row', () async {
      final key = b15SupplierReturnIdempotencyKey();
      final failingService = SupplierReturnService.withAccountingPoster(
        db,
        accountingPoster: ({
          required int supplierId,
          required double amount,
          required int returnId,
          String note = '',
        }) async {
          throw Exception('forced accounting failure');
        },
      );

      await expectLater(
        postSupplierReturn(failingService, postingInput(), idempotencyKey: key),
        throwsA(
          isA<SupplierReturnPostingException>().having(
            (e) => e.code,
            'code',
            SupplierReturnPostingFailure.supplierAccountingFailure,
          ),
        ),
      );

      expect(await supplierReturnCount(), 0);
      expect(await idempotencyRowCount(), 0);
      expect(await returnOutLedgerCount(), 0);
      expect(await supplierReturnTxnCount(), 0);
    });

    test('P) migration v42 -> v43 creates supplier_return_idempotency', () async {
      final opened = await openSimulatedV42RawDatabase();
      addTearDown(opened.rawDb.dispose);

      final before = opened.rawDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='supplier_return_idempotency'",
      );
      expect(before, isEmpty);

      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 45);
      expect(await idempotencyTableExists(migrated), isTrue);
    });

    test('Q) seal race preSealHook then retry succeeds once', () async {
      final key = b15SupplierReturnIdempotencyKey();
      final failingService = SupplierReturnService(
        db,
        preSealHook: () async {
          throw Exception('forced seal failure');
        },
      );

      await expectLater(
        postSupplierReturn(failingService, postingInput(), idempotencyKey: key),
        throwsA(isA<Exception>()),
      );
      expect(await supplierReturnCount(), 0);
      expect(await idempotencyRowCount(), 0);

      final retry = await postSupplierReturn(
        service,
        postingInput(),
        idempotencyKey: key,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await supplierReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('R) duplicate line ordering shares fingerprint and replays', () async {
      final key = b15SupplierReturnIdempotencyKey();
      final unordered = postingInput(
        lines: [
          SupplierReturnPostingLine(
            purchaseItemId: purchaseItemId,
            quantity: 2,
          ),
          SupplierReturnPostingLine(
            purchaseItemId: purchaseItemId,
            quantity: 1,
          ),
        ],
      );
      final ordered = postingInput(
        lines: [
          SupplierReturnPostingLine(
            purchaseItemId: purchaseItemId,
            quantity: 1,
          ),
          SupplierReturnPostingLine(
            purchaseItemId: purchaseItemId,
            quantity: 2,
          ),
        ],
      );

      expect(
        SupplierReturnFingerprint.compute(unordered),
        SupplierReturnFingerprint.compute(ordered),
      );

      final first = await postSupplierReturn(
        service,
        unordered,
        idempotencyKey: key,
      );
      final replay = await postSupplierReturn(
        service,
        ordered,
        idempotencyKey: key,
      );
      expect(first.idempotentReplay, isFalse);
      expect(replay.idempotentReplay, isTrue);
      expect(replay.supplierReturnId, first.supplierReturnId);
      expect(await supplierReturnCount(), 1);
    });

    test('S) different reason or notes on same key conflicts', () async {
      final key = b15SupplierReturnIdempotencyKey();
      await postSupplierReturn(
        service,
        postingInput(reason: 'damaged'),
        idempotencyKey: key,
      );
      await expectLater(
        postSupplierReturn(
          service,
          postingInput(reason: 'wrong item'),
          idempotencyKey: key,
        ),
        throwsA(isA<SupplierReturnIdempotencyConflictException>()),
      );

      final key2 = b15SupplierReturnIdempotencyKey();
      await postSupplierReturn(
        service,
        postingInput(notes: 'first note'),
        idempotencyKey: key2,
      );
      await expectLater(
        postSupplierReturn(
          service,
          postingInput(notes: 'second note'),
          idempotencyKey: key2,
        ),
        throwsA(isA<SupplierReturnIdempotencyConflictException>()),
      );
    });

    test('T) fully paid invoice null txn id and replay works', () async {
      await SupplierAccountService(db).processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
        amount: 100,
      );
      expect(await supplierBalance(), closeTo(0, 0.001));
      await (db.update(db.purchaseInvoices)
            ..where((p) => p.id.equals(invoiceId)))
          .write(const PurchaseInvoicesCompanion(debtAmount: Value(0)));
      expect(await invoiceDebtAmount(), closeTo(0, 0.001));

      final key = b15SupplierReturnIdempotencyKey();
      final first = await postSupplierReturn(
        service,
        postingInput(),
        idempotencyKey: key,
      );
      expect(first.supplierTransactionId, isNull);
      expect(first.idempotentReplay, isFalse);

      final replay = await postSupplierReturn(
        service,
        postingInput(),
        idempotencyKey: key,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(replay.supplierReturnId, first.supplierReturnId);
      expect(replay.supplierTransactionId, isNull);
    });

    test('U) provider sticky key retries with same idempotency key', () async {
      final spyService = _CountingSupplierReturnService(db);
      final container = ProviderContainer(
        overrides: [
          supplierReturnReadRepositoryProvider
              .overrideWithValue(SupplierReturnReadRepository(db)),
          supplierReturnServiceProvider.overrideWithValue(spyService),
        ],
      );
      addTearDown(container.dispose);

      final purchase = SupplierReturnPurchaseOption(
        purchaseInvoiceId: invoiceId,
        supplierId: supplierId,
        supplierName: 'B15 Supplier',
        invoiceNumber: 'PI-B15',
        purchaseDate: DateTime(2026, 3, 1),
        totalAmount: 100,
        status: 'CONFIRMED',
      );

      final notifier = container.read(supplierReturnDraftProvider.notifier);
      await notifier.selectPurchase(purchase);
      notifier.setLineQuantity(purchaseItemId, 2);

      final firstOk = await notifier.submitReturn();
      expect(firstOk, isFalse);
      expect(spyService.postCalls, 1);
      expect(spyService.keysUsed, hasLength(1));

      final secondOk = await notifier.submitReturn();
      expect(secondOk, isTrue);
      expect(spyService.postCalls, 2);
      expect(spyService.keysUsed, hasLength(2));
      expect(spyService.keysUsed[0], spyService.keysUsed[1]);
    });

    test('V) empty lines rejects before idempotency record', () async {
      final key = b15SupplierReturnIdempotencyKey();
      await expectLater(
        service.postPurchaseLinkedReturn(
          idempotencyKey: key,
          input: SupplierReturnPostingInput(
            supplierId: supplierId,
            purchaseInvoiceId: invoiceId,
            lines: const [],
          ),
        ),
        throwsA(
          isA<SupplierReturnPostingException>().having(
            (e) => e.code,
            'code',
            SupplierReturnPostingFailure.emptyLines,
          ),
        ),
      );
      expect(await idempotencyRowCount(), 0);
      expect(await supplierReturnCount(), 0);
    });

    test('W) independent operations use unique keys and do not replay', () async {
      final key1 = b15SupplierReturnIdempotencyKey();
      final key2 = b15SupplierReturnIdempotencyKey();
      expect(key1, isNot(equals(key2)));

      final first = await postSupplierReturn(
        service,
        postingInput(),
        idempotencyKey: key1,
      );
      final second = await postSupplierReturn(
        service,
        postingInput(
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItemId,
              quantity: 1,
            ),
          ],
        ),
        idempotencyKey: key2,
      );

      expect(first.idempotentReplay, isFalse);
      expect(second.idempotentReplay, isFalse);
      expect(first.supplierReturnId, isNot(equals(second.supplierReturnId)));
      expect(await supplierReturnCount(), 2);
      expect(await idempotencyRowCount(), 2);
      expect(await returnOutLedgerCount(), 2);
      expect(await supplierReturnTxnCount(), 2);
    });
  });
}