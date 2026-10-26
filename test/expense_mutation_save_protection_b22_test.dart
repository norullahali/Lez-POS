import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/activity/activity_types.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/expense_creation_fingerprint.dart';
import 'package:lez_pos/core/services/expense_creation_service.dart';
import 'package:lez_pos/core/services/expense_mutation_fingerprint.dart';
import 'package:lez_pos/core/services/expense_mutation_save_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/expense_mutation_save_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/expense_creation_test_keys.dart';
import 'support/expense_mutation_save_test_keys.dart';

Future<({sqlite3.Database rawDb, String path})> openSimulatedV48RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b22_v48_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement(
    'DROP TABLE IF EXISTS expense_mutation_idempotency',
  );
  await bootstrap.customStatement('DROP INDEX IF EXISTS emi_expense_record_idx');
  await bootstrap.customStatement('PRAGMA user_version = 48');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 48);
  return (rawDb: rawDb, path: dbPath);
}

Future<({
  AppDatabase dbA,
  AppDatabase dbB,
  String path,
})> openDualConnectionRaceDatabases() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b22_race_${DateTime.now().microsecondsSinceEpoch}.db';
  final rawA = sqlite3.sqlite3.open(dbPath);
  final rawB = sqlite3.sqlite3.open(dbPath);
  rawA.execute('PRAGMA busy_timeout = 15000');
  rawB.execute('PRAGMA busy_timeout = 15000');
  return (
    dbA: AppDatabase.test(NativeDatabase.opened(rawA)),
    dbB: AppDatabase.test(NativeDatabase.opened(rawB)),
    path: dbPath,
  );
}

void main() {
  // Keep aligned with AppDatabase.schemaVersion (lib/core/database/app_database.dart).
  const kExpectedAppSchemaVersion = 51;

  late AppDatabase db;
  late ExpenseCreationService createService;
  late ExpenseMutationSaveService mutationService;
  late int categoryId;
  late int userId;
  late DateTime expenseDate;
  late DateTime paidAt;

  setUp(() async {
    db = AppDatabase.test();
    createService = ExpenseCreationService(db);
    mutationService = ExpenseMutationSaveService(db);
    userId = await db.into(db.usersTable).insert(
          UsersTableCompanion.insert(
            fullName: 'B22 User',
            username: 'b22_${DateTime.now().microsecondsSinceEpoch}',
            passwordHash: 'hash',
            roleId: 1,
          ),
        );
    categoryId = await db.expensesDao.createCategory(
      const ExpenseCategoriesCompanion(
        name: Value('B22 Category'),
        isActive: Value(true),
      ),
    );
    expenseDate = DateTime(2026, 4, 10);
    paidAt = DateTime(2026, 4, 11);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> createExpense({double amount = 100}) async {
    final key = b18ExpenseCreationIdempotencyKey();
    final fp = ExpenseCreationFingerprint.compute(
      categoryId: categoryId,
      amount: amount,
      expenseDate: expenseDate,
      paidAt: paidAt,
      notes: 'seed',
      createdBy: userId,
    );
    final r = await createService.processCreate(
      idempotencyKey: key,
      fingerprintHash: fp,
      categoryId: categoryId,
      amount: amount,
      expenseDate: expenseDate,
      paidAt: paidAt,
      notes: 'seed',
      createdBy: userId,
    );
    return r.expenseRecordId;
  }

  String updateFp(int expenseId, {double amount = 120, int? sessionId}) =>
      ExpenseMutationFingerprint.computeUpdate(
        expenseId: expenseId,
        categoryId: categoryId,
        amount: amount,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'updated',
        updatedBy: userId,
        sessionId: sessionId,
      );

  String voidFp(int expenseId) => ExpenseMutationFingerprint.computeVoid(
        expenseId: expenseId,
        voidedBy: userId,
      );

  Future<int> mutationIdempotencyCount([AppDatabase? target]) async {
    final d = target ?? db;
    return (await d.select(d.expenseMutationIdempotency).get()).length;
  }

  Future<int> activityLogCount([AppDatabase? target]) async {
    final d = target ?? db;
    return (await d.select(d.activityLogs).get()).length;
  }

  Future<double> summaryTotal([AppDatabase? target]) async {
    final d = target ?? db;
    final s = await d.expensesDao.getExpenseSummary();
    return s.$2;
  }

  Future<int> activityCountForType(String activityType, [AppDatabase? target]) async {
    final d = target ?? db;
    final rows = await d.select(d.activityLogs).get();
    return rows.where((r) => r.activityType == activityType).length;
  }

  Future<({
    int expenseId,
    int uid,
    int categoryId,
  })> seedExpenseOnDualDb({
    required AppDatabase dbA,
    double amount = 50,
  }) async {
    final uid = await dbA.into(dbA.usersTable).insert(
          UsersTableCompanion.insert(
            fullName: 'Race',
            username: 'race_${DateTime.now().microsecondsSinceEpoch}',
            passwordHash: 'hash',
            roleId: 1,
          ),
        );
    final cid = await dbA.expensesDao.createCategory(
      const ExpenseCategoriesCompanion(name: Value('C'), isActive: Value(true)),
    );
    final createKey = b18ExpenseCreationIdempotencyKey();
    final createFp = ExpenseCreationFingerprint.compute(
      categoryId: cid,
      amount: amount,
      expenseDate: expenseDate,
      paidAt: paidAt,
      notes: 'seed',
      createdBy: uid,
    );
    final created = await ExpenseCreationService(dbA).processCreate(
      idempotencyKey: createKey,
      fingerprintHash: createFp,
      categoryId: cid,
      amount: amount,
      expenseDate: expenseDate,
      paidAt: paidAt,
      notes: 'seed',
      createdBy: uid,
    );
    return (
      expenseId: created.expenseRecordId,
      uid: uid,
      categoryId: cid,
    );
  }

  group('B22 expense mutation save protection', () {
    test('1) update success', () async {
      final expenseId = await createExpense();
      final key = b22ExpenseMutationIdempotencyKey();
      final fp = updateFp(expenseId);
      final result = await mutationService.processUpdate(
        idempotencyKey: key,
        fingerprintHash: fp,
        expenseId: expenseId,
        categoryId: categoryId,
        amount: 120,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'updated',
        updatedBy: userId,
      );
      expect(result.idempotentReplay, isFalse);
      final row = await db.expensesDao.getExpenseById(expenseId);
      expect(row!.amount, 120);
      expect(await mutationIdempotencyCount(), 1);
      expect(await activityLogCount(), greaterThan(1));
    });

    test('2) update same-key replay', () async {
      final expenseId = await createExpense();
      final key = b22ExpenseMutationIdempotencyKey();
      final fp = updateFp(expenseId);
      await mutationService.processUpdate(
        idempotencyKey: key,
        fingerprintHash: fp,
        expenseId: expenseId,
        categoryId: categoryId,
        amount: 120,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'updated',
        updatedBy: userId,
      );
      final logsAfterFirst = await activityLogCount();
      final replay = await mutationService.processUpdate(
        idempotencyKey: key,
        fingerprintHash: fp,
        expenseId: expenseId,
        categoryId: categoryId,
        amount: 120,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'updated',
        updatedBy: userId,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(await activityLogCount(), logsAfterFirst);
      expect(await mutationIdempotencyCount(), 1);
    });

    test('3) update same-key conflict', () async {
      final expenseId = await createExpense();
      final key = b22ExpenseMutationIdempotencyKey();
      await mutationService.processUpdate(
        idempotencyKey: key,
        fingerprintHash: updateFp(expenseId, amount: 110),
        expenseId: expenseId,
        categoryId: categoryId,
        amount: 110,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'updated',
        updatedBy: userId,
      );
      await expectLater(
        mutationService.processUpdate(
          idempotencyKey: key,
          fingerprintHash: updateFp(expenseId, amount: 999),
          expenseId: expenseId,
          categoryId: categoryId,
          amount: 999,
          expenseDate: expenseDate,
          paidAt: paidAt,
          notes: 'updated',
          updatedBy: userId,
        ),
        throwsA(isA<ExpenseMutationSaveIdempotencyConflictException>()),
      );
      expect((await db.expensesDao.getExpenseById(expenseId))!.amount, 110);
    });

    test('4) different keys sequential updates', () async {
      final expenseId = await createExpense();
      await mutationService.processUpdate(
        idempotencyKey: b22ExpenseMutationIdempotencyKey(),
        fingerprintHash: updateFp(expenseId, amount: 110),
        expenseId: expenseId,
        categoryId: categoryId,
        amount: 110,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'a',
        updatedBy: userId,
      );
      await mutationService.processUpdate(
        idempotencyKey: b22ExpenseMutationIdempotencyKey(),
        fingerprintHash: updateFp(expenseId, amount: 130),
        expenseId: expenseId,
        categoryId: categoryId,
        amount: 130,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'b',
        updatedBy: userId,
      );
      expect((await db.expensesDao.getExpenseById(expenseId))!.amount, 130);
      expect(await mutationIdempotencyCount(), 2);
    });

    test('5) update rollback on activity log failure', () async {
      final expenseId = await createExpense();
      final flaky = ExpenseMutationSaveService(
        db,
        testActivityLogHook: () async {
          throw StateError('forced activity failure');
        },
      );
      await expectLater(
        flaky.processUpdate(
          idempotencyKey: b22ExpenseMutationIdempotencyKey(),
          fingerprintHash: updateFp(expenseId),
          expenseId: expenseId,
          categoryId: categoryId,
          amount: 120,
          expenseDate: expenseDate,
          paidAt: paidAt,
          notes: 'updated',
          updatedBy: userId,
        ),
        throwsA(isA<StateError>()),
      );
      expect((await db.expensesDao.getExpenseById(expenseId))!.amount, 100);
      expect(await mutationIdempotencyCount(), 0);
    });

    test('6) update seal failure then retry', () async {
      final expenseId = await createExpense();
      final key = b22ExpenseMutationIdempotencyKey();
      final fp = updateFp(expenseId);
      final flaky = ExpenseMutationSaveService(
        db,
        preSealHook: () async {
          throw StateError('forced seal failure');
        },
      );
      await expectLater(
        flaky.processUpdate(
          idempotencyKey: key,
          fingerprintHash: fp,
          expenseId: expenseId,
          categoryId: categoryId,
          amount: 120,
          expenseDate: expenseDate,
          paidAt: paidAt,
          notes: 'updated',
          updatedBy: userId,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await mutationIdempotencyCount(), 0);
      await mutationService.processUpdate(
        idempotencyKey: key,
        fingerprintHash: fp,
        expenseId: expenseId,
        categoryId: categoryId,
        amount: 120,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'updated',
        updatedBy: userId,
      );
      expect(await mutationIdempotencyCount(), 1);
    });

    test('7) dual-connection same-key update', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        File(opened.path).deleteSync();
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Race',
              username: 'race_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final cid = await opened.dbA.expensesDao.createCategory(
        const ExpenseCategoriesCompanion(name: Value('C'), isActive: Value(true)),
      );
      final createKey = b18ExpenseCreationIdempotencyKey();
      final createFp = ExpenseCreationFingerprint.compute(
        categoryId: cid,
        amount: 50,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'x',
        createdBy: uid,
      );
      final created = await ExpenseCreationService(opened.dbA).processCreate(
        idempotencyKey: createKey,
        fingerprintHash: createFp,
        categoryId: cid,
        amount: 50,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'x',
        createdBy: uid,
      );
      final sameKey = b22ExpenseMutationIdempotencyKey();
      final fp = ExpenseMutationFingerprint.computeUpdate(
        expenseId: created.expenseRecordId,
        categoryId: cid,
        amount: 75,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'u',
        updatedBy: uid,
      );
      final release = Completer<void>();
      final serviceA = ExpenseMutationSaveService(
        opened.dbA,
        preSealHook: () async => release.future,
      );
      final serviceB = ExpenseMutationSaveService(opened.dbB);
      final fA = serviceA.processUpdate(
        idempotencyKey: sameKey,
        fingerprintHash: fp,
        expenseId: created.expenseRecordId,
        categoryId: cid,
        amount: 75,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'u',
        updatedBy: uid,
      );
      final fB = serviceB.processUpdate(
        idempotencyKey: sameKey,
        fingerprintHash: fp,
        expenseId: created.expenseRecordId,
        categoryId: cid,
        amount: 75,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'u',
        updatedBy: uid,
      );
      release.complete();
      final outcomes = await Future.wait([fA, fB]);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(await mutationIdempotencyCount(opened.dbA), 1);
      expect(
        (await opened.dbA.expensesDao.getExpenseById(created.expenseRecordId))!
            .amount,
        75,
      );
    });

    test('8) update amount and summary total', () async {
      final expenseId = await createExpense(amount: 80);
      expect(await summaryTotal(), 80);
      await mutationService.processUpdate(
        idempotencyKey: b22ExpenseMutationIdempotencyKey(),
        fingerprintHash: updateFp(expenseId, amount: 95),
        expenseId: expenseId,
        categoryId: categoryId,
        amount: 95,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'updated',
        updatedBy: userId,
      );
      expect(await summaryTotal(), 95);
    });

    test('9) void success', () async {
      final expenseId = await createExpense();
      final result = await mutationService.processVoid(
        idempotencyKey: b22ExpenseMutationIdempotencyKey(),
        fingerprintHash: voidFp(expenseId),
        expenseId: expenseId,
        voidedBy: userId,
      );
      expect(result.alreadyVoided, isFalse);
      expect((await db.expensesDao.getExpenseById(expenseId))!.isVoided, isTrue);
      expect(await summaryTotal(), 0);
      expect(await mutationIdempotencyCount(), 1);
    });

    test('10) void same-key replay', () async {
      final expenseId = await createExpense();
      final key = b22ExpenseMutationIdempotencyKey();
      final fp = voidFp(expenseId);
      await mutationService.processVoid(
        idempotencyKey: key,
        fingerprintHash: fp,
        expenseId: expenseId,
        voidedBy: userId,
      );
      final logs = await activityLogCount();
      final replay = await mutationService.processVoid(
        idempotencyKey: key,
        fingerprintHash: fp,
        expenseId: expenseId,
        voidedBy: userId,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(await activityLogCount(), logs);
    });

    test('11) void same-key conflict', () async {
      final expenseId = await createExpense();
      final key = b22ExpenseMutationIdempotencyKey();
      await mutationService.processVoid(
        idempotencyKey: key,
        fingerprintHash: voidFp(expenseId),
        expenseId: expenseId,
        voidedBy: userId,
      );
      await expectLater(
        mutationService.processVoid(
          idempotencyKey: key,
          fingerprintHash: ExpenseMutationFingerprint.computeVoid(
            expenseId: expenseId,
            voidedBy: userId + 999,
          ),
          expenseId: expenseId,
          voidedBy: userId + 999,
        ),
        throwsA(isA<ExpenseMutationSaveIdempotencyConflictException>()),
      );
    });

    test('12) void already voided different key', () async {
      final expenseId = await createExpense();
      await mutationService.processVoid(
        idempotencyKey: b22ExpenseMutationIdempotencyKey(),
        fingerprintHash: voidFp(expenseId),
        expenseId: expenseId,
        voidedBy: userId,
      );
      final logs = await activityLogCount();
      final second = await mutationService.processVoid(
        idempotencyKey: b22ExpenseMutationIdempotencyKey(),
        fingerprintHash: voidFp(expenseId),
        expenseId: expenseId,
        voidedBy: userId,
      );
      expect(second.alreadyVoided, isTrue);
      expect(await activityLogCount(), logs);
      expect(await mutationIdempotencyCount(), 1);
    });

    test('13) void rollback activity failure', () async {
      final expenseId = await createExpense();
      final flaky = ExpenseMutationSaveService(
        db,
        testActivityLogHook: () async {
          throw StateError('forced void log failure');
        },
      );
      await expectLater(
        flaky.processVoid(
          idempotencyKey: b22ExpenseMutationIdempotencyKey(),
          fingerprintHash: voidFp(expenseId),
          expenseId: expenseId,
          voidedBy: userId,
        ),
        throwsA(isA<StateError>()),
      );
      expect((await db.expensesDao.getExpenseById(expenseId))!.isVoided, isFalse);
    });

    test('14) void seal failure retry', () async {
      final expenseId = await createExpense();
      final key = b22ExpenseMutationIdempotencyKey();
      final fp = voidFp(expenseId);
      final flaky = ExpenseMutationSaveService(
        db,
        preSealHook: () async {
          throw StateError('seal fail');
        },
      );
      await expectLater(
        flaky.processVoid(
          idempotencyKey: key,
          fingerprintHash: fp,
          expenseId: expenseId,
          voidedBy: userId,
        ),
        throwsA(isA<StateError>()),
      );
      await mutationService.processVoid(
        idempotencyKey: key,
        fingerprintHash: fp,
        expenseId: expenseId,
        voidedBy: userId,
      );
      expect(await mutationIdempotencyCount(), 1);
    });

    test('15) update after void rejected', () async {
      final expenseId = await createExpense();
      await mutationService.processVoid(
        idempotencyKey: b22ExpenseMutationIdempotencyKey(),
        fingerprintHash: voidFp(expenseId),
        expenseId: expenseId,
        voidedBy: userId,
      );
      await expectLater(
        mutationService.processUpdate(
          idempotencyKey: b22ExpenseMutationIdempotencyKey(),
          fingerprintHash: updateFp(expenseId),
          expenseId: expenseId,
          categoryId: categoryId,
          amount: 200,
          expenseDate: expenseDate,
          paidAt: paidAt,
          notes: 'nope',
          updatedBy: userId,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('16) service rejects updatedBy 0', () async {
      final expenseId = await createExpense();
      await expectLater(
        mutationService.processUpdate(
          idempotencyKey: b22ExpenseMutationIdempotencyKey(),
          fingerprintHash: 'x',
          expenseId: expenseId,
          categoryId: categoryId,
          amount: 120,
          expenseDate: expenseDate,
          paidAt: paidAt,
          notes: 'x',
          updatedBy: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('17) service rejects voidedBy 0', () async {
      final expenseId = await createExpense();
      await expectLater(
        mutationService.processVoid(
          idempotencyKey: b22ExpenseMutationIdempotencyKey(),
          fingerprintHash: 'x',
          expenseId: expenseId,
          voidedBy: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('18) migration v48 to v49', () async {
      final opened = await openSimulatedV48RawDatabase();
      addTearDown(opened.rawDb.dispose);
      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());
      expect(migrated.schemaVersion, kExpectedAppSchemaVersion);
      final tables = await migrated.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='expense_mutation_idempotency'",
      ).get();
      expect(tables.length, 1);
    });

    test('19) fresh schema 51', () async {
      expect(db.schemaVersion, kExpectedAppSchemaVersion);
    });

    test('21) dual-connection update vs void concurrency', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        File(opened.path).deleteSync();
      });

      final seed = await seedExpenseOnDualDb(dbA: opened.dbA, amount: 50);
      final updateKey = b22ExpenseMutationIdempotencyKey();
      final voidKey = b22ExpenseMutationIdempotencyKey();
      const updatedAmount = 75.0;

      final updateAtBarrier = Completer<void>();
      final releaseUpdate = Completer<void>();

      final updateService = ExpenseMutationSaveService(
        opened.dbA,
        beforeMutationHook: () async {
          if (!updateAtBarrier.isCompleted) updateAtBarrier.complete();
          await releaseUpdate.future;
        },
      );
      final voidService = ExpenseMutationSaveService(opened.dbB);

      final updateFuture = updateService.processUpdate(
        idempotencyKey: updateKey,
        fingerprintHash: ExpenseMutationFingerprint.computeUpdate(
          expenseId: seed.expenseId,
          categoryId: seed.categoryId,
          amount: updatedAmount,
          expenseDate: expenseDate,
          paidAt: paidAt,
          notes: 'race-update',
          updatedBy: seed.uid,
        ),
        expenseId: seed.expenseId,
        categoryId: seed.categoryId,
        amount: updatedAmount,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'race-update',
        updatedBy: seed.uid,
      );

      await updateAtBarrier.future;

      await voidService.processVoid(
        idempotencyKey: voidKey,
        fingerprintHash: ExpenseMutationFingerprint.computeVoid(
          expenseId: seed.expenseId,
          voidedBy: seed.uid,
        ),
        expenseId: seed.expenseId,
        voidedBy: seed.uid,
      );

      releaseUpdate.complete();

      await expectLater(updateFuture, throwsA(isA<StateError>()));

      final row =
          await opened.dbA.expensesDao.getExpenseById(seed.expenseId);
      expect(row!.isVoided, isTrue);
      expect(row.amount, 50);
      expect(await mutationIdempotencyCount(opened.dbA), 1);
      expect(await summaryTotal(opened.dbA), 0);
      expect(
        await activityCountForType(ActivityTypes.expenseVoided, opened.dbA),
        1,
      );
      expect(
        await activityCountForType(ActivityTypes.expenseUpdated, opened.dbA),
        0,
      );
    });

    test('22) dual-connection void vs update concurrency', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        File(opened.path).deleteSync();
      });

      final seed = await seedExpenseOnDualDb(dbA: opened.dbA, amount: 50);
      final voidKey = b22ExpenseMutationIdempotencyKey();
      final updateKey = b22ExpenseMutationIdempotencyKey();
      const updatedAmount = 75.0;

      final voidAtBarrier = Completer<void>();
      final releaseVoid = Completer<void>();

      final voidService = ExpenseMutationSaveService(
        opened.dbA,
        beforeMutationHook: () async {
          if (!voidAtBarrier.isCompleted) voidAtBarrier.complete();
          await releaseVoid.future;
        },
      );
      final updateService = ExpenseMutationSaveService(opened.dbB);

      final voidFuture = voidService.processVoid(
        idempotencyKey: voidKey,
        fingerprintHash: ExpenseMutationFingerprint.computeVoid(
          expenseId: seed.expenseId,
          voidedBy: seed.uid,
        ),
        expenseId: seed.expenseId,
        voidedBy: seed.uid,
      );

      await voidAtBarrier.future;

      await updateService.processUpdate(
        idempotencyKey: updateKey,
        fingerprintHash: ExpenseMutationFingerprint.computeUpdate(
          expenseId: seed.expenseId,
          categoryId: seed.categoryId,
          amount: updatedAmount,
          expenseDate: expenseDate,
          paidAt: paidAt,
          notes: 'race-update',
          updatedBy: seed.uid,
        ),
        expenseId: seed.expenseId,
        categoryId: seed.categoryId,
        amount: updatedAmount,
        expenseDate: expenseDate,
        paidAt: paidAt,
        notes: 'race-update',
        updatedBy: seed.uid,
      );

      releaseVoid.complete();
      await voidFuture;

      final row =
          await opened.dbA.expensesDao.getExpenseById(seed.expenseId);
      expect(row!.isVoided, isTrue);
      expect(row.amount, updatedAmount);
      expect(await mutationIdempotencyCount(opened.dbA), 2);
      expect(await summaryTotal(opened.dbA), 0);
      expect(
        await activityCountForType(ActivityTypes.expenseUpdated, opened.dbA),
        1,
      );
      expect(
        await activityCountForType(ActivityTypes.expenseVoided, opened.dbA),
        1,
      );
    });

    test('20) real UNIQUE on mutation idempotency', () async {
      final key = b22ExpenseMutationIdempotencyKey();
      await db.expenseMutationIdempotencyDao.insertCompletedRecord(
        idempotencyKey: key,
        operationType: ExpenseMutationFingerprint.operationUpdate,
        fingerprintHash: 'fp1',
        expenseRecordId: 1,
      );
      await expectLater(
        db.expenseMutationIdempotencyDao.insertCompletedRecord(
          idempotencyKey: key,
          operationType: ExpenseMutationFingerprint.operationUpdate,
          fingerprintHash: 'fp2',
          expenseRecordId: 2,
        ),
        throwsA(
          predicate<SqliteException>(
            (e) =>
                e.extendedResultCode == 1555 ||
                e.extendedResultCode == 2067,
          ),
        ),
      );
    });
  });
}
