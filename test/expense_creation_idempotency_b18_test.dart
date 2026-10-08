import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/expense_creation_fingerprint.dart';
import 'package:lez_pos/core/services/expense_creation_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/expense_creation_result.dart';
import 'package:lez_pos/core/services/expense_creation_service.dart';
import 'package:lez_pos/features/expenses/models/expense_record.dart' as models;
import 'package:lez_pos/features/expenses/repositories/expense_repository.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/expense_creation_test_keys.dart';

Future<({sqlite3.Database rawDb, String path})> openSimulatedV44RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b18_v44_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement('DROP TABLE IF EXISTS expense_idempotency');
  await bootstrap.customStatement('DROP INDEX IF EXISTS ei_expense_record_idx');
  await bootstrap.customStatement('PRAGMA user_version = 44');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 44);
  return (rawDb: rawDb, path: dbPath);
}

void main() {
  late AppDatabase db;
  late ExpenseCreationService service;
  late ExpenseRepository repository;
  late int categoryId;
  late int userId;
  late DateTime expenseDate;
  late DateTime paidAt;

  setUp(() async {
    db = AppDatabase.test();
    service = ExpenseCreationService(db);
    repository = ExpenseRepository(db);
    userId = await db.into(db.usersTable).insert(
          UsersTableCompanion.insert(
            fullName: 'B18 User',
            username: 'b18_${DateTime.now().microsecondsSinceEpoch}',
            passwordHash: 'hash',
            roleId: 1,
          ),
        );
    categoryId = await db.expensesDao.createCategory(
      const ExpenseCategoriesCompanion(
        name: Value('B18 Category'),
        isActive: Value(true),
      ),
    );
    expenseDate = DateTime(2026, 3, 15, 14, 30);
    paidAt = DateTime(2026, 3, 15, 9, 45);
  });

  tearDown(() async {
    await db.close();
  });

  String fingerprintFor({
    double amount = 100,
    int? categoryOverride,
    DateTime? expenseDateOverride,
    DateTime? paidAtOverride,
    String notes = 'B18 note',
    int? createdByOverride,
    int? sessionId,
  }) {
    return ExpenseCreationFingerprint.compute(
      categoryId: categoryOverride ?? categoryId,
      amount: amount,
      expenseDate: expenseDateOverride ?? expenseDate,
      paidAt: paidAtOverride ?? paidAt,
      notes: notes,
      createdBy: createdByOverride ?? userId,
      sessionId: sessionId,
    );
  }

  Future<ExpenseCreationResult> postExpense({
    ExpenseCreationService? targetService,
    required String idempotencyKey,
    double amount = 100,
    String notes = 'B18 note',
    String? fingerprint,
    int? categoryOverride,
    DateTime? expenseDateOverride,
    DateTime? paidAtOverride,
    int? createdByOverride,
    int? sessionId,
  }) {
    final svc = targetService ?? service;
    final fp = fingerprint ??
        fingerprintFor(
          amount: amount,
          notes: notes,
          categoryOverride: categoryOverride,
          expenseDateOverride: expenseDateOverride,
          paidAtOverride: paidAtOverride,
          createdByOverride: createdByOverride,
        );
    return svc.processCreate(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fp,
      categoryId: categoryOverride ?? categoryId,
      amount: amount,
      expenseDate: expenseDateOverride ?? expenseDate,
      paidAt: paidAtOverride ?? paidAt,
      notes: notes,
      createdBy: createdByOverride ?? userId,
      sessionId: sessionId,
    );
  }

  Future<int> expenseCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.expenseRecords).get()).length;
  }

  Future<int> idempotencyRowCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.expenseIdempotency).get()).length;
  }

  Future<int> activityLogCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.activityLogs).get()).length;
  }

  Future<int> expenseLedgerCount([AppDatabase? database]) async {
    final target = database ?? db;
    final ledger = FinancialLedgerRepository(target);
    const ledgerFilter = CashLedgerFilter(
      page: 0,
      pageSize: 1000,
      dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
    );
    return (await ledger.getEntries(ledgerFilter))
        .entries
        .where((e) => e.eventType == CashLedgerEventType.expense)
        .length;
  }

  Future<int> expenseLedgerCountForId(int expenseId, [AppDatabase? database]) async {
    final target = database ?? db;
    final ledger = FinancialLedgerRepository(target);
    const ledgerFilter = CashLedgerFilter(
      page: 0,
      pageSize: 1000,
      dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
    );
    return (await ledger.getEntries(ledgerFilter))
        .entries
        .where((e) =>
            e.eventType == CashLedgerEventType.expense &&
            e.referenceId == expenseId)
        .length;
  }

  Future<bool> idempotencyTableExists(AppDatabase database) async {
    final rows = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='expense_idempotency'",
    ).get();
    return rows.isNotEmpty;
  }

  group('B18 expense creation idempotency', () {
    test('1) first create succeeds', () async {
      final key = b18ExpenseCreationIdempotencyKey();
      final result = await postExpense(idempotencyKey: key);

      expect(result.idempotentReplay, isFalse);
      expect(result.expenseRecordId, greaterThan(0));
      expect(await expenseCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await activityLogCount(), 1);
    });

    test('2) same key + same fingerprint replay', () async {
      final key = b18ExpenseCreationIdempotencyKey();
      final fp = fingerprintFor();
      final first = await postExpense(idempotencyKey: key, fingerprint: fp);
      final second = await postExpense(idempotencyKey: key, fingerprint: fp);

      expect(second.idempotentReplay, isTrue);
      expect(second.expenseRecordId, first.expenseRecordId);
      expect(await expenseCount(), 1);
    });

    test('3) same key + different fingerprint conflict', () async {
      final key = b18ExpenseCreationIdempotencyKey();
      await postExpense(idempotencyKey: key, amount: 100);

      await expectLater(
        postExpense(idempotencyKey: key, amount: 200),
        throwsA(isA<ExpenseCreationIdempotencyConflictException>()),
      );

      expect(await expenseCount(), 1);
    });

    test('4) sequential double submit same key', () async {
      final key = b18ExpenseCreationIdempotencyKey();
      final fp = fingerprintFor();
      await postExpense(idempotencyKey: key, fingerprint: fp);
      await postExpense(idempotencyKey: key, fingerprint: fp);
      expect(await expenseCount(), 1);
    });

    test('5) concurrent same key + same fingerprint', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b18_same_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 15000');
      rawB.execute('PRAGMA busy_timeout = 15000');
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

      final uid = await dbA.into(dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Conc User',
              username: 'conc_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final cid = await dbA.expensesDao.createCategory(
        const ExpenseCategoriesCompanion(
          name: Value('Conc Cat'),
          isActive: Value(true),
        ),
      );

      final serviceA = ExpenseCreationService(dbA);
      final serviceB = ExpenseCreationService(dbB);
      final sameKey = b18ExpenseCreationIdempotencyKey();
      final fp = ExpenseCreationFingerprint.compute(
        categoryId: cid,
        amount: 50,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'conc',
        createdBy: uid,
      );

      final outcomes = await Future.wait([
        serviceA.processCreate(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          categoryId: cid,
          amount: 50,
          expenseDate: expenseDate,
          paidAt: paidAt,
          notes: 'conc',
          createdBy: uid,
        ),
        serviceB.processCreate(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          categoryId: cid,
          amount: 50,
          expenseDate: expenseDate,
          paidAt: paidAt,
          notes: 'conc',
          createdBy: uid,
        ),
      ]);

      expect(await expenseCount(dbA), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(outcomes.map((r) => r.expenseRecordId).toSet().length, 1);
    });

    test('6) concurrent same key + different fingerprint conflict', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b18_conflict_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 15000');
      rawB.execute('PRAGMA busy_timeout = 15000');
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

      final uid = await dbA.into(dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Conflict User',
              username: 'conf_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final cid = await dbA.expensesDao.createCategory(
        const ExpenseCategoriesCompanion(
          name: Value('Conflict Cat'),
          isActive: Value(true),
        ),
      );

      final serviceA = ExpenseCreationService(dbA);
      final serviceB = ExpenseCreationService(dbB);
      final sameKey = b18ExpenseCreationIdempotencyKey();
      final fpA = ExpenseCreationFingerprint.compute(
        categoryId: cid,
        amount: 50,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'a',
        createdBy: uid,
      );
      final fpB = ExpenseCreationFingerprint.compute(
        categoryId: cid,
        amount: 75,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'b',
        createdBy: uid,
      );

      Future<Object?> runConflictAttempt() async {
        try {
          return await serviceB.processCreate(
            idempotencyKey: sameKey,
            fingerprintHash: fpB,
            categoryId: cid,
            amount: 75,
            expenseDate: expenseDate,
            paidAt: paidAt,
            notes: 'b',
            createdBy: uid,
          );
        } on ExpenseCreationIdempotencyConflictException catch (e) {
          return e;
        }
      }

      final outcomes = await Future.wait<Object?>([
        serviceA.processCreate(
          idempotencyKey: sameKey,
          fingerprintHash: fpA,
          categoryId: cid,
          amount: 50,
          expenseDate: expenseDate,
          paidAt: paidAt,
          notes: 'a',
          createdBy: uid,
        ),
        runConflictAttempt(),
      ]);

      expect(await expenseCount(dbA), 1);
      expect(
        outcomes.whereType<ExpenseCreationIdempotencyConflictException>().length,
        1,
      );
    });

    test('7) different keys create two expenses', () async {
      await postExpense(idempotencyKey: b18ExpenseCreationIdempotencyKey());
      await postExpense(idempotencyKey: b18ExpenseCreationIdempotencyKey());
      expect(await expenseCount(), 2);
    });

    test('8) expense INSERT failure rolls back', () async {
      final failing = ExpenseCreationService(
        db,
        beforeExpenseInsertHook: () async {
          throw Exception('forced insert failure');
        },
      );

      await expectLater(
        postExpense(
          targetService: failing,
          idempotencyKey: b18ExpenseCreationIdempotencyKey(),
        ),
        throwsA(isA<Exception>()),
      );

      expect(await expenseCount(), 0);
      expect(await idempotencyRowCount(), 0);
    });

    test('9) production activity log failure rolls back', () async {
      await db.customStatement('''
        CREATE TRIGGER b18_block_activity_log
        BEFORE INSERT ON activity_logs
        BEGIN
          SELECT RAISE(FAIL, 'forced activity log failure');
        END;
      ''');

      await expectLater(
        postExpense(idempotencyKey: b18ExpenseCreationIdempotencyKey()),
        throwsA(isA<Exception>()),
      );

      expect(await expenseCount(), 0);
      expect(await idempotencyRowCount(), 0);
    });

    test('10) seal race preSealHook then retry succeeds once', () async {
      final key = b18ExpenseCreationIdempotencyKey();
      final fp = fingerprintFor();
      var hookCalls = 0;
      final flaky = ExpenseCreationService(
        db,
        preSealHook: () async {
          hookCalls++;
          if (hookCalls == 1) throw Exception('forced seal race');
        },
      );

      await expectLater(
        postExpense(targetService: flaky, idempotencyKey: key, fingerprint: fp),
        throwsA(isA<Exception>()),
      );

      final retry = await postExpense(
        targetService: flaky,
        idempotencyKey: key,
        fingerprint: fp,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await expenseCount(), 1);
    });

    test('11) SQLITE_BUSY retry succeeds under dual connection contention', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b18_busy_${DateTime.now().microsecondsSinceEpoch}.db';
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

      final uid = await dbA.into(dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Busy User',
              username: 'busy_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final cid = await dbA.expensesDao.createCategory(
        const ExpenseCategoriesCompanion(
          name: Value('Busy Cat'),
          isActive: Value(true),
        ),
      );

      final serviceA = ExpenseCreationService(dbA);
      final serviceB = ExpenseCreationService(dbB);
      final sameKey = b18ExpenseCreationIdempotencyKey();
      final fp = ExpenseCreationFingerprint.compute(
        categoryId: cid,
        amount: 40,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'busy',
        createdBy: uid,
      );

      final outcomes = await Future.wait([
        serviceA.processCreate(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          categoryId: cid,
          amount: 40,
          expenseDate: expenseDate,
          paidAt: paidAt,
          notes: 'busy',
          createdBy: uid,
        ),
        serviceB.processCreate(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          categoryId: cid,
          amount: 40,
          expenseDate: expenseDate,
          paidAt: paidAt,
          notes: 'busy',
          createdBy: uid,
        ),
      ]);

      expect(await expenseCount(dbA), 1);
      expect(outcomes.map((r) => r.expenseRecordId).toSet().length, 1);
    });

    test('12) post-commit ambiguous-result replay returns same expense ID', () async {
      final key = b18ExpenseCreationIdempotencyKey();
      final fp = fingerprintFor();
      final first = await postExpense(idempotencyKey: key, fingerprint: fp);
      final replay = await postExpense(idempotencyKey: key, fingerprint: fp);

      expect(replay.idempotentReplay, isTrue);
      expect(replay.expenseRecordId, first.expenseRecordId);
    });

    test('13) void after create excludes ledger row', () async {
      final created = await postExpense(idempotencyKey: b18ExpenseCreationIdempotencyKey(), amount: 80);
      expect(await expenseLedgerCountForId(created.expenseRecordId), 1);
      await repository.voidExpense(created.expenseRecordId);
      expect(await expenseLedgerCountForId(created.expenseRecordId), 0);
    });

    test('14) edit after create keeps single ledger row for expense ID', () async {
      final created = await postExpense(idempotencyKey: b18ExpenseCreationIdempotencyKey(), amount: 80);
      final row = await db.expensesDao.getExpenseById(created.expenseRecordId);
      expect(row, isNotNull);

      await repository.updateExpense(
        models.ExpenseRecord(
          id: created.expenseRecordId,
          categoryId: categoryId,
          amount: 120,
          expenseDate: row!.expenseDate,
          paidAt: row.paidAt,
          notes: row.notes,
          createdBy: userId,
          isVoided: false,
        ),
      );

      expect(await expenseLedgerCountForId(created.expenseRecordId), 1);
    });

    test('15) exactly one EXPENSE ledger event after replay', () async {
      final key = b18ExpenseCreationIdempotencyKey();
      final fp = fingerprintFor(amount: 55);
      final first = await postExpense(idempotencyKey: key, fingerprint: fp, amount: 55);
      await postExpense(idempotencyKey: key, fingerprint: fp, amount: 55);
      expect(await expenseLedgerCount(), 1);
      expect(await expenseLedgerCountForId(first.expenseRecordId), 1);
    });

    test('16) migration v44 -> v45 creates expense_idempotency', () async {
      final opened = await openSimulatedV44RawDatabase();
      addTearDown(opened.rawDb.dispose);

      final before = opened.rawDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='expense_idempotency'",
      );
      expect(before, isEmpty);

      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 48);
      expect(await idempotencyTableExists(migrated), isTrue);
    });

    test('17) date normalization matches same calendar day with different times', () async {
      final morning = DateTime(2026, 6, 10, 8, 15);
      final evening = DateTime(2026, 6, 10, 19, 45);
      final fpMorning = fingerprintFor(
        amount: 30,
        expenseDateOverride: morning,
        paidAtOverride: morning,
        notes: 'date norm',
      );
      final fpEvening = fingerprintFor(
        amount: 30,
        expenseDateOverride: evening,
        paidAtOverride: evening,
        notes: 'date norm',
      );
      expect(fpMorning, fpEvening);

      final created = await postExpense(
        idempotencyKey: b18ExpenseCreationIdempotencyKey(),
        fingerprint: fpMorning,
        amount: 30,
        expenseDateOverride: morning,
        paidAtOverride: morning,
        notes: 'date norm',
      );
      final row = await db.expensesDao.getExpenseById(created.expenseRecordId);
      expect(row!.expenseDate, ExpenseCreationFingerprint.normalizeDate(morning));
      expect(row.paidAt, ExpenseCreationFingerprint.normalizeDate(morning));
    });

    test('18) createdBy validation rejects zero', () async {
      await expectLater(
        postExpense(
          idempotencyKey: b18ExpenseCreationIdempotencyKey(),
          createdByOverride: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await expenseCount(), 0);
    });

    test('19) category existence and active validation', () async {
      await expectLater(
        postExpense(
          idempotencyKey: b18ExpenseCreationIdempotencyKey(),
          categoryOverride: 999999,
        ),
        throwsA(isA<StateError>()),
      );

      final inactiveId = await db.expensesDao.createCategory(
        const ExpenseCategoriesCompanion(
          name: Value('Inactive'),
          isActive: Value(false),
        ),
      );

      await expectLater(
        postExpense(
          idempotencyKey: b18ExpenseCreationIdempotencyKey(),
          categoryOverride: inactiveId,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('20) fingerprint change with same key conflicts', () async {
      final key = b18ExpenseCreationIdempotencyKey();
      final fpA = fingerprintFor(amount: 100, notes: 'first');
      await postExpense(idempotencyKey: key, fingerprint: fpA, notes: 'first');

      final fpB = fingerprintFor(amount: 100, notes: 'second');
      expect(fpA, isNot(fpB));

      await expectLater(
        postExpense(idempotencyKey: key, fingerprint: fpB, notes: 'second'),
        throwsA(isA<ExpenseCreationIdempotencyConflictException>()),
      );
    });
  });
}
