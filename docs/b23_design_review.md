# B23 DESIGN REVIEW

**Date:** 2026-10-12
**Mode:** DESIGN ONLY — no production/test/schema changes, no commit, no push
**Baseline:** `552636336b07489f0b7f7a5d1cc52cb3e90bef3b` @ schema **v49**
**Discovery candidate:** C23-A — Other Income UPDATE + VOID save protection

---

## 1. Baseline

| Item | Value |
|------|-------|
| Branch | `main` |
| HEAD / origin/main | `552636336b07489f0b7f7a5d1cc52cb3e90bef3b` |
| Schema | v49 |
| Tracked working tree | Clean |
| B22 | Closed (expense mutation protection) |
| B19 | Other income **CREATE** idempotency (unchanged scope) |

---

## 2. Current Production Paths

### UPDATE (verified at HEAD)

| Layer | Component |
|-------|-----------|
| UI | `OtherIncomeDialog._submit` when `widget.existing != null` |
| Provider | `otherIncomeRepositoryProvider` |
| Repository | `OtherIncomeRepository.updateIncome` |
| DAO | `OtherIncomeDao.updateIncome` — Drift `replace` |
| Audit | `ActivityLoggerService.logEntityUpdate` **after** repository transaction |

**Production callers:** `lib/features/other_income/screens/widgets/other_income_dialog.dart` only.

**Test callers:** `test/other_income_creation_idempotency_b19_test.dart` test 14 (`repository.updateIncome`).

**No** other `lib/` references to `updateIncome`.

### VOID (verified)

| Layer | Component |
|-------|-----------|
| UI | `OtherIncomeScreen._ActionButtons._confirmVoid` |
| Repository | `OtherIncomeRepository.voidIncome` |
| DAO | `OtherIncomeDao.voidIncome` — partial write (`is_voided`, `updated_at`) |
| Audit | `ActivityLoggerService.logWarning` **after** repository transaction |

**Production callers:** `other_income_screen.dart` only.

**Test callers:** B19 test 13 (`repository.voidIncome`).

### CREATE (B19 — out of scope for mutation)

`OtherIncomeDialog` → `OtherIncomeCreationService.processCreate` → in-txn insert + audit + `other_income_idempotency` seal.

### Alternate / legacy writers

- **No** production path calls `OtherIncomeDao.updateIncome` / `voidIncome` except via repository.
- **No** `saveSale`-style dead path for other income mutations.
- Category CRUD remains separate (not in B23 scope).

---

## 3. Current Other Income Semantics

### Schema (`other_income_records`)

| Column | Role |
|--------|------|
| `category_id`, `amount`, `income_date`, `received_at`, `notes`, `session_id` | Mutable on update |
| `created_by` | **Immutable** author (FK users); update companion preserves original `created_by` |
| `created_at` | Set on insert only |
| `updated_at` | Set on update and void |
| `is_voided` | Void flag; default false |

**No** `updated_by` / `voided_by` columns — actor identity lives in activity log + mutation fingerprint (same as expenses post-B22).

### UPDATE semantics (today)

- Full row **`replace`** via Drift with `isVoided: const Value(false)` forced in repository (caller cannot void via update).
- Pre-txn read inside repository transaction: reject missing row or `isVoided == true` → `StateError`.
- **Does not** use `WHERE is_voided = 0` on the UPDATE statement (unlike B22 writer); relies on pre-read only inside same txn.
- Amount must remain `> 0` (table CHECK).

### VOID semantics (today)

- Sets `is_voided = true`, `updated_at = now`; **no delete**, **no reversal row**, **no ledger negation row**.
- Already voided: repository returns **silently** (no throw, **no audit**).
- Irreversible in UI.
- Audit: `ActivityTypes.incomeVoided`, **`logWarning`** (correct severity intent).

### Ledger semantics (unchanged by design)

`FinancialLedgerRepository` SQL: one `OTHER_INCOME` inflow per **active** row (`is_voided = 0`, `amount > 0`); void **excludes** row entirely. Edit changes amount/dates/category/notes/session on same row → ledger reflects current snapshot. **B23 must preserve this model.**

### Race behavior (today, pre-protection)

- Update vs void: repository-level TOCTOU within separate transactions; audit non-atomic; no idempotency; duplicate submit can duplicate audits or apply redundant writes.

---

## 4. Architecture Options

### Option A — Extend `other_income_idempotency` (B19 table)

Add `operation_type` (`CREATE` | `UPDATE` | `VOID`); migrate existing rows to `CREATE`.

| Pros | Cons |
|------|------|
| Single table | Touches B19 table, DAO, replay branching |
| | Higher B19 regression risk |
| | CREATE fingerprints lack `operation` field today |

**Verdict:** Reject — violates B-phase isolation goal (same rationale as B22 vs B18).

### Option B — New `other_income_mutation_idempotency` (UPDATE + VOID only) **(recommended)**

Mirror B22 / `expense_mutation_idempotency`: PK `idempotency_key`, `operation_type`, `fingerprint_hash`, `other_income_record_id`, index on record id.

| Pros | Cons |
|------|------|
| B19 untouched | New migration v50 |
| Clear mutation lifecycle | Second idempotency table for other income |
| Proven B22 pattern | |

### Option C — Separate UPDATE and VOID tables

Duplicate structure; no correctness gain.

**Verdict:** Reject.

---

## 5. Recommended Architecture

**Option B** with:

- `OtherIncomeMutationSaveService` — `processUpdate`, `processVoid`
- `OtherIncomeMutationInTransactionWriter` — row updates + in-txn activity logs
- `OtherIncomeMutationFingerprint` — SHA-256 canonical JSON (reuse B19 normalization helpers where applicable)
- `other_income_mutation_save_service_provider.dart`
- Repository: remove production `updateIncome` / `voidIncome`; add `@visibleForTesting` `updateIncomeForTest` / `voidIncomeForTest` delegating to service (B22 expense pattern)

---

## 6. Database Design

**Schema v50** (additive only).

### Table: `other_income_mutation_idempotency`

| Column | Type | Notes |
|--------|------|-------|
| `idempotency_key` | TEXT PK | Client intent key |
| `operation_type` | TEXT NOT NULL | `UPDATE` \| `VOID` |
| `fingerprint_hash` | TEXT NOT NULL | SHA-256 hex |
| `other_income_record_id` | INTEGER NOT NULL | Target row |
| `created_at` | DATETIME | default now |

### Index

- `oimi_other_income_record_idx` on `(other_income_record_id)` — parity with `oii_*` / `emi_*`

No FK required (consistent with B19/B22 idempotency tables). **No backfill.**

---

## 7. Fingerprint Design

Use `OtherIncomeCreationFingerprint` normalization family: `roundAmount` (6 dp), `normalizeNotes`, date-only strings via `dateString` / `normalizeDate`.

### UPDATE payload

| Field | Include |
|-------|---------|
| `operation` | `'UPDATE'` |
| `otherIncomeRecordId` | yes |
| `categoryId` | yes |
| `amount` | yes (rounded) |
| `incomeDate` | yes (date string) |
| `receivedAt` | yes (date string) |
| `notes` | yes (trimmed) |
| `sessionId` | yes (nullable in JSON) |
| `updatedBy` | yes (`> 0`) |

**Exclude:** idempotency key, `createdAt`/`updatedAt`, `createdBy`, UI-only fields.

### VOID payload

| Field | Include |
|-------|---------|
| `operation` | `'VOID'` |
| `otherIncomeRecordId` | yes |
| `voidedBy` | yes (`> 0`) |

Hash: `sha256(utf8.encode(jsonEncode(payload)))`.

Service validates category active on update (mirror B19/B22 expense category checks).

---

## 8. Transaction Boundary

Per attempt, single `db.transaction()`:

1. Lookup mutation idempotency by key
2. If found: same `operation_type` + same fingerprint → **replay return** (no mutation, no audit)
3. If found: fingerprint or operation mismatch → **conflict exception**, zero mutation
4. Optional test hooks: `beforeMutationHook`, `testActivityLogHook`, `preSealHook`
5. Re-read row; validate not voided (update) / existence (void)
6. Writer: conditional update (`is_voided = 0`) or conditional void
7. In-txn `activityLogsDao.insertLog` (update: info; void: **warning**)
8. Insert idempotency seal **last**
9. Commit

**Rollback:** any failure rolls back row + audit + seal. Replay path never reaches steps 5–8.

---

## 9. Replay / Conflict Semantics

| Condition | UPDATE | VOID |
|-----------|--------|------|
| Same key + same fingerprint | Replay; no row/audit change | Replay; no extra audit |
| Same key + different fingerprint | Conflict | Conflict |
| Different keys | Sequential updates allowed (last write wins) | Already voided + new key: **success no-op**, no audit, **no seal** (B22 void pattern) |
| Seal UNIQUE race | Retry loop / replay winner | Same |

Do **not** reuse B19 create keys for mutations.

---

## 10. UPDATE ↔ VOID Concurrency Model

**DEFERRED transactions sufficient** with:

- Update: in-txn read + writer `UPDATE ... WHERE id = ? AND is_voided = 0`; zero rows → `StateError`
- Void: writer `UPDATE ... WHERE id = ? AND is_voided = 0`; zero rows → inspect row → `alreadyVoided` path

**BEGIN IMMEDIATE:** not required unless implementation tests prove otherwise.

### Deterministic dual-connection tests (mandatory in implementation)

Use `@visibleForTesting beforeMutationHook` + Completer pair (B22 tests 21–22 / B21 pattern). **No sleeps.**

**F1 — UPDATE held, VOID commits first (dbA update paused, dbB void):**

- Expected: row **voided**, amount **unchanged** (original), **one** void audit, **zero** update audits, **one** mutation idempotency seal (void only), update future **`StateError`**, summary total excludes voided row.

**F2 — VOID held, UPDATE commits first (dbA void paused, dbB update):**

- Expected: row **voided**, amount **updated**, **one** update + **one** void audit, **two** seals, summary total 0 for active income.

These outcomes match closed B22 semantics and preserve ledger rules (void excludes row; amount at void time reflects last committed update).

---

## 11. Authorization

| Action | Requirement |
|--------|-------------|
| Update | `updatedBy > 0` in service; fingerprint includes actor |
| Void | `voidedBy > 0` in service |
| Activity log | `userId: Value(actor)` from service parameter |

**SHOULD-FIX (implementation):** Edit path in `OtherIncomeDialog` currently lacks explicit `userId > 0` gate before update (create path uses `createdBy` from auth). Add UI + service enforcement (B22 parity).

Permissions: existing `PermissionKeys.financialIncomeEdit` / delete (void) remain UI gates.

---

## 12. UI Key Lifecycle

Mirror B22 / B19 create conventions:

### UPDATE (`OtherIncomeDialog` edit mode)

- `_idempotencyKey`, `_pendingFingerprint`, `_saving` guard
- Sticky UUID until success / replay / conflict → reset
- Fingerprint change → reset key
- Transient error → **retain** key
- Route edit through `OtherIncomeMutationSaveService.processUpdate`

### VOID (`OtherIncomeScreen`)

- Convert void actions to **StatefulWidget** (B22 `_ActionButtons` pattern): `_voidIdempotencyKey`, `_voidInFlight`
- Sticky key; success/conflict clear; transient retains
- No SharedPreferences

---

## 13. SQLite Retry Strategy

Align with **B22 / B21 / B19** (already on create):

- Extended codes **1555 / 2067** with statement/message table guard for `other_income_mutation_idempotency`
- `_IdempotencySealRace` → retry transaction
- BUSY (**5**) / LOCKED (**6**): up to **8** attempts, backoff `25 * (attempt + 1)` ms
- Non-Exception throwables wrapped after log

No BEGIN IMMEDIATE.

---

## 14. Migration Plan

- **v49 → v50** additive migration in `app_database.dart`
- Register table + DAO; onCreate + `from < 50` upgrade
- Bump **schema sentinel to 50** in regression tests that assert `schemaVersion` (same 14-file pattern as B22)
- B19 migration tests: continue to assert idempotency table exists post-open; expect schema **50** after bump

---

## 15. Production Bypass Prevention

Target production graph:

| Operation | Path |
|-----------|------|
| UPDATE | `OtherIncomeDialog` → `otherIncomeMutationSaveServiceProvider.processUpdate` |
| VOID | `OtherIncomeScreen` → `processVoid` |
| CREATE | Unchanged — `OtherIncomeCreationService` |

Post-cutover grep requirement: **zero** production `OtherIncomeRepository.updateIncome` / `voidIncome` from UI.

`OtherIncomeDao.updateIncome` / `voidIncome` used only from in-transaction writer (or deprecated for direct use).

---

## 16. Test Matrix

File: `test/other_income_mutation_save_protection_b23_test.dart` (name TBD).

### A. UPDATE

1. Success
2. Same-key replay
3. Same-key fingerprint conflict
4. Different-key sequential updates
5. Rollback on activity failure
6. Seal failure then retry
7. Auth `updatedBy <= 0`
8. Update after void rejected

### B. VOID

9. Success
10. Same-key replay
11. Same-key conflict
12. Already voided, different key (no extra audit/seal)
13. Rollback on activity failure
14. Seal failure retry
15. Auth `voidedBy <= 0`

### C. CROSS-PATH (mandatory)

16. Dual-connection **UPDATE vs VOID** (F1)
17. Dual-connection **VOID vs UPDATE** (F2)

### D. CONCURRENCY

18. Dual-connection same-key update (mirror B22 test 7)
19. UNIQUE/PK on idempotency key (direct + service race)
20. BUSY/LOCKED — **optional** deterministic test if practical

### E. MIGRATION

21. Simulated v49 → v50 table + index
22. Fresh DB schema 50

### F. LEDGER

23. Update changes summary / ledger count for record id (B19 test 14 intent)
24. Void excludes ledger row (B19 test 13 intent)
25. Failed txn leaves ledger unchanged (rollback case)

B19 tests 13–14: switch to `*ForTest` service-backed helpers only (no semantic change).

---

## 17. Regression Plan

Minimum re-run after implementation:

| Suite | Reason |
|-------|--------|
| B23 (new) | Primary |
| B19 | CREATE isolation + ledger tests 13–15 |
| B22 | Parallel mutation pattern unchanged |
| B18 | Expense sanity |
| B4–B10 | Schema sentinel 50 |
| Financial ledger tests touching OTHER_INCOME | If any dedicated file exists; else B19 ledger assertions |

Do not bulk-bump unrelated tests beyond schema version lines.

---

## 18. Explicit Invariants

| ID | Invariant |
|----|-----------|
| I1 | One client idempotency key → at most one successful mutation seal for that key |
| I2 | Same key + same fingerprint → zero additional row/audit/financial effect |
| I3 | Same key + different fingerprint → typed conflict, zero mutation |
| I4 | UPDATE row + audit + seal atomic in one transaction |
| I5 | VOID row + warning audit + seal atomic (or no-op without seal when already voided) |
| I6 | Seal written only after successful mutation + audit (except replay / alreadyVoided) |
| I7 | Failed attempt leaves no partial mutation, audit, or seal |
| I8 | Voided record cannot be updated (StateError) |
| I9 | Cross-path UPDATE↔VOID barriers yield deterministic valid final state (tests 16–17) |
| I10 | Unauthorized actor (`<= 0`) cannot mutate |
| I11 | B19 CREATE table, service, and semantics unchanged |
| I12 | Ledger continues to derive OTHER_INCOME from active `other_income_records` only |

---

## 19. Risks / Open Questions

| Risk | Mitigation |
|------|------------|
| B19 regression | Do not alter `other_income_idempotency` or `OtherIncomeCreationService` |
| DAO void lacks `is_voided = 0` filter | Writer uses conditional SQL (B22 hardening) |
| Edit sessionId rules in dialog | Preserve existing Case A/B/C session resolution when wiring service |
| UTF-16 test file encoding | Use UTF-8 no BOM on new files (B22 lesson) |

**Open question:** None blocking — void no-op on already-voided matches B22 and current repository behavior.

---

## 20. SHOULD-FIX (for implementation / review pass)

1. **Auth gate** on edit + void UI and service (`userId > 0`).
2. **Void UI** stateful sticky key + in-flight guard.
3. **Edit UI** sticky key + fingerprint reset (create path already has partial pattern; edit must match B22).
4. **Conditional void/update SQL** in writer (not replace-only void).
5. **B21-style** SqliteException handling on mutation service (not string-only).
6. **Repository** methods clearly test-only after cutover.
7. **Cross-path tests 16–17** required before final audit (B22 lesson).

---

## Final Design Verdict

**DESIGN APPROVED WITH SHOULD-FIX**

Architecture (Option B), semantics, transaction model, fingerprints, concurrency expectations, and test matrix are sound and aligned with B22. No design blockers. Address SHOULD-FIX items during implementation and review pass.
