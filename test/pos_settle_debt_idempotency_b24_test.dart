import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/features/pos/settle_debt_idempotency.dart';

void main() {
  group('PosSettleDebtIdempotencyState (B24)', () {
    late PosSettleDebtIdempotencyState state;
    var uuidSeq = 0;

    String nextKey() => 'b24-test-key-${++uuidSeq}';

    setUp(() {
      state = PosSettleDebtIdempotencyState();
      uuidSeq = 0;
    });

    test('1) new intent creates one key', () {
      final key = state.prepareKey(
        customerId: 10,
        amount: 100,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      expect(key, 'b24-test-key-1');
      expect(state.idempotencyKey, key);
    });

    test('2) same intent retry reuses exactly the same key', () {
      final first = state.prepareKey(
        customerId: 10,
        amount: 50,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      final second = state.prepareKey(
        customerId: 10,
        amount: 50,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      expect(second, first);
      expect(uuidSeq, 1);
    });

    test('3) success clears key', () {
      state.prepareKey(
        customerId: 1,
        amount: 20,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      state.onSuccessfulPayment();
      expect(state.idempotencyKey, isNull);
      expect(state.boundCustomerId, isNull);
      expect(state.boundAmount, isNull);
      expect(state.boundNote, isNull);
    });

    test('4) idempotentReplay path uses onSuccessfulPayment and clears key', () {
      state.prepareKey(
        customerId: 1,
        amount: 20,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      state.onSuccessfulPayment();
      expect(state.idempotencyKey, isNull);
    });

    test('5) generic failure retains key (no success/conflict handler)', () {
      state.prepareKey(
        customerId: 2,
        amount: 30,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      expect(state.idempotencyKey, isNotNull);
      expect(state.boundCustomerId, 2);
    });

    test('6) customer change invalidates key', () {
      final first = state.prepareKey(
        customerId: 10,
        amount: 40,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      final second = state.prepareKey(
        customerId: 11,
        amount: 40,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      expect(second, isNot(first));
      expect(uuidSeq, 2);
    });

    test('7) amount change invalidates key', () {
      final first = state.prepareKey(
        customerId: 10,
        amount: 40,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      final second = state.prepareKey(
        customerId: 10,
        amount: 41,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      expect(second, isNot(first));
      expect(uuidSeq, 2);
    });

    test('7b) amount within B6 tolerance reuses key', () {
      final first = state.prepareKey(
        customerId: 10,
        amount: 40,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      final second = state.prepareKey(
        customerId: 10,
        amount: 40.00005,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      expect(second, first);
      expect(uuidSeq, 1);
    });

    test('8) fixed POS note remains correctly bound', () {
      state.prepareKey(
        customerId: 5,
        amount: 10,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      expect(state.boundNote, kPosSettleDebtNote);
      expect(
        state.matchesBoundIntent(
          customerId: 5,
          amount: 10,
          note: kPosSettleDebtNote,
        ),
        isTrue,
      );
    });

    test('8b) note change invalidates key', () {
      final first = state.prepareKey(
        customerId: 5,
        amount: 10,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      final second = state.prepareKey(
        customerId: 5,
        amount: 10,
        note: 'other note',
        generateUuid: nextKey,
      );
      expect(second, isNot(first));
    });

    test('9) conflict resets key/intent', () {
      state.prepareKey(
        customerId: 1,
        amount: 15,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      state.onIdempotencyConflict();
      expect(state.idempotencyKey, isNull);
    });

    test('10) second independent intent after success gets new key', () {
      final first = state.prepareKey(
        customerId: 1,
        amount: 15,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      state.onSuccessfulPayment();
      final second = state.prepareKey(
        customerId: 1,
        amount: 15,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      expect(second, isNot(first));
      expect(uuidSeq, 2);
    });

    test('12) key is not created until prepareKey (no build lifecycle)', () {
      expect(state.idempotencyKey, isNull);
      state.prepareKey(
        customerId: 1,
        amount: 1,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      expect(state.idempotencyKey, isNotNull);
    });

    test('13) dialog cancel does not destroy pending retry intent', () {
      final key = state.prepareKey(
        customerId: 3,
        amount: 25,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      // Cancel path: no resetAttempt / onSuccess / onConflict
      final retry = state.prepareKey(
        customerId: 3,
        amount: 25,
        note: kPosSettleDebtNote,
        generateUuid: nextKey,
      );
      expect(retry, key);
      expect(uuidSeq, 1);
    });

    test('11) in-flight blocks duplicate submit start', () {
      expect(canStartSettleDebtSubmit(inFlight: false), isTrue);
      expect(canStartSettleDebtSubmit(inFlight: true), isFalse);
    });
  });
}
