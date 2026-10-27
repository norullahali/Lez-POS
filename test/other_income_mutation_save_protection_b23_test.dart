import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/activity/activity_types.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/other_income_creation_fingerprint.dart';
import 'package:lez_pos/core/services/other_income_creation_service.dart';
import 'package:lez_pos/core/services/other_income_mutation_fingerprint.dart';
import 'package:lez_pos/core/services/other_income_mutation_save_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/other_income_mutation_save_result.dart';
import 'package:lez_pos/core/services/other_income_mutation_save_service.dart';
import 'package:lez_pos/features/auth/providers/auth_provider.dart';
import 'package:lez_pos/features/other_income/models/other_income_category.dart'
    as oi_cat;
import 'package:lez_pos/features/other_income/models/other_income_record.dart'
    as oi_models;
import 'package:lez_pos/features/other_income/providers/other_income_mutation_save_service_provider.dart';
import 'package:lez_pos/features/other_income/providers/other_income_providers.dart';
import 'package:lez_pos/features/other_income/screens/widgets/other_income_dialog.dart';
import 'package:lez_pos/features/pos/providers/pos_provider.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/other_income_creation_test_keys.dart';
import 'support/other_income_mutation_save_test_keys.dart';

class _CountingOtherIncomeMutationSaveService
    extends OtherIncomeMutationSaveService {
  _CountingOtherIncomeMutationSaveService(
    AppDatabase database, {
    Completer<void>? saveGate,
  })  : _saveGate = saveGate,
        super(database);

  final Completer<void>? _saveGate;
  bool throwConflict = false;
  bool throwOnce = false;
  int updateCalls = 0;
  final List<String> keysUsed = [];
  int? lastSessionId;

  @override
  Future<OtherIncomeMutationSaveResult> processUpdate({
    required String idempotencyKey,
    required String fingerprintHash,
    required int otherIncomeRecordId,
    required int categoryId,
    required double amount,
    required DateTime incomeDate,
    required DateTime receivedAt,
    required String notes,
    required int updatedBy,
    int? sessionId,
  }) async {
    updateCalls++;
    keysUsed.add(idempotencyKey);
    lastSessionId = sessionId;
    if (throwOnce) {
      throwOnce = false;
      throw Exception('forced update failure');
    }
    if (throwConflict) {
      throw const OtherIncomeMutationSaveIdempotencyConflictException();
    }
    if (_saveGate != null) {
      await _saveGate!.future;
    }
    return OtherIncomeMutationSaveResult(
      otherIncomeRecordId: otherIncomeRecordId,
      idempotentReplay: false,
    );
  }
}

class _B40UpdateAuthNotifier extends AuthNotifier {
  _B40UpdateAuthNotifier(this._user);

  final User _user;

  @override
  FutureOr<AuthState> build() async => AuthState(user: _user);
}

class _NullPosSessionNotifier extends PosSessionNotifier {
  @override
  Future<PosSession?> build() async => null;
}

User _b40UpdateUser(int id) => User(
      id: id,
      fullName: 'B40 Update User',
      username: 'b40update',
      passwordHash: 'hash',
      roleId: 1,
      isActive: true,
      refundLimit: 100000,
      createdAt: DateTime(2026, 1, 1),
    );

List<Override> _b40UpdateUiOverrides({
  required _CountingOtherIncomeMutationSaveService spy,
  required int categoryId,
  required int userId,
  bool nullPosSession = false,
}) {
  return [
    otherIncomeMutationSaveServiceProvider.overrideWithValue(spy),
    authProvider.overrideWith(() => _B40UpdateAuthNotifier(_b40UpdateUser(userId))),
    otherIncomeCategoriesProvider.overrideWith(
      (ref) async => [
        oi_cat.OtherIncomeCategory(
          id: categoryId,
          name: 'B40 Update Category',
          isActive: true,
        ),
      ],
    ),
    if (nullPosSession)
      posSessionProvider.overrideWith(_NullPosSessionNotifier.new),
  ];
}

Future<void> _pumpOtherIncomeEditDialog(
  WidgetTester tester,
  ProviderContainer container,
  oi_models.OtherIncomeRecord existing,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: OtherIncomeDialog(existing: existing),
        ),
      ),
    ),
  );
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final auth = container.read(authProvider);
    if (auth.hasValue &&
        auth.requireValue.user != null &&
        find.byKey(const Key('other_income_dialog_save')).evaluate().isNotEmpty) {
      return;
    }
  }
}

Finder _b40UpdateAmountField() =>
    find.byKey(const Key('other_income_dialog_amount'));

Future<({sqlite3.Database rawDb, String path})> openSimulatedV49RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b23_v49_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement(
    'DROP TABLE IF EXISTS other_income_mutation_idempotency',
  );
  await bootstrap.customStatement('DROP INDEX IF EXISTS oimi_other_income_record_idx');
  await bootstrap.customStatement('PRAGMA user_version = 49');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 49);
  return (rawDb: rawDb, path: dbPath);
}

Future<({
  AppDatabase dbA,
  AppDatabase dbB,
  String path,
})> openDualConnectionRaceDatabases() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b23_race_${DateTime.now().microsecondsSinceEpoch}.db';
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
  late OtherIncomeCreationService createService;
  late OtherIncomeMutationSaveService mutationService;
  late int categoryId;
  late int userId;
  late DateTime incomeDate;
  late DateTime receivedAt;

  setUp(() async {
    db = AppDatabase.test();
    createService = OtherIncomeCreationService(db);
    mutationService = OtherIncomeMutationSaveService(db);
    userId = await db.into(db.usersTable).insert(
          UsersTableCompanion.insert(
            fullName: 'B23 User',
            username: 'b23_${DateTime.now().microsecondsSinceEpoch}',
            passwordHash: 'hash',
            roleId: 1,
          ),
        );
    categoryId = await db.otherIncomeDao.createCategory(
      const OtherIncomeCategoriesCompanion(
        name: Value('B23 Category'),
        isActive: Value(true),
      ),
    );
    incomeDate = DateTime(2026, 4, 10);
    receivedAt = DateTime(2026, 4, 11);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> createIncome({double amount = 100}) async {
    final key = b19OtherIncomeCreationIdempotencyKey();
    final fp = OtherIncomeCreationFingerprint.compute(
      categoryId: categoryId,
      amount: amount,
      incomeDate: incomeDate,
      receivedAt: receivedAt,
      notes: 'seed',
      createdBy: userId,
    );
    final r = await createService.processCreate(
      idempotencyKey: key,
      fingerprintHash: fp,
      categoryId: categoryId,
      amount: amount,
      incomeDate: incomeDate,
      receivedAt: receivedAt,
      notes: 'seed',
      createdBy: userId,
    );
    return r.otherIncomeRecordId;
  }

  String updateFp(int otherIncomeRecordId, {double amount = 120, int? sessionId}) =>
      OtherIncomeMutationFingerprint.computeUpdate(
        otherIncomeRecordId: otherIncomeRecordId,
        categoryId: categoryId,
        amount: amount,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'updated',
        updatedBy: userId,
        sessionId: sessionId,
      );

  String voidFp(int otherIncomeRecordId) => OtherIncomeMutationFingerprint.computeVoid(
        otherIncomeRecordId: otherIncomeRecordId,
        voidedBy: userId,
      );

  Future<int> mutationIdempotencyCount([AppDatabase? target]) async {
    final d = target ?? db;
    return (await d.select(d.otherIncomeMutationIdempotency).get()).length;
  }

  Future<int> activityLogCount([AppDatabase? target]) async {
    final d = target ?? db;
    return (await d.select(d.activityLogs).get()).length;
  }

  Future<double> summaryTotal([AppDatabase? target]) async {
    final d = target ?? db;
    final s = await d.otherIncomeDao.getIncomeSummary();
    return s.$2;
  }

  Future<int> activityCountForType(String activityType, [AppDatabase? target]) async {
    final d = target ?? db;
    final rows = await d.select(d.activityLogs).get();
    return rows.where((r) => r.activityType == activityType).length;
  }

  Future<int> otherIncomeLedgerCountForId(
    int incomeId, [
    AppDatabase? target,
  ]) async {
    final d = target ?? db;
    final ledger = FinancialLedgerRepository(d);
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

  Future<({
    int otherIncomeRecordId,
    int uid,
    int categoryId,
  })> seedIncomeOnDualDb({
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
    final cid = await dbA.otherIncomeDao.createCategory(
      const OtherIncomeCategoriesCompanion(name: Value('C'), isActive: Value(true)),
    );
    final createKey = b19OtherIncomeCreationIdempotencyKey();
    final createFp = OtherIncomeCreationFingerprint.compute(
      categoryId: cid,
      amount: amount,
      incomeDate: incomeDate,
      receivedAt: receivedAt,
      notes: 'seed',
      createdBy: uid,
    );
    final created = await OtherIncomeCreationService(dbA).processCreate(
      idempotencyKey: createKey,
      fingerprintHash: createFp,
      categoryId: cid,
      amount: amount,
      incomeDate: incomeDate,
      receivedAt: receivedAt,
      notes: 'seed',
      createdBy: uid,
    );
    return (
      otherIncomeRecordId: created.otherIncomeRecordId,
      uid: uid,
      categoryId: cid,
    );
  }

  group('B23 other income mutation save protection', () {
    test('1) update success', () async {
      final otherIncomeRecordId = await createIncome();
      final key = b23OtherIncomeMutationIdempotencyKey();
      final fp = updateFp(otherIncomeRecordId);
      final result = await mutationService.processUpdate(
        idempotencyKey: key,
        fingerprintHash: fp,
        otherIncomeRecordId: otherIncomeRecordId,
        categoryId: categoryId,
        amount: 120,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'updated',
        updatedBy: userId,
      );
      expect(result.idempotentReplay, isFalse);
      final row = await db.otherIncomeDao.getIncomeById(otherIncomeRecordId);
      expect(row!.amount, 120);
      expect(await mutationIdempotencyCount(), 1);
      expect(await activityLogCount(), greaterThan(1));
    });

    test('2) update same-key replay', () async {
      final otherIncomeRecordId = await createIncome();
      final key = b23OtherIncomeMutationIdempotencyKey();
      final fp = updateFp(otherIncomeRecordId);
      await mutationService.processUpdate(
        idempotencyKey: key,
        fingerprintHash: fp,
        otherIncomeRecordId: otherIncomeRecordId,
        categoryId: categoryId,
        amount: 120,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'updated',
        updatedBy: userId,
      );
      final logsAfterFirst = await activityLogCount();
      final replay = await mutationService.processUpdate(
        idempotencyKey: key,
        fingerprintHash: fp,
        otherIncomeRecordId: otherIncomeRecordId,
        categoryId: categoryId,
        amount: 120,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'updated',
        updatedBy: userId,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(await activityLogCount(), logsAfterFirst);
      expect(await mutationIdempotencyCount(), 1);
    });

    test('3) update same-key conflict', () async {
      final otherIncomeRecordId = await createIncome();
      final key = b23OtherIncomeMutationIdempotencyKey();
      await mutationService.processUpdate(
        idempotencyKey: key,
        fingerprintHash: updateFp(otherIncomeRecordId, amount: 110),
        otherIncomeRecordId: otherIncomeRecordId,
        categoryId: categoryId,
        amount: 110,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'updated',
        updatedBy: userId,
      );
      await expectLater(
        mutationService.processUpdate(
          idempotencyKey: key,
          fingerprintHash: updateFp(otherIncomeRecordId, amount: 999),
          otherIncomeRecordId: otherIncomeRecordId,
          categoryId: categoryId,
          amount: 999,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: 'updated',
          updatedBy: userId,
        ),
        throwsA(isA<OtherIncomeMutationSaveIdempotencyConflictException>()),
      );
      expect((await db.otherIncomeDao.getIncomeById(otherIncomeRecordId))!.amount, 110);
    });

    test('4) different keys sequential updates', () async {
      final otherIncomeRecordId = await createIncome();
      await mutationService.processUpdate(
        idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
        fingerprintHash: updateFp(otherIncomeRecordId, amount: 110),
        otherIncomeRecordId: otherIncomeRecordId,
        categoryId: categoryId,
        amount: 110,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'a',
        updatedBy: userId,
      );
      await mutationService.processUpdate(
        idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
        fingerprintHash: updateFp(otherIncomeRecordId, amount: 130),
        otherIncomeRecordId: otherIncomeRecordId,
        categoryId: categoryId,
        amount: 130,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'b',
        updatedBy: userId,
      );
      expect((await db.otherIncomeDao.getIncomeById(otherIncomeRecordId))!.amount, 130);
      expect(await mutationIdempotencyCount(), 2);
    });

    test('5) update rollback on activity log failure', () async {
      final otherIncomeRecordId = await createIncome();
      final flaky = OtherIncomeMutationSaveService(
        db,
        testActivityLogHook: () async {
          throw StateError('forced activity failure');
        },
      );
      await expectLater(
        flaky.processUpdate(
          idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
          fingerprintHash: updateFp(otherIncomeRecordId),
          otherIncomeRecordId: otherIncomeRecordId,
          categoryId: categoryId,
          amount: 120,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: 'updated',
          updatedBy: userId,
        ),
        throwsA(isA<StateError>()),
      );
      expect((await db.otherIncomeDao.getIncomeById(otherIncomeRecordId))!.amount, 100);
      expect(await mutationIdempotencyCount(), 0);
    });

    test('6) update seal failure then retry', () async {
      final otherIncomeRecordId = await createIncome();
      final key = b23OtherIncomeMutationIdempotencyKey();
      final fp = updateFp(otherIncomeRecordId);
      final flaky = OtherIncomeMutationSaveService(
        db,
        preSealHook: () async {
          throw StateError('forced seal failure');
        },
      );
      await expectLater(
        flaky.processUpdate(
          idempotencyKey: key,
          fingerprintHash: fp,
          otherIncomeRecordId: otherIncomeRecordId,
          categoryId: categoryId,
          amount: 120,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: 'updated',
          updatedBy: userId,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await mutationIdempotencyCount(), 0);
      await mutationService.processUpdate(
        idempotencyKey: key,
        fingerprintHash: fp,
        otherIncomeRecordId: otherIncomeRecordId,
        categoryId: categoryId,
        amount: 120,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
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
      final cid = await opened.dbA.otherIncomeDao.createCategory(
        const OtherIncomeCategoriesCompanion(name: Value('C'), isActive: Value(true)),
      );
      final createKey = b19OtherIncomeCreationIdempotencyKey();
      final createFp = OtherIncomeCreationFingerprint.compute(
        categoryId: cid,
        amount: 50,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'x',
        createdBy: uid,
      );
      final created = await OtherIncomeCreationService(opened.dbA).processCreate(
        idempotencyKey: createKey,
        fingerprintHash: createFp,
        categoryId: cid,
        amount: 50,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'x',
        createdBy: uid,
      );
      final sameKey = b23OtherIncomeMutationIdempotencyKey();
      final fp = OtherIncomeMutationFingerprint.computeUpdate(
        otherIncomeRecordId: created.otherIncomeRecordId,
        categoryId: cid,
        amount: 75,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'u',
        updatedBy: uid,
      );
      final release = Completer<void>();
      final serviceA = OtherIncomeMutationSaveService(
        opened.dbA,
        preSealHook: () async => release.future,
      );
      final serviceB = OtherIncomeMutationSaveService(opened.dbB);
      final fA = serviceA.processUpdate(
        idempotencyKey: sameKey,
        fingerprintHash: fp,
        otherIncomeRecordId: created.otherIncomeRecordId,
        categoryId: cid,
        amount: 75,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'u',
        updatedBy: uid,
      );
      final fB = serviceB.processUpdate(
        idempotencyKey: sameKey,
        fingerprintHash: fp,
        otherIncomeRecordId: created.otherIncomeRecordId,
        categoryId: cid,
        amount: 75,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'u',
        updatedBy: uid,
      );
      release.complete();
      final outcomes = await Future.wait([fA, fB]);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(await mutationIdempotencyCount(opened.dbA), 1);
      expect(
        (await opened.dbA.otherIncomeDao.getIncomeById(created.otherIncomeRecordId))!
            .amount,
        75,
      );
    });

    test('8) update amount and summary total', () async {
      final otherIncomeRecordId = await createIncome(amount: 80);
      expect(await summaryTotal(), 80);
      await mutationService.processUpdate(
        idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
        fingerprintHash: updateFp(otherIncomeRecordId, amount: 95),
        otherIncomeRecordId: otherIncomeRecordId,
        categoryId: categoryId,
        amount: 95,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'updated',
        updatedBy: userId,
      );
      expect(await summaryTotal(), 95);
    });

    test('9) void success', () async {
      final otherIncomeRecordId = await createIncome();
      final result = await mutationService.processVoid(
        idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
        fingerprintHash: voidFp(otherIncomeRecordId),
        otherIncomeRecordId: otherIncomeRecordId,
        voidedBy: userId,
      );
      expect(result.alreadyVoided, isFalse);
      expect((await db.otherIncomeDao.getIncomeById(otherIncomeRecordId))!.isVoided, isTrue);
      expect(await summaryTotal(), 0);
      expect(await mutationIdempotencyCount(), 1);
    });

    test('10) void same-key replay', () async {
      final otherIncomeRecordId = await createIncome();
      final key = b23OtherIncomeMutationIdempotencyKey();
      final fp = voidFp(otherIncomeRecordId);
      await mutationService.processVoid(
        idempotencyKey: key,
        fingerprintHash: fp,
        otherIncomeRecordId: otherIncomeRecordId,
        voidedBy: userId,
      );
      final logs = await activityLogCount();
      final replay = await mutationService.processVoid(
        idempotencyKey: key,
        fingerprintHash: fp,
        otherIncomeRecordId: otherIncomeRecordId,
        voidedBy: userId,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(await activityLogCount(), logs);
    });

    test('11) void same-key conflict', () async {
      final otherIncomeRecordId = await createIncome();
      final key = b23OtherIncomeMutationIdempotencyKey();
      await mutationService.processVoid(
        idempotencyKey: key,
        fingerprintHash: voidFp(otherIncomeRecordId),
        otherIncomeRecordId: otherIncomeRecordId,
        voidedBy: userId,
      );
      await expectLater(
        mutationService.processVoid(
          idempotencyKey: key,
          fingerprintHash: OtherIncomeMutationFingerprint.computeVoid(
            otherIncomeRecordId: otherIncomeRecordId,
            voidedBy: userId + 999,
          ),
          otherIncomeRecordId: otherIncomeRecordId,
          voidedBy: userId + 999,
        ),
        throwsA(isA<OtherIncomeMutationSaveIdempotencyConflictException>()),
      );
    });

    test('12) void already voided different key', () async {
      final otherIncomeRecordId = await createIncome();
      await mutationService.processVoid(
        idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
        fingerprintHash: voidFp(otherIncomeRecordId),
        otherIncomeRecordId: otherIncomeRecordId,
        voidedBy: userId,
      );
      final logs = await activityLogCount();
      final second = await mutationService.processVoid(
        idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
        fingerprintHash: voidFp(otherIncomeRecordId),
        otherIncomeRecordId: otherIncomeRecordId,
        voidedBy: userId,
      );
      expect(second.alreadyVoided, isTrue);
      expect(await activityLogCount(), logs);
      expect(await mutationIdempotencyCount(), 1);
    });

    test('13) void rollback activity failure', () async {
      final otherIncomeRecordId = await createIncome();
      final flaky = OtherIncomeMutationSaveService(
        db,
        testActivityLogHook: () async {
          throw StateError('forced void log failure');
        },
      );
      await expectLater(
        flaky.processVoid(
          idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
          fingerprintHash: voidFp(otherIncomeRecordId),
          otherIncomeRecordId: otherIncomeRecordId,
          voidedBy: userId,
        ),
        throwsA(isA<StateError>()),
      );
      expect((await db.otherIncomeDao.getIncomeById(otherIncomeRecordId))!.isVoided, isFalse);
    });

    test('14) void seal failure retry', () async {
      final otherIncomeRecordId = await createIncome();
      final key = b23OtherIncomeMutationIdempotencyKey();
      final fp = voidFp(otherIncomeRecordId);
      final flaky = OtherIncomeMutationSaveService(
        db,
        preSealHook: () async {
          throw StateError('seal fail');
        },
      );
      await expectLater(
        flaky.processVoid(
          idempotencyKey: key,
          fingerprintHash: fp,
          otherIncomeRecordId: otherIncomeRecordId,
          voidedBy: userId,
        ),
        throwsA(isA<StateError>()),
      );
      await mutationService.processVoid(
        idempotencyKey: key,
        fingerprintHash: fp,
        otherIncomeRecordId: otherIncomeRecordId,
        voidedBy: userId,
      );
      expect(await mutationIdempotencyCount(), 1);
    });

    test('15) update after void rejected', () async {
      final otherIncomeRecordId = await createIncome();
      await mutationService.processVoid(
        idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
        fingerprintHash: voidFp(otherIncomeRecordId),
        otherIncomeRecordId: otherIncomeRecordId,
        voidedBy: userId,
      );
      await expectLater(
        mutationService.processUpdate(
          idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
          fingerprintHash: updateFp(otherIncomeRecordId),
          otherIncomeRecordId: otherIncomeRecordId,
          categoryId: categoryId,
          amount: 200,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: 'nope',
          updatedBy: userId,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('16) service rejects updatedBy 0', () async {
      final otherIncomeRecordId = await createIncome();
      await expectLater(
        mutationService.processUpdate(
          idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
          fingerprintHash: 'x',
          otherIncomeRecordId: otherIncomeRecordId,
          categoryId: categoryId,
          amount: 120,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: 'x',
          updatedBy: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('17) service rejects voidedBy 0', () async {
      final otherIncomeRecordId = await createIncome();
      await expectLater(
        mutationService.processVoid(
          idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
          fingerprintHash: 'x',
          otherIncomeRecordId: otherIncomeRecordId,
          voidedBy: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('18) migration v49 to v50', () async {
      final opened = await openSimulatedV49RawDatabase();
      addTearDown(opened.rawDb.dispose);
      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());
      expect(migrated.schemaVersion, kExpectedAppSchemaVersion);
      final tables = await migrated.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='other_income_mutation_idempotency'",
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

      final seed = await seedIncomeOnDualDb(dbA: opened.dbA, amount: 50);
      final updateKey = b23OtherIncomeMutationIdempotencyKey();
      final voidKey = b23OtherIncomeMutationIdempotencyKey();
      const updatedAmount = 75.0;

      final updateAtBarrier = Completer<void>();
      final releaseUpdate = Completer<void>();

      final updateService = OtherIncomeMutationSaveService(
        opened.dbA,
        beforeMutationHook: () async {
          if (!updateAtBarrier.isCompleted) updateAtBarrier.complete();
          await releaseUpdate.future;
        },
      );
      final voidService = OtherIncomeMutationSaveService(opened.dbB);

      final updateFuture = updateService.processUpdate(
        idempotencyKey: updateKey,
        fingerprintHash: OtherIncomeMutationFingerprint.computeUpdate(
          otherIncomeRecordId: seed.otherIncomeRecordId,
          categoryId: seed.categoryId,
          amount: updatedAmount,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: 'race-update',
          updatedBy: seed.uid,
        ),
        otherIncomeRecordId: seed.otherIncomeRecordId,
        categoryId: seed.categoryId,
        amount: updatedAmount,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'race-update',
        updatedBy: seed.uid,
      );

      await updateAtBarrier.future;

      await voidService.processVoid(
        idempotencyKey: voidKey,
        fingerprintHash: OtherIncomeMutationFingerprint.computeVoid(
          otherIncomeRecordId: seed.otherIncomeRecordId,
          voidedBy: seed.uid,
        ),
        otherIncomeRecordId: seed.otherIncomeRecordId,
        voidedBy: seed.uid,
      );

      releaseUpdate.complete();

      await expectLater(updateFuture, throwsA(isA<StateError>()));

      final row =
          await opened.dbA.otherIncomeDao.getIncomeById(seed.otherIncomeRecordId);
      expect(row!.isVoided, isTrue);
      expect(row.amount, 50);
      expect(await mutationIdempotencyCount(opened.dbA), 1);
      expect(await summaryTotal(opened.dbA), 0);
      expect(
        await activityCountForType(ActivityTypes.incomeVoided, opened.dbA),
        1,
      );
      expect(
        await activityCountForType(ActivityTypes.incomeUpdated, opened.dbA),
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

      final seed = await seedIncomeOnDualDb(dbA: opened.dbA, amount: 50);
      final voidKey = b23OtherIncomeMutationIdempotencyKey();
      final updateKey = b23OtherIncomeMutationIdempotencyKey();
      const updatedAmount = 75.0;

      final voidAtBarrier = Completer<void>();
      final releaseVoid = Completer<void>();

      final voidService = OtherIncomeMutationSaveService(
        opened.dbA,
        beforeMutationHook: () async {
          if (!voidAtBarrier.isCompleted) voidAtBarrier.complete();
          await releaseVoid.future;
        },
      );
      final updateService = OtherIncomeMutationSaveService(opened.dbB);

      final voidFuture = voidService.processVoid(
        idempotencyKey: voidKey,
        fingerprintHash: OtherIncomeMutationFingerprint.computeVoid(
          otherIncomeRecordId: seed.otherIncomeRecordId,
          voidedBy: seed.uid,
        ),
        otherIncomeRecordId: seed.otherIncomeRecordId,
        voidedBy: seed.uid,
      );

      await voidAtBarrier.future;

      await updateService.processUpdate(
        idempotencyKey: updateKey,
        fingerprintHash: OtherIncomeMutationFingerprint.computeUpdate(
          otherIncomeRecordId: seed.otherIncomeRecordId,
          categoryId: seed.categoryId,
          amount: updatedAmount,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: 'race-update',
          updatedBy: seed.uid,
        ),
        otherIncomeRecordId: seed.otherIncomeRecordId,
        categoryId: seed.categoryId,
        amount: updatedAmount,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'race-update',
        updatedBy: seed.uid,
      );

      releaseVoid.complete();
      await voidFuture;

      final row =
          await opened.dbA.otherIncomeDao.getIncomeById(seed.otherIncomeRecordId);
      expect(row!.isVoided, isTrue);
      expect(row.amount, updatedAmount);
      expect(await mutationIdempotencyCount(opened.dbA), 2);
      expect(await summaryTotal(opened.dbA), 0);
      expect(
        await activityCountForType(ActivityTypes.incomeUpdated, opened.dbA),
        1,
      );
      expect(
        await activityCountForType(ActivityTypes.incomeVoided, opened.dbA),
        1,
      );
    });

    test('23) update changes ledger row for income ID', () async {
      final otherIncomeRecordId = await createIncome(amount: 80);
      expect(await otherIncomeLedgerCountForId(otherIncomeRecordId), 1);
      await mutationService.processUpdate(
        idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
        fingerprintHash: updateFp(otherIncomeRecordId, amount: 120),
        otherIncomeRecordId: otherIncomeRecordId,
        categoryId: categoryId,
        amount: 120,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: 'updated',
        updatedBy: userId,
      );
      expect(await otherIncomeLedgerCountForId(otherIncomeRecordId), 1);
      expect(await summaryTotal(), 120);
    });

    test('24) void excludes ledger row', () async {
      final otherIncomeRecordId = await createIncome(amount: 80);
      expect(await otherIncomeLedgerCountForId(otherIncomeRecordId), 1);
      await mutationService.processVoid(
        idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
        fingerprintHash: voidFp(otherIncomeRecordId),
        otherIncomeRecordId: otherIncomeRecordId,
        voidedBy: userId,
      );
      expect(await otherIncomeLedgerCountForId(otherIncomeRecordId), 0);
      expect(await summaryTotal(), 0);
    });

    test('25) failed update leaves ledger unchanged', () async {
      final otherIncomeRecordId = await createIncome(amount: 80);
      expect(await summaryTotal(), 80);
      final flaky = OtherIncomeMutationSaveService(
        db,
        testActivityLogHook: () async {
          throw StateError('forced activity failure');
        },
      );
      await expectLater(
        flaky.processUpdate(
          idempotencyKey: b23OtherIncomeMutationIdempotencyKey(),
          fingerprintHash: updateFp(otherIncomeRecordId, amount: 200),
          otherIncomeRecordId: otherIncomeRecordId,
          categoryId: categoryId,
          amount: 200,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: 'fail',
          updatedBy: userId,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await summaryTotal(), 80);
      expect(await otherIncomeLedgerCountForId(otherIncomeRecordId), 1);
    });

    test('20) real UNIQUE on mutation idempotency', () async {
      final key = b23OtherIncomeMutationIdempotencyKey();
      await db.otherIncomeMutationIdempotencyDao.insertCompletedRecord(
        idempotencyKey: key,
        operationType: OtherIncomeMutationFingerprint.operationUpdate,
        fingerprintHash: 'fp1',
        otherIncomeRecordId: 1,
      );
      await expectLater(
        db.otherIncomeMutationIdempotencyDao.insertCompletedRecord(
          idempotencyKey: key,
          operationType: OtherIncomeMutationFingerprint.operationUpdate,
          fingerprintHash: 'fp2',
          otherIncomeRecordId: 2,
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

  group('B40 other income dialog UI idempotency — update', () {
    late AppDatabase uiDb;
    late int uiCategoryId;
    late int uiUserId;
    late int uiOtherIncomeId;
    late _CountingOtherIncomeMutationSaveService spy;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      OtherIncomeDialog.resetOtherIncomeSubmitTestingHooks();
      uiDb = AppDatabase.test();
      uiUserId = await uiDb.into(uiDb.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'B40 Update UI',
              username: 'b40up_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      uiCategoryId = await uiDb.otherIncomeDao.createCategory(
        const OtherIncomeCategoriesCompanion(
          name: Value('B40 Update Category'),
          isActive: Value(true),
        ),
      );
      final createResult = await OtherIncomeCreationService(uiDb).processCreate(
        idempotencyKey: b19OtherIncomeCreationIdempotencyKey(),
        fingerprintHash: OtherIncomeCreationFingerprint.compute(
          categoryId: uiCategoryId,
          amount: 100,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: '',
          sessionId: null,
          createdBy: uiUserId,
        ),
        categoryId: uiCategoryId,
        amount: 100,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: '',
        createdBy: uiUserId,
      );
      uiOtherIncomeId = createResult.otherIncomeRecordId;
      spy = _CountingOtherIncomeMutationSaveService(uiDb);
    });

    tearDown(() async {
      OtherIncomeDialog.resetOtherIncomeSubmitTestingHooks();
      await uiDb.close();
    });

    oi_models.OtherIncomeRecord existingRecord({int? sessionId}) =>
        oi_models.OtherIncomeRecord(
          id: uiOtherIncomeId,
          categoryId: uiCategoryId,
          amount: 100,
          incomeDate: incomeDate,
          receivedAt: receivedAt,
          notes: '',
          sessionId: sessionId,
          createdBy: uiUserId,
        );

    Future<void> openEditDialog(
      WidgetTester tester, {
      int? sessionId,
      bool nullPosSession = false,
    }) async {
      final container = ProviderContainer(
        overrides: _b40UpdateUiOverrides(
          spy: spy,
          categoryId: uiCategoryId,
          userId: uiUserId,
          nullPosSession: nullPosSession,
        ),
      );
      addTearDown(container.dispose);
      await _pumpOtherIncomeEditDialog(
        tester,
        container,
        existingRecord(sessionId: sessionId),
      );
      await tester.enterText(_b40UpdateAmountField(), '120');
      await tester.pump();
    }

    testWidgets('duplicate in-flight update invokes processUpdate once',
        (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      spy = _CountingOtherIncomeMutationSaveService(uiDb, saveGate: gate);
      await openEditDialog(tester);

      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pump();
      await tester.runAsync(() async {
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pump();

      expect(spy.updateCalls, 1);
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('stale update does not close dialog', (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      spy = _CountingOtherIncomeMutationSaveService(uiDb, saveGate: gate);
      await openEditDialog(tester);

      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pump();
      OtherIncomeDialog.invalidateSubmitGenerationForTesting();
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(OtherIncomeDialog), findsOneWidget);
      expect(OtherIncomeDialog.postSuccessRefreshCount, 0);
    });

    testWidgets('update success closes dialog once', (tester) async {
      await openEditDialog(tester);

      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();

      expect(find.byType(OtherIncomeDialog), findsNothing);
      expect(spy.updateCalls, 1);
      expect(OtherIncomeDialog.postSuccessRefreshCount, 1);
    });

    testWidgets('update conflict clears key for retry', (tester) async {
      spy.throwConflict = true;
      await openEditDialog(tester);

      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();

      spy.throwConflict = false;
      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();

      expect(spy.updateCalls, 2);
      expect(spy.keysUsed[0], isNot(spy.keysUsed[1]));
    });

    testWidgets('update service failure retry reuses key', (tester) async {
      spy.throwOnce = true;
      await openEditDialog(tester);

      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();

      expect(spy.updateCalls, 2);
      expect(spy.keysUsed[0], spy.keysUsed[1]);
    });

    testWidgets('update refresh failure retains key then succeeds',
        (tester) async {
      OtherIncomeDialog.failNextPostSuccessRefreshForTesting = true;
      await openEditDialog(tester);

      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();

      expect(find.byType(OtherIncomeDialog), findsOneWidget);
      expect(
        find.text('تم حفظ الإيراد، لكن تعذر تحديث العرض. أعد المحاولة.'),
        findsOneWidget,
      );
      expect(spy.updateCalls, 1);
      expect(OtherIncomeDialog.postSuccessRefreshCount, 0);

      OtherIncomeDialog.failNextPostSuccessRefreshForTesting = false;
      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();

      expect(spy.updateCalls, 2);
      expect(spy.keysUsed[0], spy.keysUsed[1]);
      expect(find.byType(OtherIncomeDialog), findsNothing);
      expect(OtherIncomeDialog.postSuccessRefreshCount, 1);
    });

    testWidgets('Case D preserves sessionId when no active session',
        (tester) async {
      await openEditDialog(
        tester,
        sessionId: 999,
        nullPosSession: true,
      );

      await tester.tap(find.byKey(const Key('other_income_dialog_save')));
      await tester.pumpAndSettle();

      expect(spy.updateCalls, 1);
      expect(spy.lastSessionId, 999);
    });

    test('update refresh failure persists mutation before service replay',
        () async {
      final key = b23OtherIncomeMutationIdempotencyKey();
      final fingerprint = OtherIncomeMutationFingerprint.computeUpdate(
        otherIncomeRecordId: uiOtherIncomeId,
        categoryId: uiCategoryId,
        amount: 120,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: '',
        sessionId: null,
        updatedBy: uiUserId,
      );
      final service = OtherIncomeMutationSaveService(uiDb);

      final first = await service.processUpdate(
        idempotencyKey: key,
        fingerprintHash: fingerprint,
        otherIncomeRecordId: uiOtherIncomeId,
        categoryId: uiCategoryId,
        amount: 120,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: '',
        updatedBy: uiUserId,
      );
      expect(first.idempotentReplay, isFalse);
      expect(
        (await uiDb.otherIncomeDao.getIncomeById(uiOtherIncomeId))!.amount,
        120,
      );

      final replay = await service.processUpdate(
        idempotencyKey: key,
        fingerprintHash: fingerprint,
        otherIncomeRecordId: uiOtherIncomeId,
        categoryId: uiCategoryId,
        amount: 120,
        incomeDate: incomeDate,
        receivedAt: receivedAt,
        notes: '',
        updatedBy: uiUserId,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(
        (await uiDb.otherIncomeDao.getIncomeById(uiOtherIncomeId))!.amount,
        120,
      );
      expect(
        (await uiDb.select(uiDb.otherIncomeMutationIdempotency).get()).length,
        1,
      );
    });
  });
}
