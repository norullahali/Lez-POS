# Customer Returns Phase C — Step 2.8A Review Pass

**Review type:** Independent financial safety review (read-only)  
**Review date:** 2026-09-23  
**Baseline HEAD:** `9206d4b` — `feat(customer-returns): show remaining refundable amount`  
**Schema:** 32 (unchanged)

---

## 1. Git / Scope

### Inspected commands
- `git rev-parse HEAD` → `9206d4be53466834c7905ef3e94f579522df4a36`
- `git status --short`
- `git diff --name-only`
- `git diff --stat`

### Modified tracked files (expected production scope)
| File | Stat |
|------|------|
| `lib/core/database/daos/customer_accounts_dao.dart` | +72 lines |
| `lib/core/services/customer_refund_settlement_service.dart` | +43 / -20 lines |

**Total tracked diff:** 2 files, 95 insertions, 20 deletions.

### Untracked files in expected Step 2.8A scope
- `test/customer_refund_aggregate_concurrency_phase_c_step_2_8a_test.dart`
- `docs/customer_returns_phase_c_step_2_8a_aggregate_concurrency.md`

### Untracked unrelated files (not part of Step 2.8A implementation)
- `docs/customer_returns_current_state_assessment.md`
- `docs/customer_returns_phase_c_next_step_discovery.md`
- `docs/customer_returns_phase_c_step_2_5_review_pass.md`
- `docs/customer_returns_phase_c_step_2_6_discovery.md`
- `docs/customer_returns_phase_c_step_2_6_review_pass.md`
- `docs/customer_returns_phase_c_step_2_7_discovery.md`
- `docs/customer_returns_phase_c_step_2_7b_discovery.md`
- `docs/customer_returns_phase_c_step_2_7c_discovery.md`
- `tool/_write_2_7c_test.dart`

No unrelated **tracked** production files were modified. Unrelated untracked discovery/review artifacts remain in the working tree and were not staged or cleaned.

---

## 2. Architecture Protection

### Sole REFUND mutation boundary
`CustomerRefundSettlementService.settleCredit()` remains the sole **production** financial REFUND mutation boundary.

Production path now calls `recordRefundInTransactionIfWithinAggregateCredit()` instead of unconditional `recordRefundInTransaction()`. The unguarded DAO method remains for tests and historical seeding only; it is not invoked from `settleCredit()` in production code.

`refundInTransactionOverride` remains test-only (`@visibleForTesting`).

### Protected architecture — verified unchanged
| Area | Status |
|------|--------|
| `CustomerReturnCredit` | No diff |
| `ReturnsDao` (incl. `incrementSettledAmountIfWithinCap`) | No diff |
| `CustomerReturnReadRepository` | No diff |
| `FinancialLedgerRepository` | No diff |
| Cash Ledger derivation architecture | No diff |
| `customer_returns.settled_amount` schema/logic | No diff |
| Step 2.7B per-return cap (`incrementSettledAmountIfWithinCap`) | Unchanged, still runs after guarded REFUND |
| Step 2.7C remaining-refundable UI | No diff |
| `PartialReturnService` | No diff |
| Invoice Details | No diff |
| Refund UI/provider architecture | No diff |
| Supplier refund architecture | No diff |

The Step 2.8A guard is **additive**. Step 2.7B per-return protection remains in place and still executes after the guarded REFUND insert for linked refunds.

---

## 3. Aggregate Credit Invariant — SQL Assessment

### Method reviewed
`CustomerAccountsDao.recordRefundInTransactionIfWithinAggregateCredit()`

### Exact SQL
```sql
INSERT INTO customer_transactions (customer_id, type, amount, reference_id, note)
SELECT ?, 'REFUND', ?, ?, ?
WHERE COALESCE(
  (SELECT SUM(amount) FROM customer_transactions WHERE customer_id = ?),
  0
) + ? <= ?
```

### Semantic verification

| Check | Result |
|-------|--------|
| SUM source | `SUM(amount)` on `customer_transactions` — matches `calculateBalanceFromTransactions()` |
| `customer_id` filter | Subquery filters `WHERE customer_id = ?` — correct per-customer isolation |
| Refund amount sign | REFUND stored as positive `amount`; guard adds `+ amount` to sum — matches existing sign convention |
| Pre-SQL validation | `if (amount <= 0) return false` — rejects non-positive before SQL |
| Tolerance | Default `0.0001`, passed from service — consistent with Step 2.7B tolerance |
| Atomicity | Single `INSERT ... SELECT ... WHERE` is one SQLite statement; WHERE evaluated against current DB state at execution time |
| Success detection | `SELECT changes()` after statement; `!= 1` → guard failure — correct (avoids stale `last_insert_rowid()`) |
| Guard failure | `changes() != 1` → returns `false` → service throws → Drift transaction rolls back → **no REFUND row committed** |

### Invariant equivalence
Existing credit math: `balance = SUM(amount)`. Available credit = `-balance` when `balance < 0`.

After REFUND of `a`: new sum = `old_sum + a`. Credit remains valid when new sum ≤ 0 (within tolerance).

Guard: `old_sum + a <= tolerance` where `tolerance = 0.0001`.

This is equivalent to: refund cannot drive aggregate balance above zero (cannot over-refund available credit).

**Assessment:** SQL and semantics are correct for the stated financial invariant.

---

## 4. Concurrency Analysis

### SQLite / Drift behavior
- Production DB uses `PRAGMA journal_mode = WAL` (AppDatabase migration/onCreate).
- Default SQLite writer serialization: only one write transaction commits at a time per database file.
- The conditional INSERT reads `SUM(amount)` at statement execution time inside the caller's Drift transaction.

### Scenario: credit = 100, two concurrent refunds of 60
1. Transaction A begins, passes pre-checks, executes guarded INSERT → succeeds, sum moves from -100 to -40.
2. Transaction B (concurrent connection) either:
   - **Waits** for A's lock, then executes INSERT with updated sum (-40 + 60 = 20 > tolerance) → 0 rows inserted → guard failure → rollback, **or**
   - Encounters **SQLITE_BUSY** if lock cannot be acquired (see Section 5).

**Both cannot commit REFUND rows totaling 120 against 100 credit.** Verified by Test E committed-state assertion (exactly 1 REFUND of 60, balance -40).

### Additional scenarios (test-backed)
| Scenario | Expected | Verified by |
|----------|----------|---------------|
| 60 + 40 sequential within 100 | Both succeed | Test D |
| 60 + 50 after 60 on linked return | Second fails | Test G |
| Different `returnId`s share aggregate pool | Second fails on aggregate | Test F |
| Linked + unlinked share pool | Unlinked fails after linked 60 | Test G |
| 60 + 60 concurrent on 100 credit | Not both succeed | Test E |

### Connection usage (Test E)
- Two raw `sqlite3` connections opened on the same temp `.db` file.
- Two separate `AppDatabase.test(NativeDatabase.opened(...))` instances.
- `PRAGMA busy_timeout = 5000` set on **test connections only** (not production).

---

## 5. SQLITE_BUSY Assessment

### Observed behavior (Test E execution)
During concurrent Test E, one connection logged:
```
SqliteException(5): database is locked
```
while executing the guarded INSERT. The generic `catch` in `settleCredit()` converted this to:
```
CustomerRefundSettlementFailure.unexpectedFailure
```
The Drift transaction rolled back. Final committed state: **exactly 1 REFUND row**, balance -40.

### Classification: **A — Acceptable for this step, with documented UX limitation**

| Criterion | Finding |
|-----------|---------|
| Rollback on BUSY | Yes — exception aborts Drift transaction; no partial REFUND |
| Double-commit prevention | Yes — Test E proves only one REFUND committed |
| Error taxonomy | Suboptimal — loser may get `unexpectedFailure` instead of `amountExceedsCredit` |
| Production `busy_timeout` | **Not set** in AppDatabase (default 0 = fail-fast on lock contention) |
| Test masking | **No** — Test E asserts committed REFUND count and balance, not merely exception types. A false pass would require both refunds committing, which would fail assertions. |

**Conclusion:** SQLITE_BUSY does **not** create an aggregate over-refund path. It is an acceptable documented contention failure mode for Step 2.8A financial safety. It is **not** classified as REQUIRES HARDENING for the core invariant, but is noted as NON-BLOCKING UX/resilience improvement for a future step (production `busy_timeout`, bounded retry, or mapping lock failure to `amountExceedsCredit`).

---

## 6. Transaction Order

Verified order inside `settleCredit()` (`customer_refund_settlement_service.dart`):

1. Customer validation
2. Amount validation
3. Return validation + per-return cap pre-check (when `returnId != null`)
4. Aggregate credit pre-check (`calculateBalanceFromTransactions`)
5. **Authoritative guarded REFUND insert** (or test override)
6. Per-return `incrementSettledAmountIfWithinCap` (when linked)
7. Optional `postRefundHook` (tests)
8. Audit log insert

All financial writes (REFUND insert, `customer_accounts` balance update, `settled_amount` increment) occur inside the single `_db.transaction()` block.

---

## 7. Rollback Analysis

| Failure point | REFUND committed? | Verified by |
|---------------|-------------------|-------------|
| Aggregate guard (`changes() != 1`) | No | Tests C, H, K; service throws before increment |
| Per-return increment failure | No (rolled back) | Test J (override simulates race); Step 2.7B Test J |
| Post-refund hook failure | No (rolled back) | Step 2.7B Test K pattern |
| Pre-check failures | No | Tests C, I, L |
| Audit log failure | Would roll back entire txn | Standard Drift transaction semantics (no new bypass introduced) |

Test K explicitly proves second guarded insert fails in same transaction and outer rollback leaves 0 REFUND rows.

---

## 8. Linked Refunds (Step 2.7B)

For `returnId != null`:
- Aggregate guard applies (Step 2.8A)
- Per-return cap pre-check still applies before REFUND
- `incrementSettledAmountIfWithinCap` still runs after REFUND with atomic conditional UPDATE
- Either guard failure rolls back entire transaction including REFUND

Step 2.7B logic in `ReturnsDao` was not modified. Step 2.8A did not weaken per-return enforcement.

---

## 9. Unlinked Refunds

For `returnId == null`:
- Aggregate guard applies (Tests A–D, M, O)
- No `settled_amount` update (guard clause `if (returnId != null)` unchanged)
- Profile-style unlinked refund path functional (Test M)
- Invoice Details architecture untouched; unlinked settlement path unchanged at service layer

---

## 10. General Customer (ID 1)

Test L confirms: `settleCredit(customerId: 1, amount: 10)` throws `noCustomerCredit`; no REFUND rows created. No new eligibility introduced.

---

## 11. Test Integrity — All 15 Tests

All tests use real `AppDatabase.test()` and real Drift transactions. No mock DAO bypasses the guard except Test J (intentional override for rollback simulation, matching Step 2.7B pattern).

| Test | Proves |
|------|--------|
| A | Single refund within credit succeeds; committed REFUND + balance |
| B | Exact-full refund succeeds; balance → 0 |
| C | Over-credit fails pre-check; 0 REFUND rows |
| D | Sequential 40+40 within 100 both commit |
| E | **Concurrent 60+60 on 100: exactly one succeeds; 1 REFUND row; balance -40** |
| F | Cross-returnId aggregate pool enforced |
| G | Linked then unlinked share aggregate pool |
| H | Failed guard leaves 0 REFUND rows |
| I | Step 2.7B per-return cap still blocks 101 on 100-cap return |
| J | Per-return failure after REFUND rolls back REFUND (override test) |
| K | Second guarded insert in same txn fails; rollback leaves 0 REFUND |
| L | Customer ID 1 unchanged |
| M | Unlinked refund works; `referenceId` null |
| N | Linked refund works; `referenceId` set; `settled_amount` updated |
| O | Unlinked path still works; Arabic message helper callable |

### Test E — exact proof
Test E proves the **financial invariant at committed state**:
- Seeds 100 credit via RETURN transaction on shared DB file
- Launches two concurrent `settleCredit(..., 60)` calls on separate DB connections
- Asserts **exactly 1** of the two calls returns success
- Asserts **exactly 1** committed REFUND row with amount 60
- Asserts committed balance is -40 (100 credit − 60 refunded)

It does **not** require the losing transaction to throw a specific failure code (BUSY → `unexpectedFailure` is acceptable). It **does** prove both refunds cannot commit.

### Test weakness (informational)
- Test O compares Arabic message to itself rather than a fixed expected string — low signal, but harmless.

---

## 12. Regression Results (independent re-run)

| Suite | Result |
|-------|--------|
| A. Focused Step 2.8A | **15/15 PASS** |
| B. Customer Returns Phase C (11 files) | **192/192 PASS** |
| C. Supplier regression (11 files) | **131/131 PASS** |

All runs used `-j 1`.

---

## 13. Static Validation

| Check | Result |
|-------|--------|
| Scoped `flutter analyze` (3 files) | **0 errors, 0 warnings** (7 `info`-level hints: pre-existing `prefer_const_constructors`, test `depend_on_referenced_packages`) |
| `dart format --set-exit-if-changed` | **PASS** (0 files changed) |
| Windows debug build | **PASS** — `build\windows\x64\runner\Debug\lez_pos.exe` |
| `schemaVersion` | **32** (`app_database.dart:147`) |

---

## 14. Financial Ledger Check

No changes to `FinancialLedgerRepository`. CUSTOMER_REFUND events remain derived from committed `customer_transactions` REFUND rows via existing SQL (`'CUSTOMER_REFUND:' || ct.id`). No direct Cash Ledger write was introduced by Step 2.8A.

---

## 15. Deferred Work — Confirmed Untouched

- Invoice Details `returnId` wiring
- DB UNIQUE `original_invoice_id`
- Global refund idempotency
- RETURN `reference_id` redesign
- `sale_item_returns.customer_return_id`
- `CustomerReturnService` refactor
- Historical backfill

---

## 16. Implementation Documentation Review

`docs/customer_returns_phase_c_step_2_8a_aggregate_concurrency.md` accurately describes:
- Original gap ✓
- Financial invariant ✓
- Guard mechanism (conditional INSERT + `changes()`) ✓
- Transaction order ✓
- Rollback behavior ✓
- Linked/unlinked coverage ✓
- SQLITE_BUSY limitation ✓
- Schema 32 unchanged ✓

Minor gap: implementation doc does not explicitly document that production lacks `busy_timeout` (only test E sets it). Documented limitation is otherwise accurate.

---

## 17. Findings Summary

### BLOCKERS
**None.**

### REQUIRES HARDENING
**None** for the Step 2.8A financial invariant (aggregate over-refund prevention). SQLITE_BUSY contention is handled safely via rollback; see Section 5.

### NON-BLOCKING
1. **SQLITE_BUSY error taxonomy** — Concurrent refund losers may receive `unexpectedFailure` instead of `amountExceedsCredit`. Financially safe; UX could be improved in a future step.
2. **Production `busy_timeout`** — Not configured in AppDatabase; may increase BUSY frequency under concurrent UI submissions compared to Test E.

### INFORMATIONAL
1. Untracked unrelated discovery/review docs and `tool/_write_2_7c_test.dart` present in working tree.
2. Test O Arabic assertion is tautological (compares helper output to itself).
3. Test J intentionally bypasses guard via override (valid rollback test pattern inherited from 2.7B).
4. Analyzer reports 7 `info`-level hints only; no warnings.

---

## 18. Final Decision

**GO TO FINAL AUDIT**

Rationale:
- BLOCKERS = 0
- REQUIRES HARDENING = 0 (financial safety invariant satisfied; contention failures roll back correctly)
- Aggregate credit concurrency gap is closed by authoritative conditional INSERT
- Architecture, Step 2.7B, and schema 32 preserved
- All focused and regression tests pass