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
          const SuppliersCompanion(name: Value('Aggregate Supplier')),
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

  Future<double> refundTotal([AppDatabase? database, int? sid]) async {
    final target = database ?? db;
    final rows = await (target.select(target.supplierTransactions)
          ..where((t) =>
              t.supplierId.equals(sid ?? supplierId) & t.type.equals('REFUND')))
        .get();
    return rows.fold<double>(0, (sum, row) => sum + row.amount);
  }

  Future<int> idempotencyRowCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.supplierRefundIdempotency).get()).length;
  }

  Future<void> seedCredit(
    double credit, [
    AppDatabase? database,
    int? sid,
  ]) async {
    final target = database ?? db;
    final supplier = sid ?? supplierId;
    await target.supplierAccountsDao.recordReturnInTransaction(
      supplierId: supplier,
      amount: credit,
      returnId: 999,
      note: 'aggregate credit seed',
    );
    expect(await balance(target, supplier), closeTo(-credit, 0.001));
  }

  group('SR Step 2.2 supplier aggregate credit concurrency', () {
    test('A) two concurrent different-key refunds - only one succeeds',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}sr22a_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 5000');
      rawB.execute('PRAGMA busy_timeout = 5000');
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
            const SuppliersCompanion(name: Value('Concurrent Aggregate')),
          );
      await dbA.supplierAccountsDao.recordReturnInTransaction(
        supplierId: sid,
        amount: 100,
        returnId: 999,
        note: 'shared credit seed',
      );

      final key1 = supplierRefundTestIdempotencyKey();
      final key2 = supplierRefundTestIdempotencyKey();
      const ledgerFilter = CashLedgerFilter(
        page: 0,
        pageSize: 1000,
        dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
      );
      final ledger = FinancialLedgerRepository(dbA);

      final outcomes = await Future.wait<Object?>([
        () async {
          try {
            return await serviceA.settleCredit(
              supplierId: sid,
              amount: 70,
              idempotencyKey: key1,
            );
          } on SupplierRefundSettlementException catch (e) {
            return e.code;
          }
        }(),
        () async {
          try {
            return await serviceB.settleCredit(
              supplierId: sid,
              amount: 70,
              idempotencyKey: key2,
            );
          } on SupplierRefundSettlementException catch (e) {
            return e.code;
          }
        }(),
      ]);

      final successes = outcomes.whereType<SupplierRefundSettlementResult>();
      final failures = outcomes.whereType<SupplierRefundSettlementFailure>();

      expect(successes.length, 1);
      expect(failures.length, 1);
      expect(
        failures.single,
        SupplierRefundSettlementFailure.amountExceedsCredit,
      );

      expect(await refundTxnCount(dbA, sid), 1);
      expect(await refundTotal(dbA, sid), lessThanOrEqualTo(100));
      expect(await refundTotal(dbA, sid), 70);
      expect(await balance(dbA, sid), closeTo(-30, 0.001));
      expect(await idempotencyRowCount(dbA), 1);

      final refundLedgerEvents = (await ledger.getEntries(ledgerFilter))
          .entries
          .where((e) => e.eventType == CashLedgerEventType.supplierRefund)
          .toList();
      expect(refundLedgerEvents.length, 1);
      expect(refundLedgerEvents.single.amount, 70);
    });

    test('B) DAO guarded insert rejects second insert in same transaction',
        () async {
      await seedCredit(100);
      try {
        await db.transaction(() async {
          final first = await db.supplierAccountsDao
              .recordRefundInTransactionIfWithinAggregateCredit(
            supplierId: supplierId,
            amount: 70,
          );
          final second = await db.supplierAccountsDao
              .recordRefundInTransactionIfWithinAggregateCredit(
            supplierId: supplierId,
            amount: 70,
          );
          expect(first, isNotNull);
          expect(second, isNull);
          throw StateError('rollback probe');
        });
      } on StateError catch (_) {
        // expected rollback
      }
      expect(await refundTxnCount(), 0);
      expect(await balance(), closeTo(-100, 0.001));
    });

    test('C) sequential different-key refunds within aggregate credit',
        () async {
      await seedCredit(100);
      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 60,
        idempotencyKey: supplierRefundTestIdempotencyKey(),
      );
      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 40,
        idempotencyKey: supplierRefundTestIdempotencyKey(),
      );

      expect(await refundTxnCount(), 2);
      expect(await refundTotal(), closeTo(100, 0.001));
      expect(await balance(), closeTo(0, 0.001));
      expect(await idempotencyRowCount(), 2);
    });

    test('D) refund exceeding aggregate credit is rejected', () async {
      await seedCredit(50);
      await expectLater(
        settlementService.settleCredit(
          supplierId: supplierId,
          amount: 60,
          idempotencyKey: supplierRefundTestIdempotencyKey(),
        ),
        throwsA(
          isA<SupplierRefundSettlementException>().having(
            (e) => e.code,
            'code',
            SupplierRefundSettlementFailure.amountExceedsCredit,
          ),
        ),
      );

      expect(await refundTxnCount(), 0);
      expect(await idempotencyRowCount(), 0);
      expect(await balance(), closeTo(-50, 0.001));
    });

    test('E) refund exactly equal to aggregate credit succeeds', () async {
      await seedCredit(50);
      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 50,
        idempotencyKey: supplierRefundTestIdempotencyKey(),
      );

      expect(await refundTxnCount(), 1);
      expect(await balance(), closeTo(0, 0.001));
    });

    test('F) idempotent replay after credit depletion', () async {
      await seedCredit(100);
      const ledgerFilter = CashLedgerFilter(
        page: 0,
        pageSize: 1000,
        dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
      );
      final ledger = FinancialLedgerRepository(db);
      final key = supplierRefundTestIdempotencyKey();

      final original = await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 100,
        idempotencyKey: key,
        note: 'full credit refund',
      );
      expect(original.idempotentReplay, isFalse);
      expect(await balance(), closeTo(0, 0.001));

      final replay = await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 100,
        idempotencyKey: key,
        note: 'full credit refund',
      );

      expect(replay.idempotentReplay, isTrue);
      expect(replay.supplierTransactionId, original.supplierTransactionId);
      expect(await refundTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);

      final refundLedgerEvents = (await ledger.getEntries(ledgerFilter))
          .entries
          .where((e) => e.eventType == CashLedgerEventType.supplierRefund)
          .toList();
      expect(refundLedgerEvents.length, 1);
      expect(refundLedgerEvents.single.amount, 100);
    });
  });
}
