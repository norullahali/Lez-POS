# B22 REVIEW PASS

**Date:** 2026-10-08  
**Mode:** REVIEW ONLY — no commit, push, stage, or code fixes  
**Baseline commit (pre-B22):** `53a86e6eea76e9adf15bbc46699890f937aeec12`

---

## Baseline

| Check | Result |
|-------|--------|
| `git branch --show-current` | `main` |
| `git rev-parse HEAD` | `53a86e6eea76e9adf15bbc46699890f937aeec12` |
| `git rev-parse origin/main` | `53a86e6eea76e9adf15bbc46699890f937aeec12` |
| Committed B22 work | **None** (B22 files untracked or unstaged) |
| `git diff --check` | **Clean** (CRLF warning on `app_database.g.dart` only) |

**Finding:** NONE — baseline matches specification.

---

## Production Path

### UPDATE

`ExpenseDialog._submit` (edit) → `expenseMutationSaveServiceProvider` → `ExpenseMutationSaveService.processUpdate` → one `db.transaction()` → idempotency lookup → replay/conflict → `ExpenseMutationInTransactionWriter.updateExpenseRowInTransaction` → in-txn update activity log → `preSealHook` (tests) → idempotency seal → commit.

### VOID

`ExpenseScreen._ActionButtonsState._confirmVoid` → `processVoid` → same pattern → conditional void write → in-txn **warning** void activity log → seal (skipped when `alreadyVoided`).

### Writers / bypass

| Path | Production writer |
|------|-------------------|
| UPDATE | **One:** `ExpenseMutationSaveService` + in-transaction writer |
| VOID | **One:** same |
| CREATE (B18) | **Unchanged:** `ExpenseCreationService` |

- `ExpenseRepository.updateExpense` / `voidExpense` removed; `@visibleForTesting` `updateExpenseForTest` / `voidExpenseForTest` delegate to the service.
- No production UI → repository mutation calls.
- `ExpensesDao.updateExpense` / `voidExpense` remain but are unused from `lib/`; writer uses Drift `update()` directly.
- No post-transaction `ActivityLoggerService` on expense update/void.

**Finding:** NONE.

---

## B18 Safety

| Item | Status |
|------|--------|
| `ExpenseCreationService` | No diff vs `53a86e6` |
| `expense_idempotency` | Unchanged (B18 table/DAO logic) |
| CREATE UI | Still `processCreate` in `ExpenseDialog` |
| B18 tests 13–14 | Use service-backed test helpers; ledger intent unchanged |

**Finding:** NONE.

---

## Idempotency

| Case | Behavior |
|------|----------|
| A. Same key + same fingerprint | Replay; no mutation, audit, or second seal (tests 2, 10) |
| B. Same key + different fingerprint | `ExpenseMutationSaveIdempotencyConflictException`; `operationType` checked |
| C. Different keys | Separate seals; void on already-voided + new key → no seal/audit (test 12) |
| D. Seal race | UNIQUE/PK → `_IdempotencySealRace` retry (tests 6–7, 14, 20) |
| E. Retry after failure | Sticky key; rollback leaves no seal; retry succeeds (tests 6, 14) |

**Finding:** NONE.

---

## Fingerprints

**UPDATE:** `operation`, `expenseId`, `categoryId`, `amount` (6 dp), date-only `expenseDate`/`paidAt`, normalized `notes`, `sessionId`, `updatedBy`; SHA-256 JSON. **VOID:** `operation`, `expenseId`, `voidedBy`. No idempotency key or volatile UI fields. Service normalizes dates/amount/notes before write (B18 family).

**Finding:** NONE.

---

## Transaction Atomicity

UPDATE and applied VOID: mutation + in-txn activity + seal in one transaction. `alreadyVoided`: no seal, no audit. Hook tests prove rollback (5, 13, 6, 14). Activity via `activityLogsDao.insertLog` inside txn.

**Finding:** NONE.

---

## Void Semantics

`is_voided` flag only; no delete/reversal row. Conditional void SQL; update blocked after void (test 15). Already voided + different key → no-op without extra audit (test 12). Summary excludes voided rows (tests 8–9).

**Finding:** NONE.

---

## Authorization

UI and service enforce `userId > 0` / `updatedBy` / `voidedBy` (tests 16–17). Fingerprints and activity logs use authenticated actor parameters.

**Finding:** NONE.

---

## UI Lifecycle

**UPDATE:** sticky UUID, fingerprint reset, `_saving` guard, success/conflict clear key, transient error retains key. **VOID:** sticky key, `_voidInFlight`, success/conflict clear, transient retains. No SharedPreferences.

**Finding:** NONE.

---

## Concurrency

Different-key updates: last-write-wins with void guard — accepted. Same-key dual connection: tested for UPDATE (test 7). Update vs void / void vs update with dual connections and barriers: **not tested** (design items 21–22). Code uses in-txn void checks and `WHERE is_voided = 0`; BEGIN IMMEDIATE not required.

**Finding:** **SHOULD-FIX** — add tests 21 and 22 (see Findings Summary).

---

## SQLite Error Handling

B21-style: extended codes 1555/2067 with table guard, BUSY/LOCKED backoff, seal-race retry, non-Exception wrap. No dedicated BUSY/LOCKED test.

**Finding:** **OPTIONAL** — missing test 32.

---

## Migration

v48→v49 additive; `expense_mutation_idempotency` + `emi_expense_record_idx`; schemaVersion 49; no backfill. Tests 18–19 cover table / fresh DB; index not asserted in test 18.

**Finding:** **OPTIONAL** — index assertion (item 29).

---

## Test Coverage

| Suite | Result (this review) |
|-------|----------------------|
| B22 | 20/20 PASS |
| B18 | 20/20 PASS |
| B21 | 22/22 PASS |
| B4–B10 | 147/147 PASS |

Matrix gaps: **21–22 missing**; partial 25–26, 29–30, 32 (see design matrix).

**Finding:** **SHOULD-FIX** (21–22); **OPTIONAL** (others).

---

## Regression

14 regression files: schema sentinel 49 only. B18 service/table unchanged. Executed suites pass; no regression from v49 or repository cutover observed.

**Finding:** NONE.

---

## Scope / Hygiene

Scoped to expense mutation protection + v49 + UI/repository. Untracked `docs/` and `tool/` excluded. No conflict markers. New B22 Dart files: UTF-8 without BOM (spot-check). B18 test diff adds UTF-8 BOM on first line — fix before commit.

**Finding:** **OPTIONAL** — B18 test BOM.

---

## Findings Summary

| ID | Severity | Topic |
|----|----------|--------|
| F1 | SHOULD-FIX | Missing test 21: dual-connection UPDATE vs VOID |
| F2 | SHOULD-FIX | Missing test 22: dual-connection VOID vs UPDATE |
| F3 | OPTIONAL | No BUSY/LOCKED test (32) |
| F4 | OPTIONAL | Migration test omits index check (29) |
| F5 | OPTIONAL | No UI auth widget tests (30) |
| F6 | OPTIONAL | UTF-8 BOM in B18 test file |

### F1 / F2 (SHOULD-FIX)

- **Issue:** Cross-path concurrency not automated.
- **Why:** Design matrix 21–22; production safety relies on txn ordering without proof.
- **Files:** `test/expense_mutation_save_protection_b22_test.dart`
- **Correction:** Add dual-connection tests with `preSealHook` / `Future.wait`; assert single void state, audit counts, idempotency rows, and update rejection when void wins.
- **Test:** New cases 21 and 22 in B22 suite.

---

## FINAL VERDICT

**B22 REVIEW: PASS WITH SHOULD-FIX**

No blockers. Add cross-path concurrency tests 21–22 before Final Audit. All other areas match approved design; regression suites executed here pass.