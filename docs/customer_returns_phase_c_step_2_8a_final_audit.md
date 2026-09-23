# Customer Returns Phase C — Step 2.8A Final Audit

## 1. Final Certification

Independent Final Audit of Step 2.8A (Aggregate Credit Concurrency Hardening) completed on 2026-09-23.

**Result: CERTIFIED FOR COMMIT**

All certification criteria passed. No blockers. No requires-hardening items affecting financial correctness.

---

## 2. Actual Baseline

| Check | Result |
|-------|--------|
| `git rev-parse HEAD` | `9206d4be53466834c7905ef3e94f579522df4a36` |
| `git log -1 --oneline` | `9206d4b feat(customer-returns): show remaining refundable amount` |
| Branch | `main` tracking `origin/main` at `9206d4b` |
| Step 2.8A committed? | **No** — implementation remains uncommitted working-tree changes |
| `schemaVersion` | **32** (`lib/core/database/app_database.dart:147`) |

Baseline matches expected certified review input.

---

## 3. Scope

### Tracked modifications (2 files)
| File | Diff |
|------|------|
| `lib/core/database/daos/customer_accounts_dao.dart` | +72 lines |
| `lib/core/services/customer_refund_settlement_service.dart` | +43 / -20 lines |

**Stat:** 2 files changed, 95 insertions(+), 20 deletions(-)

### Untracked — expected Step 2.8A scope
- `test/customer_refund_aggregate_concurrency_phase_c_step_2_8a_test.dart`
- `docs/customer_returns_phase_c_step_2_8a_aggregate_concurrency.md`
- `docs/customer_returns_phase_c_step_2_8a_review_pass.md` (review artifact)

### Untracked — outside Step 2.8A commit scope
- `docs/customer_returns_current_state_assessment.md`
- `docs/customer_returns_phase_c_next_step_discovery.md`
- `docs/customer_returns_phase_c_step_2_5_review_pass.md`
- `docs/customer_returns_phase_c_step_2_6_discovery.md`
- `docs/customer_returns_phase_c_step_2_6_review_pass.md`
- `docs/customer_returns_phase_c_step_2_7_discovery.md`
- `docs/customer_returns_phase_c_step_2_7b_discovery.md`
- `docs/customer_returns_phase_c_step_2_7c_discovery.md`
- `tool/_write_2_7c_test.dart`

No unrelated tracked files modified. Nothing staged, committed, or cleaned during this audit.

**SCOPE: PASS**

---

## 4. Financial Invariant

### Method
`CustomerAccountsDao.recordRefundInTransactionIfWithinAggregateCredit()`

### Actual SQL (verified in repository)
```sql
INSERT INTO customer_transactions (customer_id, type, amount, reference_id, note)
SELECT ?, 'REFUND', ?, ?, ?
WHERE COALESCE(
  (SELECT SUM(amount) FROM customer_transactions WHERE customer_id = ?),
  0
) + ? <= ?
```

### Verification checklist
| Requirement | Status |
|-------------|--------|
| Customer isolation | PASS — subquery filters `customer_id = ?` |
| Positive REFUND amount | PASS — `if (amount <= 0) return false`; REFUND stored as positive |
| Tolerance | PASS — default 0.0001, passed from service |
| Single conditional INSERT | PASS — one SQLite statement |
| Affected-row detection | PASS — `SELECT changes()`; `!= 1` → failure |
| Zero rows → no REFUND | PASS — `changes() != 1` returns false before balance update |
| Failed guard → rollback | PASS — service throws inside `_db.transaction()` |

### Invariant meaning
`SUM(amount) + refund <= tolerance` ensures post-refund aggregate balance cannot exceed zero (within tolerance). Equivalent to: aggregate customer credit cannot be over-consumed.

**FINANCIAL_INVARIANT: PASS**

---

## 5. Concurrency Guard

### Scenario: 60 + 60 against 100 credit
Test E (`customer_refund_aggregate_concurrency_phase_c_step_2_8a_test.dart:182-246`):
- Two real `sqlite3` connections on same temp `.db` file
- Two `AppDatabase.test(NativeDatabase.opened(...))` instances
- Real Drift transactions via `settleCredit()`
- `PRAGMA busy_timeout = 5000` on test connections

**Committed-state assertions:**
- Exactly 1 successful settlement (`results.where((ok) => ok).length == 1`)
- Exactly 1 committed REFUND row, amount 60
- Final balance = -40 (100 credit − 60 refunded)
- Never two REFUND rows totaling 120

### Additional concurrency scenarios (test-backed)
| Scenario | Test | Result |
|----------|------|--------|
| 60 + 40 sequential within 100 | D | Both succeed |
| 60 + 50 after linked 60 (shared pool) | G | Second fails |
| Different returnIds share aggregate pool | F | Second fails on aggregate |
| Linked + unlinked share pool | G | Unlinked fails after linked 60 |

**CONCURRENCY_GUARD: PASS**

---

## 6. SQLite Behavior

### Observed contention behavior
During concurrent Test E execution, `SqliteException(5): database is locked` may occur on the guarded INSERT. The generic catch in `settleCredit()` maps this to `CustomerRefundSettlementFailure.unexpectedFailure`. The Drift transaction rolls back.

### Reassessment
| Criterion | Finding |
|-----------|---------|
| Transaction rolls back on BUSY | YES |
| No partial REFUND remains | YES — verified by committed-state queries |
| Double commit prevented | YES — Test E proves 1 REFUND max |
| Hidden post-lock REFUND path | NONE — exception aborts txn before increment/log |
| Financial invariant intact | YES |

**Classification: NON-BLOCKING UX/resilience limitation**

Production AppDatabase does not set `PRAGMA busy_timeout` (test-only). Loser may receive `unexpectedFailure` instead of `amountExceedsCredit`. This is not a financial correctness defect.

**SQLITE_BEHAVIOR: PASS** (financial safety); noted as NON-BLOCKING for error taxonomy/resilience.

---

## 7. Transaction Order

Verified in `customer_refund_settlement_service.dart` inside single `_db.transaction()`:

1. Customer validation (lines 73-78)
2. Amount validation (lines 81-86)
3. Return validation + per-return cap pre-check when linked (lines 89-132)
4. Aggregate credit pre-check (lines 134-152)
5. Authoritative guarded REFUND INSERT (lines 162-175) or test override
6. Per-return `incrementSettledAmountIfWithinCap` when linked (lines 178-192)
7. Post-refund hook (lines 194-196)
8. Audit log (lines 198-203)

All financial writes (REFUND insert, `customer_accounts` balance update, `settled_amount` increment) occur within the same Drift transaction.

**PASS**

---

## 8. Step 2.7B Protection

`ReturnsDao.incrementSettledAmountIfWithinCap()` — **no diff** in Step 2.8A.

For `returnId != null`:
- Aggregate guard applies (Step 2.8A)
- Per-return cap pre-check still runs before REFUND
- Conditional `settled_amount` increment still runs after guarded REFUND
- Either guard failure throws inside transaction → full rollback

Tests I and J confirm per-return cap and rollback behavior remain intact.

**STEP_2_7B_PROTECTION: PASS**

---

## 9. Linked Refunds

- Aggregate guard applies when `returnId != null`
- Per-return cap applies (Step 2.7B)
- `settled_amount` updated only after successful guarded REFUND
- Tests F, N validate linked paths

**LINKED_REFUNDS: PASS**

---

## 10. Unlinked Refunds

For `returnId == null`:
- Guarded REFUND insert applies (no override in production)
- No `settled_amount` update (guarded by `if (returnId != null)`)
- Tests A-D, M, O validate unlinked/profile-style paths
- Invoice Details architecture untouched (no diff)

**UNLINKED_REFUNDS: PASS**

---

## 11. General Customer

Test L: `settleCredit(customerId: 1, amount: 10)` throws `noCustomerCredit`; zero REFUND rows. No new eligibility introduced.

**GENERAL_CUSTOMER: PASS**

---

## 12. Rollback

| Failure point | Committed REFUND? | Evidence |
|---------------|-------------------|----------|
| Aggregate guard failure | No | Tests C, H, K |
| Per-return increment failure | No | Test J; Step 2.7B Test J |
| Post-refund hook failure | No | Step 2.7B Test K pattern |
| Pre-check failures | No | Tests C, I, L |
| SQLITE_BUSY / unexpected exception | No | Test E committed-state; Drift txn rollback |
| Audit log failure | Would roll back entire txn | Standard Drift semantics |

**ROLLBACK: PASS**

---

## 13. Ledger Integrity

`FinancialLedgerRepository` — **no diff**.

CUSTOMER_REFUND events remain derived from committed `customer_transactions` REFUND rows:
```sql
'CUSTOMER_REFUND:' || ct.id ... WHERE ct.type = 'REFUND' AND ct.amount > 0
```

No direct Cash Ledger write introduced. No duplicate ledger path. RETURN accounting unchanged.

**LEDGER_INTEGRITY: PASS**

---

## 14. Test Integrity

15 focused tests in `test/customer_refund_aggregate_concurrency_phase_c_step_2_8a_test.dart`.

| Property | Status |
|----------|--------|
| Real AppDatabase / Drift | PASS — all tests |
| Test E: two real connections, same file | PASS |
| Committed-state assertions (not exception-only) | PASS — Test E queries REFUND count + balance |
| Mock bypass of guard | Only Test J (intentional rollback simulation via `@visibleForTesting` override) |
| False pass if both REFUNDs commit | Impossible — Test E would fail on `count.length == 1` |

### Test O (informational)
Arabic assertion compares `customerRefundSettlementFailureMessage(...)` to itself — tautological, non-blocking. Does not affect financial proof.

**TEST_INTEGRITY: PASS**

---

## 15. Regression

Independent re-run during Final Audit (`-j 1`):

| Suite | Result |
|-------|--------|
| Focused Step 2.8A | **15/15 PASS** |
| Customer Returns Phase C (11 files) | **192/192 PASS** |
| Supplier regression (11 files) | **131/131 PASS** |

**REGRESSION: PASS**

---

## 16. Analyzer / Format / Build

| Check | Result |
|-------|--------|
| Scoped `flutter analyze` (3 files) | **PASS** — 0 errors, 0 warnings (7 info-level hints) |
| `dart format --set-exit-if-changed` | **PASS** — 0 files changed |
| `flutter build windows --debug` | **PASS** |
| Schema | **32** |

**ANALYZER: PASS | FORMAT: PASS | WINDOWS_BUILD: PASS**

---

## 17. Documentation

Reviewed `docs/customer_returns_phase_c_step_2_8a_aggregate_concurrency.md`:

| Topic | Accurate? |
|-------|-----------|
| Original gap | Yes |
| Financial invariant | Yes |
| Guarded INSERT + `changes()` | Yes |
| Transaction order | Yes |
| Rollback | Yes |
| Linked/unlinked | Yes |
| SQLite contention limitation | Yes |
| Schema 32 | Yes |

Minor note: doc does not explicitly state production lacks `busy_timeout` (test-only). Non-blocking documentation gap.

**DOCUMENTATION: PASS**

---

## 18. Deferred Work

Confirmed untouched (no diffs):
- Invoice Details returnId wiring
- DB UNIQUE original_invoice_id
- Global refund idempotency
- RETURN reference_id redesign
- sale_item_returns.customer_return_id
- CustomerReturnService refactor
- Historical backfill

---

## 19. Unrelated Files

Unrelated untracked discovery/review documents and `tool/_write_2_7c_test.dart` remain in working tree, outside Step 2.8A commit scope. Not staged or deleted.

---

## 20. Findings

### BLOCKER
**0**

### REQUIRES HARDENING
**0**

Financial aggregate over-refund invariant is satisfied. SQLITE_BUSY contention rolls back safely without partial REFUND.

### NON-BLOCKING
1. **SQLITE_BUSY error taxonomy** — Concurrent losers may receive `unexpectedFailure` instead of `amountExceedsCredit`. Financially safe; UX/resilience improvement deferred.
2. **Production busy_timeout** — Not configured in AppDatabase; may increase lock contention frequency vs Test E.

### INFORMATIONAL
1. Unrelated untracked discovery/review docs present in working tree.
2. `tool/_write_2_7c_test.dart` untracked — exclude from Step 2.8A commit.
3. Test O Arabic assertion is tautological.
4. Test J uses intentional `refundInTransactionOverride` (valid rollback test pattern from 2.7B).
5. Analyzer reports 7 info-level hints (no warnings).

---

## 21. Final Decision

All certification criteria met:

| Criterion | Result |
|-----------|--------|
| FINANCIAL_INVARIANT | PASS |
| CONCURRENCY_GUARD | PASS |
| SQLITE_BEHAVIOR | PASS |
| ROLLBACK | PASS |
| STEP_2_7B_PROTECTION | PASS |
| LINKED_REFUNDS | PASS |
| UNLINKED_REFUNDS | PASS |
| GENERAL_CUSTOMER | PASS |
| LEDGER_INTEGRITY | PASS |
| TEST_INTEGRITY | PASS |
| REGRESSION | PASS |
| ANALYZER | PASS |
| FORMAT | PASS |
| WINDOWS_BUILD | PASS |
| SCHEMA | 32 |
| SCOPE | PASS |
| DOCUMENTATION | PASS |

# CERTIFIED FOR COMMIT