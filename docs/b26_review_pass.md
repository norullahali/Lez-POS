# B26 Review Pass — POS Session Close Hardening

**Review date:** 2026-10-14
**Baseline HEAD:** `fb368f80eef14e9adbdfefe4907efdbffe21317e` (unchanged; no commit)
**Design source:** `docs/b26_design_review.md`
**Mode:** Audit only — no code/test/schema changes during this pass.

---

## Executive summary

Independent code review confirms B26 implements **Option A+** as approved: a single `PosSessionCloseService` owns the close transaction, conditional `UPDATE … AND is_closed = 0`, in-transaction live summary, fingerprint-based replay/conflict against the closed row, in-transaction authoritative activity log, bounded busy retry, and UI sticky UUID without DB persistence of the close key.

Production close paths were traced; no competing unconditional close remains in `lib/`. Regression suites were not re-run during this review pass (implementation verification reported **78/78**); static checks (`flutter analyze` on B26 lib surface, `git diff --check`) were re-verified.

---

## 1. Service authority

**File:** `lib/core/services/pos_session_close_service.dart`

| Requirement | Verdict | Evidence |
|-------------|---------|----------|
| Single orchestrator | Pass | Only `PosSessionCloseService.processClose` performs close mutation + authoritative audit. |
| Owns transaction | Pass | `db.transaction` wraps load, summary, conditional update, activity insert (L57–115). |
| Owns expected/difference/closedAt | Pass | L67–71 inside txn. |
| Conditional close | Pass | `closeOpenSessionIfStillOpen` (L77–85). |
| Replay/conflict | Pass | L63–64, L142–161, L87–94. |
| Busy retry | Pass | L55, L127–131, L192–201. |
| Authoritative activity | Pass | `activityLogsDao.insertLog` in txn (L101–106, L171–189). |

**Production call graph:**

`SessionCloseDialog._close` → `PosSessionNotifier.closeSession` (`pos_provider.dart` L56–80) → `PosRepository.closeSession` (L38–51) → `PosSessionCloseService.processClose` → `SalesDao.closeOpenSessionIfStillOpen` (`sales_dao.dart` L34–55).

**Search:** `ActivityTypes.sessionClosed` only in close service. No `ActivityLoggerService` on POS close in `lib/features/pos/`. Only `update(posSessions)` in `sales_dao.dart` for runtime close.

**Migration-only UPDATE:** B25 repair (`app_database.dart` L1307–1317), `WHERE is_closed = 0` only.

---

## 2. Conditional close atomicity

DAO: `id` + `is_closed = 0` filter (`sales_dao.dart` L43–44). Service re-reads on `affected == 0`; no blind AlreadyClosed success.

---

## 3. Live summary / TOCTOU

`getSessionSummary` at service L67 inside same transaction. Provider does not authoritatively pre-compute expected cash for persist. Post-close provider summary is display-only (L72–78). Dialog pre-close summary may be stale — design §22 accepted.

---

## 4. Immutability

Closed rows cannot be updated via production close path. Tests 5, 8, 13.

---

## 5. Replay / fingerprint

Includes sessionId, 6dp cash, normalized notes, closedByUserId. Excludes derived fields. SHA-256 JSON. Persisted notes normalized. Replay returns early without UPDATE or activity. Test 16.

---

## 6–7. Concurrency

Tests 6–7 use `_ConditionalCloseRaceGate` on `beforeConditionalCloseHook` — no `Future.delayed`. Same-intent: 1 fresh + 1 replay + 1 log. Different-intent: 1 success + 1 conflict + 1 log. Test 7 does not pin persisted row fields (low gap).

---

## 8–9. Retry / different intent after close

Test 3: reconnect replay via fingerprint. Tests 5, 8: conflict without mutation.

---

## 10–11. Activity atomicity / one log

Single transaction for UPDATE + insert. Test 10 verifies rollback state. Tests 2, 6–7, 14 cover log counts.

---

## 12. Busy retry

8 attempts; whole txn retried; conflict/not-found not retried. Exhausted busy rethrows underlying Exception (test 12), B25-aligned.

---

## 13–15. Errors, UI, wiring

Typed not-found and conflict; replay via result flag. UI sticky UUID, in-flight guard, conflict snackbar. Repository/provider thin; no competing close txn.

---

## 16. Bypass search

No production path mutates closed session close-metadata.

---

## 17–18. Regression / schema

B25 open untouched in diff. Reported 78/78. v51; no close idempotency table.

---

## 19–22. Tests, hygiene, scope, design

Tests prove invariants; minor gaps SF-04/SF-05. Analyzer clean; diff check clean. Matches Option A+; unused `idempotencyKey` in service is intentional per design.

---

## B26 REVIEW VERDICT:

**REVIEW PASS WITH SHOULD-FIX**

### A. Findings

1. **SF-01:** `idempotencyKey` unused in service (fingerprint replay only) — per v51 design.
2. **SF-02:** `debugPrint` on unexpected errors (`pos_session_close_service.dart` L133).
3. **SF-03:** Invalid `closedByUserId` → raw FK error, not typed.
4. **SF-04:** Tests 19–21 are boundary smoke, not full B24/B6/B5 re-runs.
5. **SF-05:** Test 7 could assert persisted metadata after same-intent race.

### B. Severity

All **Low**. No blocker.

### C. References

`pos_session_close_service.dart` L55–201; `sales_dao.dart` L33–55; `pos_session_close_fingerprint.dart`; `session_dialog.dart` L237–281, L524–555; `pos_provider.dart` L56–80; `app_database.dart` L1307–1317.

### D. Required fixes

None for correctness. Optional hygiene/test polish for SF-02–SF-05.

### E. Test evidence

Reported B26 21/21, combined 78/78 (not re-run in this review).

### F. Regression evidence

Reported B25/B24/B6/B5 pass; B26 does not modify B25 open code.

### G. Schema evidence

v51; no close idempotency table.

### H. Scope evidence

4 modified lib files + new services/tests; HEAD `fb368f8`.

---

**Review complete.** Only this document was written. No commit, push, or code changes.
