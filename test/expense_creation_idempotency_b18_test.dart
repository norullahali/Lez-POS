import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/expense_creation_fingerprint.dart';
import 'package:lez_pos/core/services/expense_creation_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/expense_creation_result.dart';
import 'package:lez_pos/core/services/expense_creation_service.dart';
import 'package:lez_pos/features/auth/providers/auth_provider.dart';
import 'package:lez_pos/features/expenses/expense_submit_idempotency.dart';
import 'package:lez_pos/features/expenses/models/expense_category.dart'
    as expense_models;
import 'package:lez_pos/features/expenses/models/expense_record.dart' as models;
import 'package:lez_pos/features/expenses/providers/expense_creation_service_provider.dart';
import 'package:lez_pos/features/expenses/providers/expense_providers.dart';
import 'package:lez_pos/features/expenses/screens/widgets/expense_dialog.dart';
import 'package:lez_pos/features/expenses/repositories/expense_repository.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/expense_creation_test_keys.dart';

class _CountingExpenseCreationService extends ExpenseCreationService {
  _CountingExpenseCreationService(
    AppDatabase database, {
    Completer<void>? saveGate,
  })  : _saveGate = saveGate,
        super(database);

  final Completer<void>? _saveGate;
  bool throwConflict = false;
  bool throwOnce = false;
  int createCalls = 0;
  final List<String> keysUsed = [];

  @override
  Future<ExpenseCreationResult> processCreate({
    required String idempotencyKey,
    required String fingerprintHash,
    required int categoryId,
    required double amount,
    required DateTime expenseDate,
    required DateTime paidAt,
    required String notes,
    required int createdBy,
    int? sessionId,
  }) async {
    createCalls++;
    keysUsed.add(idempotencyKey);
    if (throwOnce) {
      throwOnce = false;
      throw Exception('forced create failure');
    }
    if (throwConflict) {
      throw const ExpenseCreationIdempotencyConflictException();
    }
    if (_saveGate != null) {
      await _saveGate!.future;
    }
    return ExpenseCreationResult(
      expenseRecordId: 9001,
      idempotentReplay: false,
    );
  }
}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(this._user);

  final User _user;

  @override
  FutureOr<AuthState> build() async => AuthState(user: _user);
}

User _b39TestUser(int id) => User(
      id: id,
      fullName: 'B39 User',
      username: 'b39user',
      passwordHash: 'hash',
      roleId: 1,
      isActive: true,
      refundLimit: 100000,
      createdAt: DateTime(2026, 1, 1),
    );

List<Override> _b39CreateUiOverrides({
  required _CountingExpenseCreationService spy,
  required int categoryId,
  required int userId,
}) {
  return [
    expenseCreationServiceProvider.overrideWithValue(spy),
    authProvider.overrideWith(() => _TestAuthNotifier(_b39TestUser(userId))),
    expenseCategoriesProvider.overrideWith(
      (ref) async => [
        expense_models.ExpenseCategory(
          id: categoryId,
          name: 'B39 Category',
          isActive: true,
        ),
      ],
    ),
  ];
}

Future<void> _pumpExpenseCreateDialog(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: ExpenseDialog(),
        ),
      ),
    ),
  );
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final auth = container.read(authProvider);
    if (auth.hasValue &&
        auth.requireValue.user != null &&
        find.byType(DropdownButtonFormField<int>).evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _selectB39Category(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<int>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('B39 Category').last);
  await tester.pumpAndSettle();
}

Finder _expenseAmountField() =>
    find.byKey(const Key('expense_dialog_amount'));

Future<void> _flushExpenseDialogUi(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  });
  await tester.pump();
}

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
  // Keep aligned with AppDatabase.schemaVersion (lib/core/database/app_database.dart).

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
      await repository.voidExpenseForTest(
        idempotencyKey: b18ExpenseCreationIdempotencyKey(),
        expenseId: created.expenseRecordId,
        voidedBy: userId,
      );
      expect(await expenseLedgerCountForId(created.expenseRecordId), 0);
    });

    test('14) edit after create keeps single ledger row for expense ID', () async {
      final created = await postExpense(idempotencyKey: b18ExpenseCreationIdempotencyKey(), amount: 80);
      final row = await db.expensesDao.getExpenseById(created.expenseRecordId);
      expect(row, isNotNull);

      await repository.updateExpenseForTest(
        idempotencyKey: b18ExpenseCreationIdempotencyKey(),
        updatedBy: userId,
        record: models.ExpenseRecord(
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

      expect(migrated.schemaVersion, 51);
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

  group('B39 expense submit runner', () {
    test('skips second submit while in flight', () async {
      final runner = ExpenseSubmitRunner();
      final gate = Completer<void>();
      final intent = ExpenseSubmitIntent.create(
        categoryId: 1,
        amount: 50,
        expenseDate: _DateHelper.d,
        paidAt: _DateHelper.d,
        notes: 'n',
        sessionId: null,
        createdBy: 1,
      );
      var calls = 0;

      final firstFuture = runner.submit(
        intent: intent,
        idempotencyKey: 'key-a',
        isSubmitStillCurrent: () => true,
        invokeService: (_) async {
          calls++;
          await gate.future;
        },
        postSuccessRefresh: () async {},
      );

      final second = await runner.submit(
        intent: intent,
        idempotencyKey: 'key-a',
        isSubmitStillCurrent: () => true,
        invokeService: (_) async {
          calls++;
        },
        postSuccessRefresh: () async {},
      );

      expect(second, ExpenseSubmitOutcome.skippedInFlight);
      gate.complete();
      await firstFuture;
      expect(calls, 1);
    });

    test('stale completion skips post-success refresh', () async {
      final runner = ExpenseSubmitRunner();
      var current = true;
      var refreshCalls = 0;
      final intent = ExpenseSubmitIntent.create(
        categoryId: 1,
        amount: 50,
        expenseDate: _DateHelper.d,
        paidAt: _DateHelper.d,
        notes: 'stale',
        sessionId: null,
        createdBy: 1,
      );

      final outcome = await runner.submit(
        intent: intent,
        idempotencyKey: 'key-stale',
        isSubmitStillCurrent: () => current,
        invokeService: (_) async {
          current = false;
        },
        postSuccessRefresh: () async {
          refreshCalls++;
        },
      );

      expect(outcome, ExpenseSubmitOutcome.staleCompletion);
      expect(refreshCalls, 0);
    });
  });

  group('B39 expense dialog UI idempotency — create', () {
    late AppDatabase uiDb;
    late int uiCategoryId;
    late int uiUserId;
    late _CountingExpenseCreationService spy;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      ExpenseDialog.resetExpenseSubmitTestingHooks();
      uiDb = AppDatabase.test();
      uiUserId = await uiDb.into(uiDb.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'B39 UI User',
              username: 'b39ui_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      uiCategoryId = await uiDb.expensesDao.createCategory(
        const ExpenseCategoriesCompanion(
          name: Value('B39 Category'),
          isActive: Value(true),
        ),
      );
      spy = _CountingExpenseCreationService(uiDb);
    });

    tearDown(() async {
      ExpenseDialog.resetExpenseSubmitTestingHooks();
      await uiDb.close();
    });

    Future<ProviderContainer> openDialog(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: _b39CreateUiOverrides(
          spy: spy,
          categoryId: uiCategoryId,
          userId: uiUserId,
        ),
      );
      addTearDown(container.dispose);
      await _pumpExpenseCreateDialog(tester, container);
      await _selectB39Category(tester);
      await tester.enterText(_expenseAmountField(), '100');
      await tester.pump();
      return container;
    }

    testWidgets('duplicate in-flight create invokes processCreate once',
        (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      spy = _CountingExpenseCreationService(uiDb, saveGate: gate);
      await openDialog(tester);

      final save = find.byKey(const Key('expense_dialog_save'));
      await tester.tap(save);
      await _flushExpenseDialogUi(tester);
      expect(spy.createCalls, 1);
      expect(tester.widget<ElevatedButton>(save).onPressed, isNull);

      gate.complete();
      await _flushExpenseDialogUi(tester);
    });

    testWidgets('stale completion does not close dialog or refresh',
        (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      spy = _CountingExpenseCreationService(uiDb, saveGate: gate);

      await openDialog(tester);

      await tester.tap(find.byKey(const Key('expense_dialog_save')));
      await _flushExpenseDialogUi(tester);
      expect(spy.createCalls, 1);
      ExpenseDialog.invalidateSubmitGenerationForTesting();
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseDialog), findsOneWidget);
      expect(ExpenseDialog.postSuccessRefreshCount, 0);
      expect(
        find.text('تم تجاهل نتيجة حفظ سابقة بعد تغيير البيانات.'),
        findsOneWidget,
      );
    });

    testWidgets('success closes dialog and refreshes once', (tester) async {
      await openDialog(tester);

      await tester.tap(find.byKey(const Key('expense_dialog_save')));
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseDialog), findsNothing);
      expect(spy.createCalls, 1);
      expect(ExpenseDialog.postSuccessRefreshCount, 1);
    });

    testWidgets('conflict clears key for next attempt', (tester) async {
      spy.throwConflict = true;
      await openDialog(tester);

      await tester.tap(find.byKey(const Key('expense_dialog_save')));
      await tester.pumpAndSettle();

      spy.throwConflict = false;
      await tester.tap(find.byKey(const Key('expense_dialog_save')));
      await tester.pumpAndSettle();

      expect(spy.createCalls, 2);
      expect(spy.keysUsed.length, 2);
      expect(spy.keysUsed[0], isNot(spy.keysUsed[1]));
    });

    testWidgets('service failure retry reuses same key', (tester) async {
      spy.throwOnce = true;
      await openDialog(tester);

      await tester.tap(find.byKey(const Key('expense_dialog_save')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('expense_dialog_save')));
      await tester.pumpAndSettle();

      expect(spy.createCalls, 2);
      expect(spy.keysUsed.length, 2);
      expect(spy.keysUsed[0], spy.keysUsed[1]);
    });

    testWidgets('refresh failure retains key then succeeds', (tester) async {
      ExpenseDialog.failNextPostSuccessRefreshForTesting = true;
      await openDialog(tester);

      await tester.tap(find.byKey(const Key('expense_dialog_save')));
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseDialog), findsOneWidget);
      expect(
        find.text('تم حفظ المصروف، لكن تعذر تحديث العرض. أعد المحاولة.'),
        findsOneWidget,
      );

      ExpenseDialog.failNextPostSuccessRefreshForTesting = false;
      await tester.tap(find.byKey(const Key('expense_dialog_save')));
      await tester.pumpAndSettle();

      expect(spy.createCalls, 2);
      expect(spy.keysUsed[0], spy.keysUsed[1]);
      expect(find.byType(ExpenseDialog), findsNothing);
    });

    testWidgets('intent fields disabled while saving', (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      spy = _CountingExpenseCreationService(uiDb, saveGate: gate);

      await openDialog(tester);

      await tester.tap(find.byKey(const Key('expense_dialog_save')));
      await _flushExpenseDialogUi(tester);
      expect(spy.createCalls, 1);

      final amountField = tester.widget<TextFormField>(_expenseAmountField());
      expect(amountField.enabled, isFalse);

      gate.complete();
      await _flushExpenseDialogUi(tester);
    });
  });
}

class _DateHelper {
  static final d = DateTime(2026, 3, 15);
}
