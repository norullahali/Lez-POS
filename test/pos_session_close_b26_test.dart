import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/activity/activity_types.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/pos_session_close_fingerprint.dart';
import 'package:lez_pos/core/services/pos_session_close_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/pos_session_close_invalid_closed_by_user_exception.dart';
import 'package:lez_pos/core/services/pos_session_close_result.dart';
import 'package:lez_pos/core/services/pos_session_close_service.dart';
import 'package:lez_pos/core/services/pos_session_not_found_exception.dart';
import 'package:lez_pos/core/services/pos_session_open_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/pos_session_close_test_keys.dart';
import 'support/pos_session_open_test_keys.dart';

Future<int> insertOpenSession(
  AppDatabase db, {
  double openingCash = 100,
  String cashierName = 'Test Cashier',
}) =>
    db.into(db.posSessions).insert(
          PosSessionsCompanion(
            cashierName: Value(cashierName),
            openingCash: Value(openingCash),
            isClosed: const Value(false),
          ),
        );

Future<int> countOpenSessions(AppDatabase db) async {
  final row = await db.customSelect(
    'SELECT COUNT(*) AS cnt FROM pos_sessions WHERE is_closed = 0',
    readsFrom: {db.posSessions},
  ).getSingle();
  return row.data['cnt'] as int? ?? 0;
}

Future<int> countSessionCloseActivityLogs(AppDatabase db) async {
  return (await (db.select(db.activityLogs)
        ..where((l) => l.activityType.equals(ActivityTypes.sessionClosed)))
      .get())
      .length;
}

class _ConditionalCloseRaceGate {
  _ConditionalCloseRaceGate({required this.participantCount});

  final int participantCount;
  var _arrived = 0;
  final _allArrived = Completer<void>();
  final _release = Completer<void>();

  Future<void> arrive() async {
    _arrived++;
    if (_arrived == participantCount) {
      _allArrived.complete();
    }
    await _allArrived.future;
    await _release.future;
  }

  Future<void> waitUntilAllArrived() => _allArrived.future;

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }
}

Future<Object?> captureClose(Future<dynamic> future) async {
  try {
    return await future;
  } catch (e) {
    return e;
  }
}

PosSessionCloseService closeService(AppDatabase db) =>
    PosSessionCloseService(db);

Future<({
  AppDatabase dbA,
  AppDatabase dbB,
  sqlite3.Database rawA,
  sqlite3.Database rawB,
  String path,
})> openDualConnectionDatabases() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b26_race_${DateTime.now().microsecondsSinceEpoch}.db';
  final rawA = sqlite3.sqlite3.open(dbPath);
  final rawB = sqlite3.sqlite3.open(dbPath);
  rawA.execute('PRAGMA busy_timeout = 15000');
  rawB.execute('PRAGMA busy_timeout = 15000');
  final dbA = AppDatabase.test(NativeDatabase.opened(rawA));
  final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
  await dbA.select(dbA.products).get();
  await dbB.select(dbB.products).get();
  return (
    dbA: dbA,
    dbB: dbB,
    rawA: rawA,
    rawB: rawB,
    path: dbPath,
  );
}

void disposeDualConnectionDatabases(
  ({
    AppDatabase dbA,
    AppDatabase dbB,
    sqlite3.Database rawA,
    sqlite3.Database rawB,
    String path,
  }) opened,
) {
  opened.rawA.dispose();
  opened.rawB.dispose();
  File(opened.path).deleteSync();
}

Future<PosSessionCloseResult> closeSession({
  required AppDatabase db,
  required int sessionId,
  required double closingCash,
  String? notes,
  int? closedByUserId,
  String? idempotencyKey,
}) {
  return closeService(db).processClose(
    idempotencyKey: idempotencyKey ?? b26SessionCloseKey('auto'),
    sessionId: sessionId,
    closingCash: closingCash,
    notes: notes,
    closedByUserId: closedByUserId,
  );
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.test();
    await db.select(db.products).get();
  });

  tearDown(() async {
    await db.close();
  });

  group('B26 POS session close hardening', () {
    test('1) fresh close succeeds; row closed; fields persisted', () async {
      final sessionId = await insertOpenSession(db, openingCash: 50);
      final key = b26SessionCloseKey('fresh');
      final result = await closeSession(
        db: db,
        sessionId: sessionId,
        closingCash: 50,
        notes: 'shift end',
        closedByUserId: 1,
        idempotencyKey: key,
      );
      expect(result.idempotentReplay, isFalse);
      expect(await countOpenSessions(db), 0);
      final row = await db.salesDao.getSessionById(sessionId);
      expect(row?.isClosed, isTrue);
      expect(row?.closingCash, 50);
      expect(row?.expectedCashAmount, 50);
      expect(row?.cashDifference, 0);
      expect(row?.notes, 'shift end');
      expect(row?.closedByUserId, 1);
      expect(row?.closedAt, isNotNull);
    });

    test('2) double submit same key → one mutation, one log', () async {
      final sessionId = await insertOpenSession(db);
      final key = b26SessionCloseKey('double');
      final svc = closeService(db);
      final first = await svc.processClose(
        idempotencyKey: key,
        sessionId: sessionId,
        closingCash: 100,
      );
      final second = await svc.processClose(
        idempotencyKey: key,
        sessionId: sessionId,
        closingCash: 100,
      );
      expect(first.idempotentReplay, isFalse);
      expect(second.idempotentReplay, isTrue);
      expect(await countOpenSessions(db), 0);
      expect(await countSessionCloseActivityLogs(db), 1);
    });

    test('3) retry after commit same key + fingerprint → replay', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b26_retry_${DateTime.now().microsecondsSinceEpoch}.db';
      final raw1 = sqlite3.sqlite3.open(dbPath);
      final persisted = AppDatabase.test(NativeDatabase.opened(raw1));
      await persisted.select(persisted.products).get();
      final sessionId = await insertOpenSession(persisted, openingCash: 75);
      final key = b26SessionCloseKey('retry');
      await closeService(persisted).processClose(
        idempotencyKey: key,
        sessionId: sessionId,
        closingCash: 75,
        notes: 'n',
      );
      await persisted.close();
      raw1.dispose();

      final raw2 = sqlite3.sqlite3.open(dbPath);
      final reconnected = AppDatabase.test(NativeDatabase.opened(raw2));
      addTearDown(() async {
        await reconnected.close();
        raw2.dispose();
        File(dbPath).deleteSync();
      });
      await reconnected.select(reconnected.products).get();
      final replay = await closeService(reconnected).processClose(
        idempotencyKey: key,
        sessionId: sessionId,
        closingCash: 75,
        notes: 'n',
      );
      expect(replay.idempotentReplay, isTrue);
      expect(await countSessionCloseActivityLogs(reconnected), 1);
    });

    test('4) same-key replay explicit', () async {
      final sessionId = await insertOpenSession(db);
      final key = b26SessionCloseKey('explicit-replay');
      final svc = closeService(db);
      await svc.processClose(
        idempotencyKey: key,
        sessionId: sessionId,
        closingCash: 120,
      );
      final replay = await svc.processClose(
        idempotencyKey: key,
        sessionId: sessionId,
        closingCash: 120,
      );
      expect(replay, isA<PosSessionCloseResult>());
      expect(replay.idempotentReplay, isTrue);
      expect(replay.closingCash, 120);
    });

    test('5) same key, changed closing cash → conflict', () async {
      final sessionId = await insertOpenSession(db);
      final key = b26SessionCloseKey('conflict-cash');
      final svc = closeService(db);
      await svc.processClose(
        idempotencyKey: key,
        sessionId: sessionId,
        closingCash: 100,
      );
      final outcome = await captureClose(svc.processClose(
        idempotencyKey: key,
        sessionId: sessionId,
        closingCash: 200,
      ));
      expect(outcome, isA<PosSessionCloseIdempotencyConflictException>());
      final row = await db.salesDao.getSessionById(sessionId);
      expect(row?.closingCash, 100);
    });

    test('6) dual connection different fingerprint → one winner, one conflict',
        () async {
      final opened = await openDualConnectionDatabases();
      final sessionId = await insertOpenSession(opened.dbA, openingCash: 10);
      final gate = _ConditionalCloseRaceGate(participantCount: 2);
      try {
        final svcA = PosSessionCloseService(
          opened.dbA,
          beforeConditionalCloseHook: gate.arrive,
        );
        final svcB = PosSessionCloseService(
          opened.dbB,
          beforeConditionalCloseHook: gate.arrive,
        );
        final futureA = captureClose(svcA.processClose(
          idempotencyKey: b26SessionCloseKey('race-a'),
          sessionId: sessionId,
          closingCash: 10,
        ));
        final futureB = captureClose(svcB.processClose(
          idempotencyKey: b26SessionCloseKey('race-b'),
          sessionId: sessionId,
          closingCash: 20,
        ));
        await gate.waitUntilAllArrived();
        gate.release();
        final results = await Future.wait<Object?>([futureA, futureB]);
        final successes =
            results.whereType<PosSessionCloseResult>().toList();
        final conflicts = results
            .whereType<PosSessionCloseIdempotencyConflictException>()
            .toList();
        expect(successes.length, 1);
        expect(conflicts.length, 1);
        expect(successes.single.idempotentReplay, isFalse);
        expect(await countSessionCloseActivityLogs(opened.dbA), 1);
        final row = await opened.dbA.salesDao.getSessionById(sessionId);
        expect(row?.isClosed, isTrue);
        expect(row?.closingCash, isIn([10.0, 20.0]));
      } finally {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionDatabases(opened);
      }
    });

    test('7) dual connection same fingerprint + gate → one fresh, one replay',
        () async {
      final opened = await openDualConnectionDatabases();
      final sessionId = await insertOpenSession(opened.dbA, openingCash: 11);
      final key = b26SessionCloseKey('same-fp-race');
      final gate = _ConditionalCloseRaceGate(participantCount: 2);
      try {
        final svcA = PosSessionCloseService(
          opened.dbA,
          beforeConditionalCloseHook: gate.arrive,
        );
        final svcB = PosSessionCloseService(
          opened.dbB,
          beforeConditionalCloseHook: gate.arrive,
        );
        final futureA = captureClose(svcA.processClose(
          idempotencyKey: key,
          sessionId: sessionId,
          closingCash: 11,
          closedByUserId: 1,
        ));
        final futureB = captureClose(svcB.processClose(
          idempotencyKey: key,
          sessionId: sessionId,
          closingCash: 11,
          closedByUserId: 1,
        ));
        await gate.waitUntilAllArrived();
        gate.release();
        final results = await Future.wait<Object?>([futureA, futureB]);
        final successes =
            results.whereType<PosSessionCloseResult>().toList();
        expect(successes.length, 2);
        expect(successes.where((r) => r.idempotentReplay).length, 1);
        expect(successes.where((r) => !r.idempotentReplay).length, 1);
        expect(await countOpenSessions(opened.dbA), 0);
        expect(await countSessionCloseActivityLogs(opened.dbA), 1);
        final fresh = successes.singleWhere((r) => !r.idempotentReplay);
        final replay = successes.singleWhere((r) => r.idempotentReplay);
        expect(replay.sessionId, fresh.sessionId);
        expect(fresh.closingCash, 11);
        expect(fresh.expectedCashAmount, 11);
        expect(fresh.cashDifference, 0);
        final row = await opened.dbA.salesDao.getSessionById(sessionId);
        expect(row?.isClosed, isTrue);
        expect(row?.closingCash, 11);
        expect(row?.expectedCashAmount, 11);
        expect(row?.cashDifference, 0);
        expect(row?.closedByUserId, 1);
        expect(row?.notes, isNull);
        expect(row?.closedAt, isNotNull);
      } finally {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionDatabases(opened);
      }
    });

    test('8) already closed, new fingerprint → conflict', () async {
      final sessionId = await insertOpenSession(db);
      await closeSession(db: db, sessionId: sessionId, closingCash: 100);
      final outcome = await captureClose(closeSession(
        db: db,
        sessionId: sessionId,
        closingCash: 150,
        notes: 'different',
        idempotencyKey: b26SessionCloseKey('new-fp'),
      ));
      expect(outcome, isA<PosSessionCloseIdempotencyConflictException>());
    });

    test('9) session not found', () async {
      final outcome = await captureClose(
        closeService(db).processClose(
          idempotencyKey: b26SessionCloseKey('missing'),
          sessionId: 999999,
          closingCash: 1,
        ),
      );
      expect(outcome, isA<PosSessionNotFoundException>());
    });

    test('9b) invalid closedByUserId → typed error, session stays open', () async {
      final sessionId = await insertOpenSession(db, openingCash: 20);
      const invalidUserId = 999999;
      final outcome = await captureClose(
        closeService(db).processClose(
          idempotencyKey: b26SessionCloseKey('bad-user'),
          sessionId: sessionId,
          closingCash: 20,
          closedByUserId: invalidUserId,
        ),
      );
      expect(outcome, isA<PosSessionCloseInvalidClosedByUserException>());
      final row = await db.salesDao.getSessionById(sessionId);
      expect(row?.isClosed, isFalse);
      expect(row?.closingCash, isNull);
      expect(row?.expectedCashAmount, isNull);
      expect(row?.closedByUserId, isNull);
      expect(await countSessionCloseActivityLogs(db), 0);
    });

    test('10) activity insert failure → rollback, session remains open', () async {
      final sessionId = await insertOpenSession(db, openingCash: 5);
      final svc = PosSessionCloseService(
        db,
        beforeActivityLogHook: () async {
          throw StateError('forced activity failure');
        },
      );
      final outcome = await captureClose(svc.processClose(
        idempotencyKey: b26SessionCloseKey('act-fail'),
        sessionId: sessionId,
        closingCash: 5,
      ));
      expect(outcome, isA<StateError>());
      final row = await db.salesDao.getSessionById(sessionId);
      expect(row?.isClosed, isFalse);
      expect(row?.closingCash, isNull);
      expect(await countSessionCloseActivityLogs(db), 0);
    });

    test('11) SQLITE_BUSY then success', () async {
      final sessionId = await insertOpenSession(db);
      var calls = 0;
      final svc = PosSessionCloseService(
        db,
        beforeActivityLogHook: () async {
          calls++;
          if (calls == 1) {
            throw Exception('database is locked');
          }
        },
      );
      final result = await svc.processClose(
        idempotencyKey: b26SessionCloseKey('busy'),
        sessionId: sessionId,
        closingCash: 100,
      );
      expect(result.idempotentReplay, isFalse);
      expect(await countOpenSessions(db), 0);
      expect(await countSessionCloseActivityLogs(db), 1);
      expect(calls, greaterThanOrEqualTo(2));
    });

    test('12) SQLITE_BUSY exhausted', () async {
      final sessionId = await insertOpenSession(db);
      final svc = PosSessionCloseService(
        db,
        beforeActivityLogHook: () async {
          throw Exception('database is locked');
        },
      );
      final outcome = await captureClose(svc.processClose(
        idempotencyKey: b26SessionCloseKey('busy-exhaust'),
        sessionId: sessionId,
        closingCash: 100,
      ));
      expect(outcome, isA<Exception>());
      expect(outcome.toString(), contains('database is locked'));
      final row = await db.salesDao.getSessionById(sessionId);
      expect(row?.isClosed, isFalse);
    });

    test('13) metadata immutability — second close cannot change closing_cash',
        () async {
      final sessionId = await insertOpenSession(db);
      await closeSession(db: db, sessionId: sessionId, closingCash: 88);
      await captureClose(closeSession(
        db: db,
        sessionId: sessionId,
        closingCash: 999,
      ));
      final row = await db.salesDao.getSessionById(sessionId);
      expect(row?.closingCash, 88);
    });

    test('14) exactly one activity log', () async {
      final sessionId = await insertOpenSession(db);
      await closeSession(db: db, sessionId: sessionId, closingCash: 100);
      await closeSession(db: db, sessionId: sessionId, closingCash: 100);
      expect(await countSessionCloseActivityLogs(db), 1);
    });

    test('15) sticky UUID reused on simulated retry', () {
      var seq = 0;
      String nextKey() => 'key-${++seq}';
      final binding = CloseDialogIdempotencyBinding(initialKey: nextKey());
      final firstKey = binding.idempotencyKey;
      binding.syncClosingInputs(
        closingCash: 50,
        notes: null,
        generateUuid: nextKey,
      );
      expect(binding.idempotencyKey, firstKey);
      binding.syncClosingInputs(
        closingCash: 50,
        notes: null,
        generateUuid: nextKey,
      );
      expect(binding.idempotencyKey, firstKey);
      expect(seq, 1);
      binding.syncClosingInputs(
        closingCash: 51,
        notes: null,
        generateUuid: nextKey,
      );
      expect(binding.idempotencyKey, isNot(firstKey));
      expect(seq, 2);
    });

    test('16) fingerprint normalization: cash decimals + empty/null notes', () {
      final h1 = PosSessionCloseFingerprint.compute(
        sessionId: 1,
        closingCash: 10.123456789,
        notes: null,
        closedByUserId: 1,
      );
      final h2 = PosSessionCloseFingerprint.compute(
        sessionId: 1,
        closingCash: 10.123457,
        notes: '',
        closedByUserId: 1,
      );
      final h3 = PosSessionCloseFingerprint.compute(
        sessionId: 1,
        closingCash: 10.1234567,
        notes: '   ',
        closedByUserId: 1,
      );
      expect(h1, h2);
      expect(h2, h3);
      expect(PosSessionCloseFingerprint.normalizeNotes(null), isNull);
      expect(PosSessionCloseFingerprint.normalizeNotes(''), isNull);
      expect(PosSessionCloseFingerprint.normalizeNotes('  x  '), 'x');
    });

    test('17) schema remains 51 / no close idempotency table', () async {
      expect(db.schemaVersion, 51);
      final closeTable = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='pos_session_close_idempotency'",
        readsFrom: {},
      ).get();
      expect(closeTable, isEmpty);
    });

    // Cases 18–21: in-file boundary smoke only. Full B25/B24/B6/B5 regressions
    // are the separate suites in the combined 78-test verification run.

    test('18) regression boundary B25 open path intact', () async {
      final idx = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND name='uq_pos_sessions_one_open'",
        readsFrom: {},
      ).getSingleOrNull();
      expect(idx?.data['name'], 'uq_pos_sessions_one_open');
      final idemTable = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='pos_session_open_idempotency'",
        readsFrom: {},
      ).get();
      expect(idemTable, isNotEmpty);
      final result = await PosSessionOpenService(db).processOpen(
        idempotencyKey: b25SessionOpenKey('b26-reg-b25'),
        cashierName: 'Reg',
        openingCash: 1,
      );
      expect(result.idempotentReplay, isFalse);
      expect(await countOpenSessions(db), 1);
    });

    test('19) regression boundary B24 artifacts present on v51 schema', () async {
      final rows = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name LIKE '%settle%' OR name='customer_transactions'",
        readsFrom: {},
      ).get();
      expect(rows, isNotEmpty);
    });

    test('20) regression boundary B6 customer payment idempotency table', () async {
      final rows = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='customer_payment_idempotency'",
        readsFrom: {},
      ).get();
      expect(rows, isNotEmpty);
    });

    test('21) regression boundary B5 pos sale idempotency table', () async {
      final rows = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='pos_sale_idempotency'",
        readsFrom: {},
      ).get();
      expect(rows, isNotEmpty);
    });
  });
}
