import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/supplier_refund_test_keys.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/supplier_refund_settlement_service.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  late AppDatabase db;
  late SupplierRefundSettlementService settlementService;
  late int supplierId;

  setUp(() async {
    db = AppDatabase.test();
    settlementService = SupplierRefundSettlementService(db);

    supplierId = await db.into(db.suppliers).insert(
          const SuppliersCompanion(name: Value('Idempotency Supplier')),
        );
  });

  tearDown(() async {
    await db.close();
  });

  Future<double> balance([AppDatabase? database, int? sid]) {
    final target = database ?? db;
    return target.supplierAccountsDao.getBalance(sid ?? supplierId);
  }

  Future<int> refundTxnCount([AppDatabase? database, int? sid]) async {
    final target = database ?? db;
    final rows = await (target.select(target.supplierTransactions)
          ..where((t) =>
              t.supplierId.equals(sid ?? supplierId) & t.type.equals('REFUND')))
        .get();
    return rows.length;
  }

  Future<int> idempotencyRowCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.supplierRefundIdempotency).get()).length;
  }

  Future<void> seedCredit100([AppDatabase? database, int? sid]) async {
    final target = database ?? db;
    final supplier = sid ?? supplierId;
    await target.supplierAccountsDao.recordReturnInTransaction(
      supplierId: supplier,
      amount: 100,
      returnId: 999,
      note: 'shared credit seed',
    );
    expect(await balance(target, supplier), closeTo(-100, 0.001));
  }

  Future<int> insertSupplierReturnHeader(
    AppDatabase database, {
    String suffix = 'A',
  }) {
    return database.into(database.supplierReturns).insert(
          SupplierReturnsCompanion(
            supplierId: Value(supplierId),
            returnNumber: Value(
              'SRI-$suffix-${DateTime.now().microsecondsSinceEpoch}',
            ),
          ),
        );
  }

  Future<bool> idempotencyTableExists(AppDatabase database) async {
    final rows = await database.customSelect(
      '''
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'supplier_refund_idempotency'
      ''',
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> idempotencyIndexExists(AppDatabase database) async {
    final rows = await database.customSelect(
      '''
      SELECT name FROM sqlite_master
      WHERE type = 'index' AND name = 'sri_supplier_created_idx'
      ''',
    ).get();
    return rows.isNotEmpty;
  }

  Future<sqlite3.Database> openSimulatedV34RawDatabase() async {
    final rawDb = sqlite3.sqlite3.openInMemory();
    final bootstrap = AppDatabase.test(NativeDatabase.opened(rawDb));
    await bootstrap.close();
    rawDb.execute('DROP TABLE IF EXISTS supplier_refund_idempotency');
    rawDb.execute('DROP INDEX IF EXISTS sri_supplier_created_idx');
    rawDb.userVersion = 34;
    return rawDb;
  }

  group('SR Step 2.1 supplier refund idempotency', () {
    test('A) first refund creates REFUND and idempotency row', () async {
      await seedCredit100();
      final key = supplierRefundTestIdempotencyKey();

      final first = await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 40,
        idempotencyKey: key,
        note: 'first attempt',
      );

      expect(first.idempotentReplay, isFalse);
      expect(await refundTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await balance(), closeTo(-60, 0.001));
    });

    test('B) same key sequential replay', () async {
      await seedCredit100();
      final key = supplierRefundTestIdempotencyKey();

      final first = await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 40,
        idempotencyKey: key,
        note: 'first attempt',
      );
      final second = await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 40,
        idempotencyKey: key,
        note: 'first attempt',
      );

      expect(first.idempotentReplay, isFalse);
      expect(second.idempotentReplay, isTrue);
      expect(second.supplierTransactionId, first.supplierTransactionId);
      expect(await refundTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('C) same key different amount conflicts with zero second mutation',
        () async {
      await seedCredit100();
      final key = supplierRefundTestIdempotencyKey();
      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 40,
        idempotencyKey: key,
      );

      await expectLater(
        settlementService.settleCredit(
          supplierId: supplierId,
          amount: 50,
          idempotencyKey: key,
        ),
        throwsA(
          isA<SupplierRefundSettlementException>().having(
            (e) => e.code,
            'code',
            SupplierRefundSettlementFailure.idempotencyKeyConflict,
          ),
        ),
      );

      expect(await refundTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await balance(), closeTo(-60, 0.001));
    });

    test('D) same key different supplier conflicts', () async {
      await seedCredit100();
      final otherSupplierId = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('Other Supplier')),
          );
      await seedCredit100(db, otherSupplierId);
      final key = supplierRefundTestIdempotencyKey();

      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 20,
        idempotencyKey: key,
      );

      await expectLater(
        settlementService.settleCredit(
          supplierId: otherSupplierId,
          amount: 20,
          idempotencyKey: key,
        ),
        throwsA(
          isA<SupplierRefundSettlementException>().having(
            (e) => e.code,
            'code',
            SupplierRefundSettlementFailure.idempotencyKeyConflict,
          ),
        ),
      );

      expect(await refundTxnCount(), 1);
      expect(await refundTxnCount(db, otherSupplierId), 0);
      expect(await idempotencyRowCount(), 1);
    });

    test('E) same key different returnId conflicts', () async {
      await seedCredit100();
      final returnIdA = await insertSupplierReturnHeader(db, suffix: 'A');
      final returnIdB = await insertSupplierReturnHeader(db, suffix: 'B');
      final key = supplierRefundTestIdempotencyKey();

      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 20,
        idempotencyKey: key,
        returnId: returnIdA,
      );

      await expectLater(
        settlementService.settleCredit(
          supplierId: supplierId,
          amount: 20,
          idempotencyKey: key,
          returnId: returnIdB,
        ),
        throwsA(
          isA<SupplierRefundSettlementException>().having(
            (e) => e.code,
            'code',
            SupplierRefundSettlementFailure.idempotencyKeyConflict,
          ),
        ),
      );

      expect(await refundTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('F) different keys K1=50 and K2=30 against credit 100', () async {
      await seedCredit100();
      final keyA = supplierRefundTestIdempotencyKey();
      final keyB = supplierRefundTestIdempotencyKey();

      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 50,
        idempotencyKey: keyA,
      );
      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 30,
        idempotencyKey: keyB,
      );

      expect(await refundTxnCount(), 2);
      expect(await idempotencyRowCount(), 2);
      expect(await balance(), closeTo(-20, 0.001));
    });

    test('G) replay returns original supplierTransactionId', () async {
      await seedCredit100();
      final key = supplierRefundTestIdempotencyKey();
      final original = await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 15,
        idempotencyKey: key,
        note: 'stable note',
      );
      final replay = await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 15,
        idempotencyKey: key,
        note: 'stable note',
      );

      expect(replay.idempotentReplay, isTrue);
      expect(replay.supplierTransactionId, original.supplierTransactionId);
    });

    test('H) cash ledger after first and replay has one SUPPLIER_REFUND event',
        () async {
      await seedCredit100();
      final key = supplierRefundTestIdempotencyKey();
      const ledgerFilter = CashLedgerFilter(
        page: 0,
        pageSize: 1000,
        dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
      );
      final ledger = FinancialLedgerRepository(db);

      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 35,
        idempotencyKey: key,
        note: 'ledger op',
      );
      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 35,
        idempotencyKey: key,
        note: 'ledger op',
      );

      final refundLedgerEvents = (await ledger.getEntries(ledgerFilter))
          .entries
          .where((e) => e.eventType == CashLedgerEventType.supplierRefund)
          .toList();
      expect(refundLedgerEvents.length, 1);
      expect(refundLedgerEvents.single.amount, 35);
    });

    test('I) concurrent same-key two connections', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}sri_${DateTime.now().microsecondsSinceEpoch}.db';
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

      final serviceA = SupplierRefundSettlementService(dbA);
      final serviceB = SupplierRefundSettlementService(dbB);

      final sid = await dbA.into(dbA.suppliers).insert(
            const SuppliersCompanion(name: Value('Concurrent Idempotency')),
          );
      await dbA.supplierAccountsDao.recordReturnInTransaction(
        supplierId: sid,
        amount: 100,
        returnId: 999,
        note: 'shared credit seed',
      );

      final sharedKey = supplierRefundTestIdempotencyKey();
      final results = await Future.wait<SupplierRefundSettlementResult>([
        serviceA.settleCredit(
          supplierId: sid,
          amount: 60,
          idempotencyKey: sharedKey,
        ),
        serviceB.settleCredit(
          supplierId: sid,
          amount: 60,
          idempotencyKey: sharedKey,
        ),
      ]);

      expect(await refundTxnCount(dbA, sid), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(results.map((r) => r.supplierTransactionId).toSet().length, 1);
      expect(results.where((r) => r.idempotentReplay).length, 1);
      expect(results.where((r) => !r.idempotentReplay).length, 1);
    });

    test('J) migration v34 to v35 and fresh install schema v35 include table',
        () async {
      final rawDb = await openSimulatedV34RawDatabase();
      addTearDown(rawDb.dispose);

      expect(rawDb.userVersion, 34);
      final before = rawDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='supplier_refund_idempotency'",
      );
      expect(before, isEmpty);

      final migrated = AppDatabase.test(NativeDatabase.opened(rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 35);
      expect(await idempotencyTableExists(migrated), isTrue);
      expect(await idempotencyIndexExists(migrated), isTrue);

      expect(db.schemaVersion, 35);
      expect(await idempotencyTableExists(db), isTrue);
      expect(await idempotencyIndexExists(db), isTrue);
    });
  });
}
