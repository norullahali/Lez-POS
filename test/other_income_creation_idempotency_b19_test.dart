import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/other_income_creation_fingerprint.dart';
import 'package:lez_pos/core/services/other_income_creation_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/other_income_creation_result.dart';
import 'package:lez_pos/core/services/other_income_creation_service.dart';
import 'package:lez_pos/features/auth/providers/auth_provider.dart';
import 'package:lez_pos/features/other_income/models/other_income_category.dart'
    as oi_cat;
import 'package:lez_pos/features/other_income/models/other_income_record.dart' as models;
import 'package:lez_pos/features/other_income/other_income_submit_idempotency.dart';
import 'package:lez_pos/features/other_income/providers/other_income_creation_service_provider.dart';
import 'package:lez_pos/features/other_income/providers/other_income_providers.dart';
import 'package:lez_pos/features/other_income/repositories/other_income_repository.dart';
import 'package:lez_pos/features/other_income/screens/widgets/other_income_dialog.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/other_income_creation_test_keys.dart';

class _CountingOtherIncomeCreationService extends OtherIncomeCreationService {
  _CountingOtherIncomeCreationService(
    AppDatabase database, {
    Completer<void>? saveGate,
  })  : _saveGate = saveGate,
        super(database);

  final Completer<void>? _saveGate;
  bool throwConflict = false;
  bool throwOnce = false;
  int createCalls = 0;
  final List<String> keysUsed = [];
  int? lastSessionId;

  @override
  Future<OtherIncomeCreationResult> processCreate({
    required String idempotencyKey,
    required String fingerprintHash,
    required int categoryId,
    required double amount,
    required DateTime incomeDate,
    required DateTime receivedAt,
    required String notes,
    required int createdBy,
    int? sessionId,
  }) async {
    createCalls++;
    keysUsed.add(idempotencyKey);
    lastSessionId = sessionId;
    if (throwOnce) {
      throwOnce = false;
      throw Exception('forced create failure');
    }
    if (throwConflict) {
      throw const OtherIncomeCreationIdempotencyConflictException();
    }
    if (_saveGate != null) {
      await _saveGate!.future;
    }
    return OtherIncomeCreationResult(
      otherIncomeRecordId: 9001,
      idempotentReplay: false,
    );
  }
}

class _B40CreateAuthNotifier extends AuthNotifier {
  _B40CreateAuthNotifier(this._user);

  final User _user;

  @override
  FutureOr<AuthState> build() async => AuthState(user: _user);
}

User _b40TestUser(int id) => User(
      id: id,
      fullName: 'B40 User',
      username: 'b40user',
      passwordHash: 'hash',
      roleId: 1,
      isActive: true,
      refundLimit: 100000,
      createdAt: DateTime(2026, 1, 1),
    );

List<Override> _b40CreateUiOverrides({
  required _CountingOtherIncomeCreationService spy,
  required int categoryId,
  required int userId,
}) {
  return [
    otherIncomeCreationServiceProvider.overrideWithValue(spy),
    authProvider.overrideWith(() => _B40CreateAuthNotifier(_b40TestUser(userId))),
    otherIncomeCategoriesProvider.overrideWith(
      (ref) async => [
        oi_cat.OtherIncomeCategory(
          id: categoryId,
          name: 'B40 Category',
          isActive: true,
        ),
      ],
    ),
  ];
}

Future<void> _pumpOtherIncomeCreateDialog(
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
          body: OtherIncomeDialog(),
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

Future<void> _selectB40Category(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<int>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('B40 Category').last);
  await tester.pumpAndSettle();
}

Finder _otherIncomeAmountField() =>
    find.byKey(const Key('other_income_dialog_amount'));

Future<void> _flushOtherIncomeDialogUi(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  });
  await tester.pump();
}

Future<({sqlite3.Database rawDb, String path})> openSimulatedV45RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b19_v44_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement('DROP TABLE IF EXISTS other_income_idempotency');
  await bootstrap.customStatement('DROP INDEX IF EXISTS oii_other_income_record_idx');
  await bootstrap.customStatement('PRAGMA user_version = 45');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 45);
  return (rawDb: rawDb, path: dbPath);
}

void main() {
  // Keep aligned with AppDatabase.schemaVersion (lib/core/database/app_database.dart).

  late AppDatabase db;
  late OtherIncomeCreationService service;
  late OtherIncomeRepository repository;
  late int categoryId;
  late int userId;
  late DateTime incomeDate;
  late DateTime receivedAt;

  setUp(() async {
    db = AppDatabase.test();
    service = OtherIncomeCreationService(db);
    repository = OtherIncomeRepository(db);
    userId = await db.into(db.usersTable).insert(
          UsersTableCompanion.insert(
            fullName: 'B19 User',
            username: 'b19_${DateTime.now().microsecondsSinceEpoch}',
            passwordHash: 'hash',
            roleId: 1,
          ),
        );
    categoryId = await db.otherIncomeDao.createCategory(
      const OtherIncomeCategoriesCompanion(
        name: Value('B19 Category'),
        isActive: Value(true),
      ),
    );
    incomeDate = DateTime(2026, 3, 15, 14, 30);
    receivedAt = DateTime(2026, 3, 15, 9, 45);
  });

  tearDown(() async {
    await db.close();
  });

  String fingerprintFor({
    double amount = 100,
    int? categoryOverride,
    DateTime? incomeDateOverride,
    DateTime? receivedAtOverride,
    String notes = 'B19 note',
    int? createdByOverride,
    int? sessionId,
  }) {
    return OtherIncomeCreationFingerprint.compute(
      categoryId: categoryOverride ?? categoryId,
      amount: amount,
      incomeDate: incomeDateOverride ?? incomeDate,
      receivedAt: receivedAtOverride ?? receivedAt,
      notes: notes,
      createdBy: createdByOverride ?? userId,
      sessionId: sessionId,
    );
  }

  Future<OtherIncomeCreationResult> postIncome({
    OtherIncomeCreationService? targetService,
    required String idempotencyKey,
    double amount = 100,
    String notes = 'B19 note',
    String? fingerprint,
    int? categoryOverride,
    DateTime? incomeDateOverride,
    DateTime? receivedAtOverride,
    int? createdByOverride,
    int? sessionId,
  }) {
    final svc = targetService ?? service;
    final fp = fingerprint ??
        fingerprintFor(
          amount: amount,
          notes: notes,
          categoryOverride: categoryOverride,
          incomeDateOverride: incomeDateOverride,
          receivedAtOverride: receivedAtOverride,
          createdByOverride: createdByOverride,
        );
    return svc.processCreate(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fp,
      categoryId: categoryOverride ?? categoryId,
      amount: amount,
      incomeDate: incomeDateOverride ?? incomeDate,
      receivedAt: receivedAtOverride ?? receivedAt,
      notes: notes,
      createdBy: createdByOverride ?? userId,
      sessionId: sessionId,
    );
  }

  Future<int> incomeCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.otherIncomeRecords).get()).length;
  }

  Future<int> idempotencyRowCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.otherIncomeIdempotency).get()).length;
  }

  Future<int> activityLogCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.activityLogs).get()).length;
  }

  Future<int> otherIncomeLedgerCount([AppDatabase? database]) async {
    final target = database ?? db;
    final ledger = FinancialLedgerRepository(target);
    const ledgerFilter = CashLedgerFilter(
      page: 0,
      pageSize: 1000,
      dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
    );
    return (await ledger.getEntries(ledgerFilter))
        .entries
        .where((e) => e.eventType == CashLedgerEventType.otherIncome)
        .length;
  }

  Future<int> otherIncomeLedgerCountForId(int incomeId, [AppDatabase? database]) async {
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
            e.eventType == CashLedgerEventType.otherIncome &&
            e.referenceId == incomeId)
        .length;
  }

  Future<bool> idempotencyTableExists(AppDatabase database) async {
    final rows = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='other_income_idempotency'",
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> idempotencyIndexExists(AppDatabase database) async {
    final rows = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='index' AND name='oii_other_income_record_idx'",
    ).get();
    return rows.isNotEmpty;
  }

  group('B19 other income creation idempotency', () {
    test('1) first create succeeds', () async {
      final key = b19OtherIncomeCreationIdempotencyKey();
      final result = await postIncome(idempotencyKey: key);

      expect(result.idempotentReplay, isFalse);
      expect(result.otherIncomeRecordId, greaterThan(0));
      expect(await incomeCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await activityLogCount(), 1);
    });

    test('2) same key + same fingerprint replay', () async {
      final key = b19OtherIncomeCreationIdempotencyKey();
      final fp = fingerprintFor();
      final first = await postIncome(idempotencyKey: key, fingerprint: fp);
      final second = await postIncome(idempotencyKey: key, fingerprint: fp);

      expect(second.idempotentReplay, isTrue);
      expect(second.otherIncomeRecordId, first.otherIncomeRecordId);
      expect(await incomeCount(), 1);
    });

    test('3) same key + different fingerprint conflict', () async {
      final key = b19OtherIncomeCreationIdempotencyKey();
      await postIncome(idempotencyKey: key, amount: 100);

      await expectLater(
        postIncome(idempotencyKey: key, amount: 200),
        throwsA(isA<OtherIncomeCreationIdempotencyConflictException>()),
      );

      expect(await incomeCount(), 1);
    });

    test('4) sequential double submit same key', () async {
      final key = b19OtherIncomeCreationIdempotencyKey();
      final fp = fingerprintFor();
      await postIncome(idempotencyKey: key, fingerprint: fp);
      await postIncome(idempotencyKey: key, fingerprint: fp);
      expect(await incomeCount(), 1);
    });

    test('5) concurrent same key + same fingerprint', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b19_same_${DateTime.now().microsecondsSinceEpoch}.db';
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
      final cid = await dbA.otherIncomeDao.createCategory(
        const OtherIncomeCategoriesCompanion(
          name: Value('Conc Cat'),
          isActive: Value(true),
        ),
      );

      final serviceA = OtherIncomeCreationService(dbA);
      final serviceB = OtherIncomeCreationService(dbB);
      final sameKey = b19OtherIncomeCreationIdempotencyKey();
      final fp = OtherIncomeCreationFingerprint.compute(
        categoryId: cid,
        amount: 50,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'conc',
        createdBy: uid,
      );

      final outcomes = await Future.wait([
        serviceA.processCreate(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          categoryId: cid,
          amount: 50,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: 'conc',
          createdBy: uid,
        ),
        serviceB.processCreate(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          categoryId: cid,
          amount: 50,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: 'conc',
          createdBy: uid,
        ),
      ]);

      expect(await incomeCount(dbA), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(outcomes.map((r) => r.otherIncomeRecordId).toSet().length, 1);
    });

    test('6) concurrent same key + different fingerprint conflict', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b19_conflict_${DateTime.now().microsecondsSinceEpoch}.db';
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
      final cid = await dbA.otherIncomeDao.createCategory(
        const OtherIncomeCategoriesCompanion(
          name: Value('Conflict Cat'),
          isActive: Value(true),
        ),
      );

      final serviceA = OtherIncomeCreationService(dbA);
      final serviceB = OtherIncomeCreationService(dbB);
      final sameKey = b19OtherIncomeCreationIdempotencyKey();
      final fpA = OtherIncomeCreationFingerprint.compute(
        categoryId: cid,
        amount: 50,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'a',
        createdBy: uid,
      );
      final fpB = OtherIncomeCreationFingerprint.compute(
        categoryId: cid,
        amount: 75,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
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
            incomeDate: incomeDate,
            receivedAt: receivedAt,
            notes: 'b',
            createdBy: uid,
          );
        } on OtherIncomeCreationIdempotencyConflictException catch (e) {
          return e;
        }
      }

      final outcomes = await Future.wait<Object?>([
        serviceA.processCreate(
          idempotencyKey: sameKey,
          fingerprintHash: fpA,
          categoryId: cid,
          amount: 50,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: 'a',
          createdBy: uid,
        ),
        runConflictAttempt(),
      ]);

      expect(await incomeCount(dbA), 1);
      expect(
        outcomes.whereType<OtherIncomeCreationIdempotencyConflictException>().length,
        1,
      );
    });

    test('7) different keys create two income records', () async {
      await postIncome(idempotencyKey: b19OtherIncomeCreationIdempotencyKey());
      await postIncome(idempotencyKey: b19OtherIncomeCreationIdempotencyKey());
      expect(await incomeCount(), 2);
    });

    test('8) income INSERT failure rolls back', () async {
      final failing = OtherIncomeCreationService(
        db,
        beforeIncomeInsertHook: () async {
          throw Exception('forced insert failure');
        },
      );

      await expectLater(
        postIncome(
          targetService: failing,
          idempotencyKey: b19OtherIncomeCreationIdempotencyKey(),
        ),
        throwsA(isA<Exception>()),
      );

      expect(await incomeCount(), 0);
      expect(await idempotencyRowCount(), 0);
    });

    test('9) production activity log failure rolls back', () async {
      await db.customStatement('''
        CREATE TRIGGER b19_block_activity_log
        BEFORE INSERT ON activity_logs
        BEGIN
          SELECT RAISE(FAIL, 'forced activity log failure');
        END;
      ''');

      await expectLater(
        postIncome(idempotencyKey: b19OtherIncomeCreationIdempotencyKey()),
        throwsA(isA<Exception>()),
      );

      expect(await incomeCount(), 0);
      expect(await idempotencyRowCount(), 0);
      expect(await activityLogCount(), 0);
      expect(await otherIncomeLedgerCount(), 0);
    });

    test('10) seal race preSealHook then retry succeeds once', () async {
      final key = b19OtherIncomeCreationIdempotencyKey();
      final fp = fingerprintFor();
      var hookCalls = 0;
      final flaky = OtherIncomeCreationService(
        db,
        preSealHook: () async {
          hookCalls++;
          if (hookCalls == 1) throw Exception('forced seal race');
        },
      );

      await expectLater(
        postIncome(targetService: flaky, idempotencyKey: key, fingerprint: fp),
        throwsA(isA<Exception>()),
      );

      final retry = await postIncome(
        targetService: flaky,
        idempotencyKey: key,
        fingerprint: fp,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await incomeCount(), 1);
    });

    test('11) SQLITE_BUSY retry succeeds under dual connection contention', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b19_busy_${DateTime.now().microsecondsSinceEpoch}.db';
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
      final cid = await dbA.otherIncomeDao.createCategory(
        const OtherIncomeCategoriesCompanion(
          name: Value('Busy Cat'),
          isActive: Value(true),
        ),
      );

      final serviceA = OtherIncomeCreationService(dbA);
      final serviceB = OtherIncomeCreationService(dbB);
      final sameKey = b19OtherIncomeCreationIdempotencyKey();
      final fp = OtherIncomeCreationFingerprint.compute(
        categoryId: cid,
        amount: 40,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'busy',
        createdBy: uid,
      );

      final outcomes = await Future.wait([
        serviceA.processCreate(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          categoryId: cid,
          amount: 40,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: 'busy',
          createdBy: uid,
        ),
        serviceB.processCreate(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          categoryId: cid,
          amount: 40,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: 'busy',
          createdBy: uid,
        ),
      ]);

      expect(await incomeCount(dbA), 1);
      expect(outcomes.map((r) => r.otherIncomeRecordId).toSet().length, 1);
    });

    test('12) post-commit ambiguous-result replay returns same income ID', () async {
      final key = b19OtherIncomeCreationIdempotencyKey();
      final fp = fingerprintFor();
      final first = await postIncome(idempotencyKey: key, fingerprint: fp);
      final replay = await postIncome(idempotencyKey: key, fingerprint: fp);

      expect(replay.idempotentReplay, isTrue);
      expect(replay.otherIncomeRecordId, first.otherIncomeRecordId);
    });

    test('13) void after create excludes ledger row', () async {
      final created = await postIncome(idempotencyKey: b19OtherIncomeCreationIdempotencyKey(), amount: 80);
      expect(await otherIncomeLedgerCountForId(created.otherIncomeRecordId), 1);
      await repository.voidIncomeForTest(
        idempotencyKey: b19OtherIncomeCreationIdempotencyKey(),
        otherIncomeRecordId: created.otherIncomeRecordId,
        voidedBy: userId,
      );
      expect(await otherIncomeLedgerCountForId(created.otherIncomeRecordId), 0);
    });

    test('14) edit after create keeps single ledger row for income ID', () async {
      final created = await postIncome(idempotencyKey: b19OtherIncomeCreationIdempotencyKey(), amount: 80);
      final row = await db.otherIncomeDao.getIncomeById(created.otherIncomeRecordId);
      expect(row, isNotNull);

      await repository.updateIncomeForTest(
        idempotencyKey: b19OtherIncomeCreationIdempotencyKey(),
        record: models.OtherIncomeRecord(
          id: created.otherIncomeRecordId,
          categoryId: categoryId,
          amount: 120,
          incomeDate: row!.incomeDate,
          receivedAt: row.receivedAt,
          notes: row.notes,
          createdBy: userId,
          isVoided: false,
        ),
        updatedBy: userId,
      );

      expect(await otherIncomeLedgerCountForId(created.otherIncomeRecordId), 1);
    });

    test('15) exactly one OTHER_INCOME ledger event after replay', () async {
      final key = b19OtherIncomeCreationIdempotencyKey();
      final fp = fingerprintFor(amount: 55);
      final first = await postIncome(idempotencyKey: key, fingerprint: fp, amount: 55);
      await postIncome(idempotencyKey: key, fingerprint: fp, amount: 55);
      expect(await otherIncomeLedgerCount(), 1);
      expect(await otherIncomeLedgerCountForId(first.otherIncomeRecordId), 1);
    });

    test('16) migration v45 -> v46 creates other_income_idempotency', () async {
      final opened = await openSimulatedV45RawDatabase();
      addTearDown(opened.rawDb.dispose);

      final before = opened.rawDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='other_income_idempotency'",
      );
      expect(before, isEmpty);

      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 51);
      expect(await idempotencyTableExists(migrated), isTrue);
      expect(await idempotencyIndexExists(migrated), isTrue);
    });

    test('17) date normalization matches same calendar day with different times', () async {
      final morning = DateTime(2026, 6, 10, 8, 15);
      final evening = DateTime(2026, 6, 10, 19, 45);
      final fpMorning = fingerprintFor(
        amount: 30,
        incomeDateOverride: morning,
        receivedAtOverride: morning,
        notes: 'date norm',
      );
      final fpEvening = fingerprintFor(
        amount: 30,
        incomeDateOverride: evening,
        receivedAtOverride: evening,
        notes: 'date norm',
      );
      expect(fpMorning, fpEvening);

      final created = await postIncome(
        idempotencyKey: b19OtherIncomeCreationIdempotencyKey(),
        fingerprint: fpMorning,
        amount: 30,
        incomeDateOverride: morning,
        receivedAtOverride: morning,
        notes: 'date norm',
      );
      final row = await db.otherIncomeDao.getIncomeById(created.otherIncomeRecordId);
      expect(row!.incomeDate, OtherIncomeCreationFingerprint.normalizeDate(morning));
      expect(row.receivedAt, OtherIncomeCreationFingerprint.normalizeDate(morning));
    });

    test('18) createdBy validation rejects zero', () async {
      await expectLater(
        postIncome(
          idempotencyKey: b19OtherIncomeCreationIdempotencyKey(),
          createdByOverride: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await incomeCount(), 0);
    });

    test('19) category existence and active validation', () async {
      await expectLater(
        postIncome(
          idempotencyKey: b19OtherIncomeCreationIdempotencyKey(),
          categoryOverride: 999999,
        ),
        throwsA(isA<StateError>()),
      );

      final inactiveId = await db.otherIncomeDao.createCategory(
        const OtherIncomeCategoriesCompanion(
          name: Value('Inactive'),
          isActive: Value(false),
        ),
      );

      await expectLater(
        postIncome(
          idempotencyKey: b19OtherIncomeCreationIdempotencyKey(),
          categoryOverride: inactiveId,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('20) fingerprint change with same key conflicts', () async {
      final key = b19OtherIncomeCreationIdempotencyKey();
      final fpA = fingerprintFor(amount: 100, notes: 'first');
      await postIncome(idempotencyKey: key, fingerprint: fpA, notes: 'first');

      final fpB = fingerprintFor(amount: 100, notes: 'second');
      expect(fpA, isNot(fpB));

      await expectLater(
        postIncome(idempotencyKey: key, fingerprint: fpB, notes: 'second'),
        throwsA(isA<OtherIncomeCreationIdempotencyConflictException>()),
      );
    });
  });

  group('B40 other income submit runner', () {
    test('skips second submit while in flight', () async {
      final runner = OtherIncomeSubmitRunner();
      final gate = Completer<void>();
      final intent = OtherIncomeSubmitIntent.create(
        categoryId: 1,
        amount: 50,
        incomeDate: DateTime(2026, 3, 15),
        receivedAt: DateTime(2026, 3, 15),
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

      expect(second, OtherIncomeSubmitOutcome.skippedInFlight);
      gate.complete();
      await firstFuture;
      expect(calls, 1);
    });

    test('stale completion skips post-success refresh', () async {
      final runner = OtherIncomeSubmitRunner();
      var current = true;
      var refreshCalls = 0;
      final intent = OtherIncomeSubmitIntent.create(
        categoryId: 1,
        amount: 50,
        incomeDate: DateTime(2026, 3, 15),
        receivedAt: DateTime(2026, 3, 15),
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

      expect(outcome, OtherIncomeSubmitOutcome.staleCompletion);
      expect(refreshCalls, 0);
    });
  });

  group('B40 other income dialog UI idempotency — create', () {
    late AppDatabase uiDb;
    late int uiCategoryId;
    late int uiUserId;
    late _CountingOtherIncomeCreationService spy;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      OtherIncomeDialog.resetOtherIncomeSubmitTestingHooks();
      uiDb = AppDatabase.test();
      uiUserId = await uiDb.into(uiDb.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'B40 UI User',
              username: 'b40ui_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      uiCategoryId = await uiDb.otherIncomeDao.createCategory(
        const OtherIncomeCategoriesCompanion(
          name: Value('B40 Category'),
          isActive: Value(true),
        ),
      );
      spy = _CountingOtherIncomeCreationService(uiDb);
    });

    tearDown(() async {
      OtherIncomeDialog.resetOtherIncomeSubmitTestingHooks();
      await uiDb.close();
    });

    Future<ProviderContainer> openDialog(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: _b40CreateUiOverrides(
          spy: spy,
          categoryId: uiCategoryId,
          userId: uiUserId,
        ),
      );
      addTearDown(container.dispose);
      await _pumpOtherIncomeCreateDialog(tester, container);
      await _selectB40Category(tester);
      await tester.enterText(_otherIncomeAmountField(), '100');
      await tester.pump();
      return container;
    }

    testWidgets('duplicate in-flight create invokes processCreate once',
        (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      spy = _CountingOtherIncomeCreationService(uiDb, saveGate: gate);
      await openDialog(tester);

      final save = find.byKey(const Key('other_income_dialog_save'));
      await tester.tap(save);
      await _flushOtherIncomeDialogUi(tester);
      expect(spy.createCalls, 1);
      expect(tester.widget<ElevatedButton>(save).onPressed, isNull);

      gate.complete();
      await _flushOtherIncomeDialogUi(tester);
    });

    testWidgets('stale completion does not close dialog or refresh',
        (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      spy = _CountingOtherIncomeCreationService(uiDb, saveGate: gate);

      await openDialog(tester);

      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await _flushOtherIncomeDialogUi(tester);
      expect(spy.createCalls, 1);
      OtherIncomeDialog.invalidateSubmitGenerationForTesting();
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(OtherIncomeDialog), findsOneWidget);
      expect(OtherIncomeDialog.postSuccessRefreshCount, 0);
      expect(
        find.text('تم تجاهل نتيجة حفظ سابقة بعد تغيير البيانات.'),
        findsOneWidget,
      );
    });

    testWidgets('success closes dialog and refreshes once', (tester) async {
      await openDialog(tester);

      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();

      expect(find.byType(OtherIncomeDialog), findsNothing);
      expect(spy.createCalls, 1);
      expect(OtherIncomeDialog.postSuccessRefreshCount, 1);
    });

    testWidgets('conflict clears key for next attempt', (tester) async {
      spy.throwConflict = true;
      await openDialog(tester);

      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();

      spy.throwConflict = false;
      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();

      expect(spy.createCalls, 2);
      expect(spy.keysUsed.length, 2);
      expect(spy.keysUsed[0], isNot(spy.keysUsed[1]));
    });

    testWidgets('service failure retry reuses same key', (tester) async {
      spy.throwOnce = true;
      await openDialog(tester);

      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();

      expect(spy.createCalls, 2);
      expect(spy.keysUsed.length, 2);
      expect(spy.keysUsed[0], spy.keysUsed[1]);
    });

    testWidgets('refresh failure retains key then succeeds', (tester) async {
      OtherIncomeDialog.failNextPostSuccessRefreshForTesting = true;
      await openDialog(tester);

      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();

      expect(find.byType(OtherIncomeDialog), findsOneWidget);
      expect(
        find.text('تم حفظ الإيراد، لكن تعذر تحديث العرض. أعد المحاولة.'),
        findsOneWidget,
      );

      OtherIncomeDialog.failNextPostSuccessRefreshForTesting = false;
      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();

      expect(spy.createCalls, 2);
      expect(spy.keysUsed[0], spy.keysUsed[1]);
      expect(find.byType(OtherIncomeDialog), findsNothing);
    });

    testWidgets('intent fields disabled while saving', (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      spy = _CountingOtherIncomeCreationService(uiDb, saveGate: gate);

      await openDialog(tester);

      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await _flushOtherIncomeDialogUi(tester);
      expect(spy.createCalls, 1);

      final amountField =
          tester.widget<TextFormField>(_otherIncomeAmountField());
      expect(amountField.enabled, isFalse);

      gate.complete();
      await _flushOtherIncomeDialogUi(tester);
    });
  });
}
