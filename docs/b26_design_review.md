# B26 Design Review

## 1. Executive Summary

**B26-C01 — POS session close hardening** replaces the thin DAO update + post-commit activity logger with an **authoritative close service** that enforces **open → closed exactly once**, **immutable close metadata**, **transactional audit**, **sticky-request replay**, and **bounded SQLITE_BUSY retry**.

**Selected approach:** **Option A+ — Authoritative conditional close** (conditional `UPDATE ... AND is_closed = 0`, in-transaction summary + activity, fingerprint-based replay against the persisted closed row). **No new idempotency table. Schema remains v51.**

## 2. Baseline

| Item | Value |
|------|-------|
| Branch | `main` |
| HEAD | `fb368f80eef14e9adbdfefe4907efdbffe21317e` (`fb368f8`) |
| Schema | **51** |
| B25 | CLOSED (session open) |
| Mode | Design only — no code/schema/test edits |
| Discovery | `docs/b26_discovery_report.md` — **READY FOR DESIGN REVIEW** |

## 3. Current Close Architecture

```
PosScreen → SessionCloseDialog._close
  → PosSessionNotifier.closeSession
      → getSessionSummary (outside txn)
      → expectedCash / difference computed in provider
      → PosRepository.closeSession → SalesDao.closeSession
          UPDATE pos_sessions SET is_closed=1, ... WHERE id = ?
      → invalidateSelf()
      → ActivityLoggerService.logInfo(sessionClosed)  // swallows errors
```

**Authoritative persisted close fields today** (`pos_sessions_table.dart`, `sales_dao.dart`, `pos_provider.dart`):

| Field | Source at close |
|-------|-----------------|
| `sessionId` | Active session from provider state |
| `closingCash` | User input (actual count) |
| `notes` | User input (optional) |
| `closedByUserId` | `authProvider.valueOrNull?.user?.id` (nullable) |
| `expectedCashAmount` | `session.openingCash + summary['cash']` (derived) |
| `cashDifference` | `closingCash - expectedCashAmount` (derived) |
| `closedAt` | `DateTime.now()` at UPDATE |
| `isClosed` | set `true` |

**Not user inputs:** `openedAt`, `openingCash`, `cashierName`, dialog display totals.

**TOCTOU today:** summary read occurs **before** the close UPDATE; a sale during the dialog can make stored `expectedCashAmount` stale relative to user expectation. B26 **must** recompute summary **inside** the close transaction immediately before UPDATE.

## 4. Business Invariants (I1–I15)

| ID | Invariant |
|----|-----------|
| I1 | OPEN → CLOSED transition at most **once** per session row |
| I2 | After close, `closing_cash` immutable |
| I3 | After close, `cash_difference` immutable |
| I4 | After close, `notes` immutable (for a given successful close) |
| I5 | After close, `closed_at` immutable |
| I6 | After close, `closed_by_user_id` immutable |
| I7 | Exactly **one** authoritative `sessionClosed` activity log per successful close |
| I8 | Close mutation + activity log **same transaction** |
| I9 | Retry of **same close intent** → replay (no second mutation/log) |
| I10 | **Different** close intent on already-closed session → typed reject |
| I11 | Double-submit cannot apply two successful close mutations |
| I12 | Concurrent connections cannot overwrite close metadata |
| I13 | SQLITE_BUSY/LOCKED bounded retry (B-series pattern) |
| I14 | B25 session open unchanged |
| I15 | No unnecessary schema complexity |

## 5. Option A Analysis — Minimal conditional close

**Mechanism:** `UPDATE ... WHERE id = ? AND is_closed = 0` inside `db.transaction`; `activityLogsDao.insertLog` in same txn; on `rowsAffected == 0`, re-read session and classify (replay vs conflict vs not found).

**Pros:** No migration; closed row is natural terminal seal; minimal surface.

**Cons:** Replay identity must be defined without a dedicated table — **resolved** by comparing **close fingerprint** to persisted closed columns (see §8).

**Verdict:** **Recommended base** — close differs from open: only one terminal outcome per session lifetime; the row **is** the durable result.

## 6. Option B Analysis — `pos_session_close_idempotency` (v52)

**Mechanism:** B25-style table: key → fingerprint → sessionId; seal last.

**Pros:** Symmetric with B25/B6; explicit cross-request replay map; same-key dual-connection recovery identical to B25 SF-01.

**Cons:** Redundant with immutable closed row for terminal mutation; extra migration/DAO; violates I15 unless proven necessary.

**Verdict:** **Not selected** — replay and conflict can be determined from **conditional UPDATE + closed-row fingerprint match** without a second durable store.

## 7. Option C Analysis — Hybrid (conditional + sticky UUID only)

**Mechanism:** UI UUID without DB seal; conditional UPDATE only.

**Cons:** UUID alone does not survive all replay paths; without row comparison or table, `rowsAffected == 0` cannot distinguish same-intent replay from different-intent rejection reliably.

**Verdict:** **Insufficient alone** — sticky UUID is **required UI** but must pair with **service-layer fingerprint + closed-row comparison** (Option A+).

## 8. Selected Design — Option A+ (Authoritative Conditional Close Service)

**Name:** `PosSessionCloseService` (canonical close orchestrator).

**Core ideas:**

1. **DB authority:** conditional close UPDATE is the single mutation gate (`is_closed = 0`).
2. **Intent fingerprint:** hash of operator-supplied close intent (not derived snapshot fields).
3. **Replay:** if session already closed and fingerprint **matches** persisted close columns → `idempotentReplay: true`.
4. **Conflict:** if closed and fingerprint **mismatches** → `PosSessionCloseIdempotencyConflictException`.
5. **Sticky UUID:** UI idempotency key passed to service for logging/correlation and future extension; **replay classification uses fingerprint vs row**, not key alone (key + fingerprint both required for conflict detection if key ever stored — **not stored in v1**).
6. **In-transaction summary** for `expectedCashAmount` / `cashDifference`.

**Why not Option B:** Close is **idempotent by session state** once closed. A idempotency table duplicates data already on `pos_sessions`. Open needed a table because many sessions over time share no single row seal until insert completes.

## 9. Why Selected Design Wins

| Criterion | A+ |
|-----------|-----|
| I1–I6 | Conditional UPDATE + no update path for closed rows |
| I7–I8 | Activity DAO inside txn |
| I9–I12 | 0-row UPDATE → re-read + fingerprint compare; same as B25 SF-01 pattern |
| I13 | Retry loop on busy/locked |
| I14 | No B25 objects touched |
| I15 | **No schema change** |

## 10. Business Fingerprint

**Include (operator intent):**

- `sessionId` (int)
- `closingCash` — normalized 6 decimal places (match B25 cash rounding)
- `notes` — normalized: `null` and `''` treated consistently (document single rule in implementation, e.g. empty → null in JSON)
- `closedByUserId` — nullable int (preserve current auth semantics)

**Exclude (derived or generated at commit):**

- `expectedCashAmount` — computed in txn from live summary
- `cashDifference` — computed from closingCash and expected
- `closedAt` — set once at successful UPDATE inside txn
- `openingCash`, sales summary totals — inputs to derivation only

**Fingerprint function:** `PosSessionCloseFingerprint.compute(...)` → SHA-256 of stable JSON (mirror B25 style).

**Match for replay** compares fingerprint to a hash recomputed from **persisted** `closing_cash`, `notes`, `closed_by_user_id`, and `sessionId` after close — not idempotency key alone.

## 11. Transaction Boundary

```
PosSessionCloseService.processClose(
  idempotencyKey,   // from UI; not persisted in v51 design
  sessionId,
  closingCash,
  notes,
  closedByUserId,
):
  fingerprint = compute(...)

  for attempt in bounded retries:
    try:
      return db.transaction(() async {
        row = SELECT session BY id

        if row missing → throw PosSessionNotFoundException

        if row.isClosed:
          if fingerprintMatchesClosedRow(row, fingerprint):
            return CloseResult(replay: true, sessionId, snapshot fields)
          else:
            throw PosSessionCloseIdempotencyConflictException

        summary = getSessionSummary(sessionId)  // inside txn
        expected = row.openingCash + summary.cash
        difference = closingCash - expected
        closedAt = DateTime.now()

        affected = UPDATE pos_sessions SET
          is_closed=1, closing_cash, expected_cash_amount,
          cash_difference, closed_at, closed_by_user_id, notes
          WHERE id = ? AND is_closed = 0

        if affected == 0:
          // concurrency loser — re-read (B25 SF-01 analogue)
          re-read row → replay or conflict or retry seal race

        activityLogsDao.insertLog(sessionClosed, entityId=sessionId, metadata...)

        return CloseResult(replay: false, ...)
      })
    catch busy/locked → backoff continue
    catch conflict/notFound → rethrow
```

**No idempotency seal row** in v51 design.

**Provider responsibility move:** remove pre-txn summary from notifier; pass `sessionId`, `closingCash`, `notes`; service owns expected/difference.

## 12. Concurrency Model

| Scenario | Behavior |
|----------|----------|
| A. Same intent, dual connection | One UPDATE succeeds; loser `affected=0` → re-read → **replay** |
| B. Different intent, same session | First wins; second `affected=0` → fingerprint mismatch → **Conflict** (or AlreadyClosed if design maps “different intent on closed” to conflict exception) |
| C. Retry after commit | Session closed + fingerprint match → **replay**, no activity |
| D. New request on closed session | Mismatch → **Conflict**; optional `PosSessionAlreadyClosedException` when no idempotency key correlation needed for UX |
| E. Activity failure | Txn rollback → session stays open |
| F. SQLITE_BUSY | Bounded retry entire txn |

**Deterministic tests:** `afterPreCloseCheckHook` / gate pattern mirroring B25 `afterIdempotencyLookupHook` — **not** `Future.delayed`.

## 13. Retry Model

- Max **8** attempts (align B25/B6).
- Retry only **SQLITE_BUSY / SQLITE_LOCKED**.
- Do **not** retry conflict, not found, or validation errors.
- Do **not** treat `affected=0` as busy — classify via re-read.

## 14. Error Model

| Outcome | Type / result |
|---------|----------------|
| Fresh success | `PosSessionCloseResult(idempotentReplay: false, ...)` |
| Replay | `PosSessionCloseResult(idempotentReplay: true, ...)` |
| Already closed, different intent | `PosSessionCloseIdempotencyConflictException` |
| Session not found | `PosSessionNotFoundException` |
| Busy exhausted | Rethrow / wrapped Exception (consistent with B25) |
| Unexpected DB error | Propagate — **never** map to AlreadyClosed |

Optional UX alias: `PosSessionAlreadyClosedException` for “session is closed and you are not replaying” — use **only** when fingerprint mismatches and UI should refresh session state (mirror B25 AlreadyOpen).

## 15. Activity / Audit Model

- **Forbidden for authoritative close:** `ActivityLoggerService.logInfo` on close path in `PosSessionNotifier`.
- **Required:** `activityLogsDao.insertLog` inside close transaction.
- Fields: `ActivityTypes.sessionClosed`, `ActivityCategories.sessions`, `entityType: pos_session`, `entityId: sessionId`, metadata JSON: `closingCash`, `expectedCash`, `difference` (from txn-computed values).
- **Replay:** return before activity insert (early branch on already-closed matching fingerprint).

## 16. UI Key Lifecycle

**Owner:** `SessionCloseDialog` state (`initState` generates UUID v4).

| Event | Key behavior |
|-------|----------------|
| New dialog | New UUID |
| Retry after transient error | Reuse UUID |
| Success (fresh or replay) | Dialog pops; key discarded |
| Conflict | Snackbar; user must cancel dialog → new intent → new UUID |
| `closingCash` or `notes` changed materially | Regenerate UUID (listener, mirror B24 amount binding) |
| In-flight | `_isLoading` disables confirm |

Pass `idempotencyKey` to `closeSession`. **No SharedPreferences.**

## 17. Schema Decision

**NO SCHEMA CHANGE — remain at v51.**

Justification: terminal conditional UPDATE + immutable closed row provides durable replay anchor; no backfill; no new indexes required beyond existing `ps_status_idx`.

## 18. Migration

**Not required.**

Fresh installs: unchanged v51 path from B25.

Interrupted state: N/A.

## 19. Test Matrix (21 cases)

| # | Test |
|---|------|
| 1 | Fresh close succeeds; row closed; fields persisted |
| 2 | Double submit same key → one mutation, one log |
| 3 | Retry after commit same key + fingerprint → replay |
| 4 | Same-key replay explicit |
| 5 | Same key, changed closing cash → conflict |
| 6 | Dual connection different fingerprint → one winner, one conflict |
| 7 | Dual connection same fingerprint + gate → one fresh, one replay |
| 8 | Already closed, new fingerprint → conflict |
| 9 | Session not found |
| 10 | Activity insert failure → rollback, still open |
| 11 | SQLITE_BUSY then success |
| 12 | SQLITE_BUSY exhausted |
| 13 | Metadata immutability — second close attempt cannot change closing_cash |
| 14 | Exactly one activity log |
| 15 | Sticky UUID reused on simulated retry (unit/helper) |
| 16 | Fingerprint normalization (cash decimals, empty notes) |
| 17 | (N/A migration) — assert schema still 51 / no close table |
| 18 | Regression B25 16/16 |
| 19 | Regression B24 15/15 |
| 20 | Regression B6 15/15 |
| 21 | Regression B5 11/11 |

File: `test/pos_session_close_b26_test.dart` (+ optional `test/support/pos_session_close_test_keys.dart`).

## 20. Expected File Surface

| Layer | Files (expected) |
|-------|------------------|
| New service | `pos_session_close_service.dart`, `pos_session_close_fingerprint.dart`, `pos_session_close_result.dart`, exceptions (`already_closed`, `conflict`, `not_found`) |
| DAO | `sales_dao.dart` — conditional close method; **no** unconditional close in production path |
| Wiring | `pos_repository.dart`, `pos_provider.dart`, `session_dialog.dart` |
| Tests | `test/pos_session_close_b26_test.dart`, support keys |
| **Not expected** | idempotency table/DAO, `app_database` version bump |

**Estimated count:** ~10–12 files (no generated schema churn if v51 holds).

## 21. Explicit Out-of-Scope

- B25 open path, `uq_pos_sessions_one_open`, open idempotency
- Session open UI
- POS checkout, B5/B6/B24 payment paths
- Backup/restore
- New POS authorization policy
- Refactors unrelated to close
- `pos_session_close_idempotency` table (deferred unless post-implementation review proves row-comparison insufficient)

## 22. Design Risk Review

| Challenge | Mitigation |
|-----------|------------|
| Two connections close same session? | Conditional UPDATE → one winner |
| Loser overwrites metadata? | **No** — 0-row update + re-read |
| Same-key retry replay? | Fingerprint vs closed row |
| Different-key rejected? | Fingerprint mismatch → conflict |
| Activity failure leaves closed session? | Rollback |
| Second activity log on replay? | Early return |
| Closed session mutable? | No UPDATE path without `is_closed=0` |
| BUSY duplicate close? | Full txn retry |
| Schema unnecessary? | **Yes — avoided** |
| B-series alignment? | Service + txn activity + busy loop + sticky UI |
| Deterministic tests? | Hook/barrier pattern |

**Open question (non-blocking):** Sales during close dialog change expected cash — B26 intentionally snapshots at txn time (correct for integrity); UI may show stale expected until close — **pre-existing**; optional future refresh, not B26.

## 23. Final Verdict

**DESIGN APPROVED**

Business invariants explicit; replay via fingerprint vs closed row; concurrency safe; atomic audit; schema justified as **unchanged**; scope bounded; test matrix defined.
