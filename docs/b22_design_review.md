# B22 DESIGN REVIEW

**Date:** 2026-10-08  
**Mode:** DESIGN ONLY — no production/test/schema changes, no commit, no push  
**Baseline:** `53a86e6eea76e9adf15bbc46699890f937aeec12` @ schema **v48**

---

## Baseline

| Item | Value |
|------|-------|
| Branch | `main` |
| HEAD / origin/main | `53a86e6eea76e9adf15bbc46699890f937aeec12` |
| Schema | v48 |
| Tracked tree | Clean |

---

## Discovery Summary

B22 targets **expense record UPDATE and VOID** while B18 protects CREATE only. POS debt settlement sticky-key gap (R3) remains out of scope.

---

## Current Production Paths

### UPDATE

| Layer | Component |
|-------|-----------|
| UI | `ExpenseDialog._submit` when `widget.existing != null` |
| Provider | None (direct repository) |
| Repository | `ExpenseRepository.updateExpense` |
| Service | **None** |
| DAO | `ExpensesDao.updateExpense` (`replace`) inside repo txn |
| Audit | `ActivityLoggerService.logEntityUpdate` **after** txn |

**Production callers:** `expense_dialog.dart` only.

**Test callers:** `expense_creation_idempotency_b18_test.dart` test 14 (ledger regression).

### VOID

| Layer | Component |
|-------|-----------|
| UI | `ExpenseScreen` row → `_confirmVoid` |
| Repository | `ExpenseRepository.voidExpense` |
| DAO | `ExpensesDao.voidExpense` (sets `is_voided=true`, `updated_at`) inside repo txn |
| Audit | `ActivityLoggerService.logInfo` **after** txn |

**Production callers:** `expense_screen.dart` only.

**Test callers:** B18 test 13.

### CREATE (B18 — unchanged)

`ExpenseDialog` → `ExpenseCreationService.processCreate` → txn → `createExpenseInTransaction` → in-txn activity → `expense_idempotency` seal.

**Single production writer today for update/void:** `ExpenseRepository` (two methods). No alternate production bypass.

---

## Current Data / Transaction Semantics

### Schema (`expense_records`)

- Void = **`is_voided` boolean** (default false). No row delete, no amount reversal row.
- Update = full row **`replace`** via Drift (all mutable fields written).
- `created_by` is original author; **`updated_by` / `voided_by` columns do not exist**.
- `updated_at` set on update and void.
- `session_id` optional FK to `pos_sessions`.

### Financial / session views

- `ExpensesDao.getExpenseSummary` and paged lists exclude `is_voided = 0` for active totals.
- `FinancialLedgerRepository` derives **one EXPENSE ledger row per active** expense (`is_voided = 0`). Void **excludes** the row (no reversal entry).
- Edit changes amount/category/dates/notes/session on the same row → ledger view reflects new values while active.

### Void / update rules (repository)

- Update: fetch → reject if missing or `isVoided` → `replace` with **`isVoided: false` forced**.
- Void: fetch → if already voided **return silently** (no throw, no audit) → else void in txn → audit outside txn.
- **Not reversible** in code.

### Transaction ownership (today)

- Repository owns a **single DEFERRED** `db.transaction()` for row mutation only.
- Activity logging is **non-atomic** with mutation.

---

## Business Invariants (target)

See Discovery §4 — all listed UPDATE/VOID/CROSS-PATH invariants must hold after B22.

---

## Design Options

### Option 1 — Extend `expense_idempotency` (CREATE table)

Add `operation_type` (`CREATE`|`UPDATE`|`VOID`), migrate existing rows to `CREATE`.

| Pros | Cons |
|------|------|
| One idempotency table | Touches B18 table and replay semantics |
| | B18 tests and DAO must branch on operation |
| | Higher regression risk to closed B18 |

**Verdict:** Reject — violates cross-phase safety goal.

### Option 2 — New `expense_mutation_idempotency` (UPDATE + VOID only) **(recommended)**

B18 `expense_idempotency` unchanged. New table keyed by `idempotency_key` with `operation_type`, `fingerprint_hash`, `expense_record_id`.

| Pros | Cons |
|------|------|
| B18 isolation | New migration v49 |
| Clear mutation lifecycle | Two idempotency tables for expenses |
| Matches B21 pattern (separate concern) | |

### Option 3 — Separate update and void tables

Structurally duplicate Option 2.

**Verdict:** Reject — no correctness gain.

---

## Recommended Design

**Option 2** with a single **`ExpenseMutationSaveService`** exposing `processUpdate` and `processVoid`, plus **`ExpenseMutationInTransactionWriter`** for row mutations and in-txn activity logs (mirror B18/B21).

### Production path (target)

**Update:** `ExpenseDialog` → `ExpenseMutationSaveService.processUpdate` → one txn → idempotency lookup → replay/conflict → writer update → activity log → seal last → commit.

**Void:** `ExpenseScreen` → `ExpenseMutationSaveService.processVoid` → same pattern.

**Repository:** `updateExpense` / `voidExpense` become **test-only delegators** to the service (or removed from production UI entirely), documented like `StockDao.createAdjustment`.

---

## Idempotency Model

| Condition | UPDATE | VOID |
|-----------|--------|------|
| Same key + same fingerprint | Replay; no row rewrite; no extra audit | Replay; no extra audit |
| Same key + different fingerprint | Conflict; zero mutation | Conflict; zero mutation |
| Different keys | Legitimate sequential updates | Second void on already-voided row: **no mutation, no audit, success** (state idempotent) unless design chooses hard error — recommend **success no-op** for void-only |
| Seal race (UNIQUE on key) | Retry txn / replay winner | Same |

**Separate idempotency keys** for update vs void UI intents (different dialogs/actions).

**Do not reuse** B18 create keys for mutations.

---

## Fingerprint Model

Use SHA-256 over canonical JSON (same family as B18).

### UPDATE payload

| Field | Include | Notes |
|-------|---------|-------|
| `operation` | `'UPDATE'` | Prevents cross-op reuse |
| `expenseId` | yes | Target row |
| `categoryId` | yes | |
| `amount` | yes | `roundAmount` (6 dp) |
| `expenseDate` | yes | date-only string |
| `paidAt` | yes | date-only string |
| `notes` | yes | trimmed |
| `sessionId` | yes | nullable in JSON |
| `updatedBy` | yes | authenticated actor `> 0` |

**Exclude:** idempotency key, `createdAt`/`updatedAt`, UI state, derived totals.

**Do not include** original `createdBy` in fingerprint (immutable author stays on row; actor is `updatedBy`).

### VOID payload

| Field | Include |
|-------|---------|
| `operation` | `'VOID'` |
| `expenseId` | yes |
| `voidedBy` | yes |

Optional note field **excluded** unless product adds void reason later.

---

## Transaction Model

- **Owner:** `ExpenseMutationSaveService` — one `db.transaction()` per attempt.
- **Order:** lookup → (replay return) → pre-mutation hooks (tests) → row mutation → in-txn activity log → `preSealHook` (tests) → insert idempotency seal → commit.
- **No nested transactions** on production path.
- **Rollback:** any failure after mutation start rolls back row + audit + seal.
- **BUSY/LOCKED:** retry with backoff (align with B21 extended codes + table-targeted UNIQUE detection — **SHOULD-FIX** vs B18 string-only).
- **Activity log failure:** must rollback mutation (move logging inside txn via `activityLogsDao.insertLog` like B18 create).

---

## Concurrency Model

| Scenario | Mitigation |
|----------|------------|
| A. Same key, same fp, dual connection | Seal-last + UNIQUE retry; one winner |
| B. Same key, diff fp | Conflict before mutation |
| C. Different keys, same expense | Last `replace` wins (acceptable); each key sealed separately |
| D/E. Update vs void | Txn serialization + read row state: update rejects voided; void uses `WHERE is_voided=0` or state check; void after update OK |
| F. Retry after failure | Sticky UI key reuses same operation |
| G. Activity failure | Full rollback |
| H. Seal race | `_IdempotencySealRace` retry loop |

**DEFERRED transactions sufficient:** row-scoped `replace` and conditional void update — no aggregate read-modify-write like opening stock. **BEGIN IMMEDIATE not required** if void uses conditional SQL and update re-reads void flag inside txn.

**Optional hardening:** `voidExpense` → `UPDATE ... WHERE id=? AND is_voided=0`; if 0 rows, inspect row for already-voided path.

---

## Update Semantics

- **Replace** mutable fields on existing row; **`created_by` unchanged**; set `updated_at`.
- **Force `is_voided = false`** in writer (preserve current guard).
- **No compensating ledger rows** — ledger is derived from current row snapshot.
- **Session change** affects session-scoped reporting only (no POS cash drawer math tied to expense row in ledger SQL beyond inclusion/exclusion).

---

## Void Semantics

- Preserve existing **`is_voided` flag** semantics (no accounting redesign).
- No delete; no amount negation row.
- Ledger excludes voided rows automatically.
- **Irreversible** in UI.
- **Replay** must not insert a second void audit entry.

---

## UI Key Lifecycle

### UPDATE (ExpenseDialog edit mode)

Mirror B18 create pattern:

- Sticky UUID per save attempt; `_pendingFingerprint`; `_saving` blocks double submit.
- Fingerprint change → reset key.
- Success / replay / conflict → clear key.
- Transient error → retain key.
- Auth: **`updatedBy` must be `userId > 0`** before call (SHOULD-FIX — edit path currently skips this check).

### VOID (ExpenseScreen)

- Add state: `_voidIdempotencyKey`, `_voidInFlight` (or per-row key map if multiple voids — prefer key generated at confirm start for that action).
- Sticky key until success/conflict; retain on transient failure.
- No SharedPreferences.

---

## Authorization

| Action | Requirement |
|--------|-------------|
| Update | `updatedBy > 0` enforced in service |
| Void | `voidedBy > 0` enforced in service |
| Fingerprint | Includes actor id |
| Activity log | `userId: Value(actor)` from authoritative parameter, not nullable anonymous |

Permissions: existing `PermissionKeys.financialExpensesEdit` / delete (void) remain UI gates.

---

## Migration Plan

- **Schema v49** (additive).
- **Table:** `expense_mutation_idempotency`
  - `idempotency_key` TEXT **PK**
  - `operation_type` TEXT NOT NULL (`UPDATE` | `VOID`)
  - `fingerprint_hash` TEXT NOT NULL
  - `expense_record_id` INTEGER NOT NULL
  - `created_at` DATETIME default current_timestamp
- **Index:** `emi_expense_record_idx` on `(expense_record_id)`
- **No backfill** required.
- **No FK** required (consistent with B18 idempotency table).
- Register table/DAO in `app_database.dart`; onCreate + migration from v48.

---

## Production Bypass Removal

| Caller | After B22 |
|--------|-----------|
| `ExpenseDialog` edit | Service only |
| `ExpenseScreen` void | Service only |
| `ExpenseRepository.updateExpense/voidExpense` | Test-only delegate or internal to service tests |
| `ExpensesDao.updateExpense/voidExpense` | In-transaction writer only |

Audit: grep must show zero production UI → repository mutation paths.

---

## Test Matrix

File: `test/expense_mutation_save_protection_b22_test.dart` (name TBD).

**UPDATE:** tests 1–12 from brief.  
**VOID:** tests 13–20.  
**CROSS:** tests 21–26 (update vs void dual connection with Completers).  
**Migration:** v48→v49 table exists.  
**Regression:** B18 suite unchanged semantics; schema sentinel → 49 in shared regression tests.

Assert **row counts, is_voided, amount, activity_logs count, idempotency rows, ledger derivation counts** — not only return objects.

---

## Regression Plan

- Full B18 file unchanged behavior for create/idempotency.
- B4–B21 schema sentinel bumps only if v49.
- Re-run B18 + B22 + representative financial tests.

---

## Risks

| Risk | Mitigation |
|------|------------|
| B18 regression | Do not alter `expense_idempotency` |
| Void no-op vs error on already voided | Document UX; prefer no-op without audit |
| Concurrent updates last-write-wins | Accepted; idempotency per intent |
| Edit auth gap | SHOULD-FIX in implementation |

---

## Alternatives Considered

- Option 1 combined table — rejected.
- POS debt sticky key — follow-up R3.
- Other income mirror — B23.
- Row version column — out of scope.

---

## Scope / Out of Scope

**In:** Expense update + void protection only.

**Out:** Other income, POS debt UI, session close audit, categories, stock_movements, dead `PosRepository.saveSale`.

---

## SHOULD-FIX (before / during implementation)

1. **Edit/void auth gate in UI + service** (`userId > 0`) on update and void paths.
2. **Void activity severity** — use `ActivitySeverity.warning` in in-txn void log (align other income / prior audit W-6).
3. **SqliteException handling** — align mutation service with B21 (extended codes + table name), not B18 string-only.
4. **Void UI submitting guard** — prevent duplicate void dialogs in flight.
5. **Repository methods** — clearly mark test-only after cutover.

---

## Final Verdict

**B22 DESIGN REVIEW: PASS WITH SHOULD-FIX**

Design is architecturally sound, preserves B18, and closes the expense mutation gap with Option 2 (new mutation idempotency table + canonical mutation service + in-txn audit + seal-last). Address SHOULD-FIX items during implementation.