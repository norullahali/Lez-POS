# B22 FINAL AUDIT

**Date:** 2026-10-08  
**Mode:** FINAL AUDIT ONLY — no code, test, commit, push, or stage changes  
**Baseline commit:** `53a86e6eea76e9adf15bbc46699890f937aeec12` (schema v48)  
**B22 target schema:** v49

---

## Baseline

| Check | Result |
|-------|--------|
| Branch | `main` |
| `git rev-parse HEAD` | `53a86e6eea76e9adf15bbc46699890f937aeec12` |
| `git rev-parse origin/main` | `53a86e6eea76e9adf15bbc46699890f937aeec12` |
| Staged files | **None** |
| B22 work | **Uncommitted** (modified tracked + untracked B22 artifacts) |

**Finding:** NONE

---

## Final Invariants

| ID | Invariant | Evidence | Finding |
|----|-----------|----------|---------|
| I1 | One UPDATE intent → at most one durable update | Idempotency seal per key; replay skips work | NONE |
| I2 | One VOID intent → at most one durable void | Same; `alreadyVoided` skips seal/audit | NONE |
| I3 | Same key + same fp → pure replay | Service early return in txn (tests 2, 10) | NONE |
| I4 | Same key + diff fp → conflict, zero mutation | `ExpenseMutationSaveIdempotencyConflictException` (tests 3, 11) | NONE |
| I5 | Different key → legitimate ops per state | Tests 4, 12, 15, 21, 22 | NONE |
| I6 | Mutation + audit + seal atomic | Single `db.transaction()` in `ExpenseMutationSaveService` | NONE |
| I7 | Failure rolls back mutation, audit, seal | Tests 5, 6, 13, 14 | NONE |
| I8 | Auth userId > 0 UI + service | `expense_dialog.dart`, `expense_screen.dart`, tests 16–17 | NONE |
| I9 | Replay → no extra mutation/audit | Tests 2, 10; activity counts unchanged | NONE |
| I10 | Concurrent same-key → one durable effect | Test 7 (dual connection) | NONE |
| I11 | UPDATE vs VOID valid final state | Test 21 | NONE |
| I12 | VOID vs UPDATE valid final state | Test 22 | NONE |
| I13 | B18 CREATE isolated | No diff on `expense_creation_service.dart` / B18 idempotency table; CREATE path unchanged | NONE |

---

## Production Path

| Flow | Path | Finding |
|------|------|---------|
| UPDATE | `ExpenseDialog` → `expenseMutationSaveServiceProvider.processUpdate` → txn → row update → in-txn info audit → seal | NONE |
| VOID | `ExpenseScreen._ActionButtons` → `processVoid` → txn → conditional void → in-txn **warning** audit → seal | NONE |
| CREATE | `ExpenseDialog` → `ExpenseCreationService.processCreate` (B18) | NONE |

- No production `ExpenseRepository.updateExpense` / `voidExpense`; test-only `*ForTest` delegates to service.
- `ExpensesDao.updateExpense` / `voidExpense` not called from production `lib/`.
- Expense record mutation audit only via `ExpenseMutationInTransactionWriter` + `activityLogsDao.insertLog` inside txn.
- Repository `ActivityLoggerService` remains for **category** CRUD only.

**Finding:** NONE

---

## Idempotency

- Lookup → replay / conflict → work → seal-last (`insertCompletedRecord`).
- UNIQUE/PK 1555/2067 on `expense_mutation_idempotency` → `_IdempotencySealRace` retry (tests 6, 7, 14, 20).
- BUSY/LOCKED backoff in `_runWithRetry` (B21-style).
- Replay does not alter row, audit count, or summary totals (tests 2, 10, 8, 9).
- `operationType` enforced on replay/conflict (UPDATE vs VOID).

**Finding:** NONE

---

## Fingerprints

**UPDATE:** `operation`, `expenseId`, `categoryId`, `amount` (6 dp), date-only dates, normalized `notes`, `sessionId`, `updatedBy` — SHA-256 JSON.

**VOID:** `operation`, `expenseId`, `voidedBy` — SHA-256 JSON.

Excludes idempotency key and volatile UI fields. Service normalizes amount/dates/notes before write.

**Finding:** NONE

---

## Transaction Atomicity

UPDATE and applied VOID bundle row change + activity log + idempotency insert in one transaction. `alreadyVoided` path skips seal and void audit. Rollback verified for activity failure, pre-seal failure, and seal retry paths.

**Finding:** NONE

---

## Void Semantics

- `is_voided` flag; no delete; no reversal row; summary excludes voided (`getExpenseSummary`).
- Already voided + different key: no-op, no extra audit (test 12).
- Update after void: rejected (test 15).
- Void after update: allowed; test 22 voids updated row.
- Same-key void replay: no duplicate audit (test 10).

**Finding:** NONE

---

## Concurrency

**Test 21 (UPDATE held, VOID commits first):**

- `beforeMutationHook` + Completer barrier on `dbA`; `processVoid` on `dbB` after barrier; no sleeps.
- Asserts: voided, amount 50, 1 idempotency row, summary 0, 1 void audit, 0 update audits; UPDATE throws `StateError`.

**Test 22 (VOID held, UPDATE commits first):**

- Reverse barrier; asserts voided, amount 75, 2 idempotency rows, summary 0, 1 update + 1 void audit.

Uses real `ExpenseMutationSaveService` on dual raw SQLite connections (`busy_timeout` 15000). Tests prove cross-path ordering required by business rules; implementation guards (`getExpenseById` void check, `WHERE is_voided = false`) align with outcomes.

**Finding:** NONE

---

## Auth / Audit

- UI blocks `userId <= 0` before service calls (update/void).
- Service `ArgumentError` for `updatedBy` / `voidedBy <= 0`.
- Activity logs use `updatedBy` / `voidedBy`; void severity `ActivitySeverity.warning`.
- All mutation audit inside transaction.

**Finding:** NONE

---

## UI Lifecycle

**UPDATE:** sticky UUID, fingerprint change resets key, success/conflict → `_resetSaveAttempt()`, generic error retains key, `_saving` guard.

**VOID:** sticky `_voidIdempotencyKey`, `_voidInFlight`, success/conflict clear key, generic catch retains key. No SharedPreferences.

**Finding:** NONE

---

## Migration

- v48 → v49 additive: `expense_mutation_idempotency` + index `emi_expense_record_idx`.
- No backfill; no mutation of existing expense rows during migration.
- `schemaVersion` 49; onCreate + `from < 49` migration; Drift generated code includes table/DAO.
- Tests 18–19 cover migrated table and fresh schema.

**Finding:** NONE

---

## Tests

**Re-run this final audit:**

| Suite | Result |
|-------|--------|
| B22 | **22/22 PASS** |
| B18 | **20/20 PASS** (with B21 in one invocation: 42 total) |
| B21 | **22/22 PASS** |
| B4–B10 | **147/147 PASS** |
| B15, B16, B17, B19, B20 | **127/127 PASS** |

Tests 21–22 are meaningful dual-connection races with deterministic Completer barriers (not timing-based).

**Finding:** NONE

---

## Regression

- B18 CREATE semantics and idempotency table unchanged; tests 13–14 use service-backed test helpers only.
- B21 full suite pass after schema v49 coexistence.
- B4–B10 and sampled B11–B20 files: schema sentinel 49 only in modified regression tests.

**Finding:** NONE

---

## Analyzer / Hygiene

| Check | Result |
|-------|--------|
| `analyze_files` on `lib/` | **No errors** |
| `git diff --check` | Clean (CRLF note on `app_database.g.dart`) |
| Conflict markers in B22 services | None |
| B22 core Dart/test UTF-8 | No BOM / UTF-16 on spot-checked B22 files |

**Finding:** NONE for B22 production defects.

---

## Scope

B22 changes limited to:

- Expense UPDATE/VOID save protection
- Schema v49 mutation idempotency
- Expense UI/repository cutover
- B22 test suite + schema bumps in 14 regression tests

Not expanded into: other income mutation, POS debt sticky key, session close, stock movements, category CRUD changes, unrelated tooling (untracked `tool/*` excluded from commit intent).

**Finding:** NONE

---

## Optional Findings

| Item | Classification | Notes |
|------|----------------|-------|
| BUSY/LOCKED integration test | OPTIONAL | Code present; no deterministic test |
| Migration index assertion in test 18 | OPTIONAL | Table asserted; index not queried |
| UI auth widget tests | OPTIONAL | Service + UI guard code reviewed |
| UTF-8 BOM in `expense_creation_idempotency_b18_test.dart` | OPTIONAL | Hygiene only; no correctness impact |

No optional item exposes a correctness defect.

**Finding:** OPTIONAL (informational only; not required for commit)

---

## Git State

- **No commit, push, or stage** during this audit.
- HEAD and `origin/main` remain `53a86e6`.
- Intended commit set: modified `lib/` expense + DB v49, new B22 `lib/`/`test/` files, 14 regression schema lines; exclude unrelated untracked `docs/*` (except audit artifacts user chooses) and `tool/*`.

**Finding:** NONE

---

## Summary of Classifications

| Severity | Count |
|----------|-------|
| BLOCKER | 0 |
| SHOULD-FIX | 0 |
| OPTIONAL | 4 (documented above; non-blocking) |
| NONE | All audited areas |

---

## FINAL VERDICT

**B22 FINAL AUDIT: PASS**

**READY FOR COMMIT**