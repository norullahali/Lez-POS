import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/pos_session_already_open_exception.dart';
import 'package:lez_pos/core/services/pos_session_open_fingerprint.dart';
import 'package:lez_pos/core/services/pos_session_open_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/pos_session_open_result.dart';
import 'package:lez_pos/core/services/pos_session_open_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/pos_session_open_test_keys.dart';

Future<int> countOpenSessions(AppDatabase db) async {
  final row = await db.customSelect(
    'SELECT COUNT(*) AS cnt FROM pos_sessions WHERE is_closed = 0',
    readsFrom: {db.posSessions},
  ).getSingle();
  return row.data['cnt'] as int? ?? 0;
}

Future<int> countSessionOpenActivityLogs(AppDatabase db) async {
  return (await db.select(db.activityLogs).get()).length;
}

/// Ensures both connections finish idempotency lookup (miss) before INSERT.
class _SameKeyInsertRaceGate {
  _SameKeyInsertRaceGate({required this.participantCount});

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

Future<Object?> captureOpen(Future<dynamic> future) async {
  try {
    return await future;
  } catch (e) {
    return e;
  }
}

PosSessionOpenService openService(AppDatabase db) => PosSessionOpenService(db);

Future<({
  AppDatabase dbA,
  AppDatabase dbB,
  sqlite3.Database rawA,
  sqlite3.Database rawB,
  String path,
})> openDualConnectionDatabases() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b25_race_${DateTime.now().microsecondsSinceEpoch}.db';
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

Future<AppDatabase> openMigratedFromV50({
  required int openSessionCount,
  List<double>? openingCashValues,
}) async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b25_v50_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement(
    'DROP INDEX IF EXISTS uq_pos_sessions_one_open',
  );
  await bootstrap.customStatement(
    'DROP TABLE IF EXISTS pos_session_open_idempotency',
  );
  await bootstrap.customStatement('PRAGMA user_version = 50');

  for (var i = 0; i < openSessionCount; i++) {
    final cash = openingCashValues != null && i < openingCashValues.length
        ? openingCashValues[i]
        : 100.0 + i;
    await bootstrap.into(bootstrap.posSessions).insert(
          PosSessionsCompanion(
            cashierName: Value('Cashier $i'),
            openingCash: Value(cash),
            openedAt: Value(DateTime.now().subtract(Duration(hours: i))),
            isClosed: const Value(false),
          ),
        );
  }
  await bootstrap.close();
  bootstrapHandle.dispose();

  final raw = sqlite3.sqlite3.open(dbPath);
  final db = AppDatabase.test(NativeDatabase.opened(raw));
  await db.select(db.products).get();
  addTearDown(() async {
    await db.close();
    raw.dispose();
    File(dbPath).deleteSync();
  });
  return db;
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

  group('B25 POS session open protection', () {
    test('1) fresh open succeeds', () async {
      final key = b25SessionOpenKey('fresh');
      final result = await openService(db).processOpen(
        idempotencyKey: key,
        cashierName: 'Test Cashier',
        openingCash: 500,
        createdByUserId: 1,
      );
      expect(result.idempotentReplay, isFalse);
      expect(await countOpenSessions(db), 1);
      final open = await db.salesDao.getOpenSession();
      expect(open?.id, result.sessionId);
    });

    test('2) duplicate submit same key replays', () async {
      final key = b25SessionOpenKey('dup');
      final svc = openService(db);
      final first = await svc.processOpen(
        idempotencyKey: key,
        cashierName: 'A',
        openingCash: 100,
      );
      final second = await svc.processOpen(
        idempotencyKey: key,
        cashierName: 'A',
        openingCash: 100,
      );
      expect(second.idempotentReplay, isTrue);
      expect(second.sessionId, first.sessionId);
      expect(await countOpenSessions(db), 1);
    });

    test('3) dual connection different keys — one open row', () async {
      final opened = await openDualConnectionDatabases();
      try {
        final svcA = openService(opened.dbA);
        final svcB = openService(opened.dbB);
        final results = await Future.wait([
          captureOpen(svcA.processOpen(
            idempotencyKey: b25SessionOpenKey('race-a'),
            cashierName: 'A',
            openingCash: 50,
          )),
          captureOpen(svcB.processOpen(
            idempotencyKey: b25SessionOpenKey('race-b'),
            cashierName: 'B',
            openingCash: 60,
          )),
        ]);
        final successes =
            results.whereType<PosSessionOpenResult>().toList();
        final failures = results
            .whereType<PosSessionAlreadyOpenException>()
            .toList();
        expect(successes.length, 1);
        expect(failures.length, 1);
        expect(await countOpenSessions(opened.dbA), 1);
      } finally {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionDatabases(opened);
      }
    });

    test('4) second open new key while session committed', () async {
      await openService(db).processOpen(
        idempotencyKey: b25SessionOpenKey('first'),
        cashierName: 'A',
        openingCash: 10,
      );
      final outcome = await captureOpen(openService(db).processOpen(
        idempotencyKey: b25SessionOpenKey('second'),
        cashierName: 'B',
        openingCash: 20,
      ));
      expect(outcome, isA<PosSessionAlreadyOpenException>());
      expect(await countOpenSessions(db), 1);
    });

    test('5) retry after commit same key replays', () async {
      final key = b25SessionOpenKey('retry');
      final svc = openService(db);
      final first = await svc.processOpen(
        idempotencyKey: key,
        cashierName: 'Retry',
        openingCash: 75,
      );
      final replay = await svc.processOpen(
        idempotencyKey: key,
        cashierName: 'Retry',
        openingCash: 75,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(replay.sessionId, first.sessionId);
      expect(await countOpenSessions(db), 1);
    });

    test('6) activity failure rolls back session and seal', () async {
      final svc = PosSessionOpenService(
        db,
        beforeActivityLogHook: () async {
          throw StateError('forced activity failure');
        },
      );
      final outcome = await captureOpen(svc.processOpen(
        idempotencyKey: b25SessionOpenKey('act-fail'),
        cashierName: 'X',
        openingCash: 1,
      ));
      expect(outcome, isA<StateError>());
      expect(await countOpenSessions(db), 0);
      expect(await db.select(db.posSessionOpenIdempotency).get(), isEmpty);
    });

    test('7) SQLITE_BUSY retry eventually succeeds', () async {
      var calls = 0;
      final svc = PosSessionOpenService(
        db,
        beforeActivityLogHook: () async {
          calls++;
          if (calls == 1) {
            throw Exception('database is locked');
          }
        },
      );
      final result = await svc.processOpen(
        idempotencyKey: b25SessionOpenKey('busy'),
        cashierName: 'Busy',
        openingCash: 5,
      );
      expect(result.idempotentReplay, isFalse);
      expect(await countOpenSessions(db), 1);
      expect(calls, greaterThanOrEqualTo(2));
    });

    test('8) existing open session blocks new key', () async {
      await db.into(db.posSessions).insert(
            PosSessionsCompanion(
              cashierName: const Value('Legacy'),
              openingCash: const Value(999),
              isClosed: const Value(false),
            ),
          );
      final outcome = await captureOpen(openService(db).processOpen(
        idempotencyKey: b25SessionOpenKey('blocked'),
        cashierName: 'New',
        openingCash: 1,
      ));
      expect(outcome, isA<PosSessionAlreadyOpenException>());
      expect(await countOpenSessions(db), 1);
    });

    test('9) v51 migration repairs multiple open rows', () async {
      final migrated = await openMigratedFromV50(openSessionCount: 3);
      expect(await countOpenSessions(migrated), 1);
      final all = await migrated.select(migrated.posSessions).get();
      expect(all.length, 3);
      final closed = all.where((s) => s.isClosed).length;
      expect(closed, 2);
      final idx = await migrated.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND name='uq_pos_sessions_one_open'",
        readsFrom: {},
      ).getSingleOrNull();
      expect(idx?.data['name'], 'uq_pos_sessions_one_open');
      final outcome = await captureOpen(openService(migrated).processOpen(
        idempotencyKey: b25SessionOpenKey('post-mig'),
        cashierName: 'After',
        openingCash: 1,
      ));
      expect(outcome, isA<PosSessionAlreadyOpenException>());
    });

    test('10) activity log rollback leaves no orphan session', () async {
      final svc = PosSessionOpenService(
        db,
        beforeSealHook: () async {
          throw StateError('seal blocked');
        },
      );
      await expectLater(
        svc.processOpen(
          idempotencyKey: b25SessionOpenKey('seal-fail'),
          cashierName: 'Y',
          openingCash: 2,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await countOpenSessions(db), 0);
    });

    test('11) two users — second attempt rejected', () async {
      await openService(db).processOpen(
        idempotencyKey: b25SessionOpenKey('u1'),
        cashierName: 'User1',
        openingCash: 10,
        createdByUserId: 1,
      );
      final outcome = await captureOpen(openService(db).processOpen(
        idempotencyKey: b25SessionOpenKey('u2'),
        cashierName: 'User2',
        openingCash: 10,
        createdByUserId: 2,
      ));
      expect(outcome, isA<PosSessionAlreadyOpenException>());
    });

    test('12) two terminals same as dual connection', () async {
      final opened = await openDualConnectionDatabases();
      try {
        await openService(opened.dbA).processOpen(
          idempotencyKey: b25SessionOpenKey('t1'),
          cashierName: 'T1',
          openingCash: 1,
        );
        final outcome = await captureOpen(openService(opened.dbB).processOpen(
          idempotencyKey: b25SessionOpenKey('t2'),
          cashierName: 'T2',
          openingCash: 2,
        ));
        expect(outcome, isA<PosSessionAlreadyOpenException>());
      } finally {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionDatabases(opened);
      }
    });

    test('13) replay same key same fingerprint', () async {
      final key = b25SessionOpenKey('fp');
      expect(
        PosSessionOpenFingerprint.compute(openingCash: 42),
        isNotEmpty,
      );
      final svc = openService(db);
      await svc.processOpen(
        idempotencyKey: key,
        cashierName: 'FP',
        openingCash: 42,
      );
      final replay = await svc.processOpen(
        idempotencyKey: key,
        cashierName: 'FP',
        openingCash: 42,
      );
      expect(replay.idempotentReplay, isTrue);
    });

    test('14) same key changed opening cash conflicts', () async {
      final key = b25SessionOpenKey('conflict');
      final svc = openService(db);
      await svc.processOpen(
        idempotencyKey: key,
        cashierName: 'C',
        openingCash: 100,
      );
      final outcome = await captureOpen(svc.processOpen(
        idempotencyKey: key,
        cashierName: 'C',
        openingCash: 200,
      ));
      expect(outcome, isA<PosSessionOpenIdempotencyConflictException>());
      expect(await countOpenSessions(db), 1);
    });

    test('15) UNIQUE + idempotency race same key', () async {
      final opened = await openDualConnectionDatabases();
      final key = b25SessionOpenKey('same-key-race');
      final gate = _SameKeyInsertRaceGate(participantCount: 2);
      try {
        final svcA = PosSessionOpenService(
          opened.dbA,
          afterIdempotencyLookupHook: gate.arrive,
        );
        final svcB = PosSessionOpenService(
          opened.dbB,
          afterIdempotencyLookupHook: gate.arrive,
        );

        final futureA = captureOpen(svcA.processOpen(
          idempotencyKey: key,
          cashierName: 'Race',
          openingCash: 11,
        ));
        final futureB = captureOpen(svcB.processOpen(
          idempotencyKey: key,
          cashierName: 'Race',
          openingCash: 11,
        ));

        await gate.waitUntilAllArrived();
        gate.release();

        final results = await Future.wait<Object?>([futureA, futureB]);
        expect(
          results.whereType<PosSessionAlreadyOpenException>(),
          isEmpty,
          reason: 'same-key loser must replay, not AlreadyOpen',
        );
        final successes =
            results.whereType<PosSessionOpenResult>().toList();
        expect(successes.length, 2);
        expect(successes.map((r) => r.sessionId).toSet().length, 1);
        expect(successes.where((r) => r.idempotentReplay).length, 1);
        expect(successes.where((r) => !r.idempotentReplay).length, 1);
        expect(await countOpenSessions(opened.dbA), 1);
        expect(
          (await opened.dbA.select(opened.dbA.posSessionOpenIdempotency).get())
              .length,
          1,
        );
        expect(await countSessionOpenActivityLogs(opened.dbA), 1);
      } finally {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionDatabases(opened);
      }
    });

    test('expression UNIQUE index allows multiple closed sessions', () async {
      await db.into(db.posSessions).insert(
            PosSessionsCompanion(
              cashierName: const Value('Old'),
              openingCash: const Value(0),
              isClosed: const Value(true),
              closedAt: Value(DateTime.now()),
            ),
          );
      await openService(db).processOpen(
        idempotencyKey: b25SessionOpenKey('after-closed'),
        cashierName: 'New',
        openingCash: 5,
      );
      expect(await countOpenSessions(db), 1);
      final total = await db.select(db.posSessions).get();
      expect(total.length, greaterThanOrEqualTo(2));
    });
  });
}
