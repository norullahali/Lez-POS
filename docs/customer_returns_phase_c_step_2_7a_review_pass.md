# Customer Returns Phase C — Step 2.7A Review Pass

**Date:** 2026-09-22  
**Reviewer:** Independent read-only verification  
**Baseline HEAD:** `09469da` — `feat(customer-returns): link partial returns to customer returns`  
**Branch:** `main` (uncommitted working-tree changes; nothing staged)

---

## 1. Executive Summary

Step 2.7A introduces persistent per-return REFUND settlement state at schema 32 via a single new column (`customer_returns.settled_amount`), a non-destructive migration with REFUND-only historical backfill, and two DAO helpers on `ReturnsDao`. Scope is limited to the state layer; refund services, UI, RETURN posting, and credit-cap enforcement remain unchanged.

Independent verification confirms schema 31 to 32 with exactly one column addition, correct backfill semantics, monotonic atomic increment primitive, protected architectures untouched, 18/18 focused tests, 140/140 customer regression, 131/131 supplier regression, analyzer clean (0 errors, 0 warnings), format PASS, Windows debug build PASS.

**No blockers identified.** Step 2.7A is ready to proceed to final audit pending commit of the implementation.

---

## 2. Git Scope

### Baseline verification

```
09469da feat(customer-returns): link partial returns to customer returns
* main 09469da [origin/main]
```

### Working tree (uncommitted)

| Category | Files |
|----------|-------|
| Production | `lib/core/database/app_database.dart`, `app_database.g.dart`, `daos/returns_dao.dart`, `tables/customer_returns_table.dart` |
| Tests | `test/customer_return_settlement_state_phase_c_step_2_7a_test.dart` (untracked) |
| Documentation | `docs/customer_returns_phase_c_step_2_7a_settlement_state.md` (untracked) |
| Unrelated docs | Pre-existing untracked docs from earlier steps (2.5, 2.6, assessment) |

### Diff stat

```
 lib/core/database/app_database.dart                | 31 ++++++++-
 lib/core/database/app_database.g.dart              | 80 ++++++++++++++++++++--
 lib/core/database/daos/returns_dao.dart            | 39 +++++++++++
 lib/core/database/tables/customer_returns_table.dart | 10 ++-
 4 files changed, 152 insertions(+), 8 deletions(-)
```

**Verdict:** Scope matches Step 2.7A intent. No unrelated production changes.

**SCOPE: PASS**

---

## 3. Schema 31 to 32

| Check | Result |
|-------|--------|
| `schemaVersion` | 32 (`app_database.dart` line 147) |
| Intended change | `customer_returns.settled_amount` only |
| Type | REAL |
| Nullability | NOT NULL (Drift generated column nullable flag = false) |
| Default | 0 / 0.0 |
| Accidental tables/columns/FKs/indexes | None observed in diff |

**SCHEMA: PASS**

---

## 4. Migration Safety

Migration block: `if (from < 32)` in `app_database.dart` (lines 807-835).

| Check | Result |
|-------|--------|
| Path | `ALTER TABLE customer_returns ADD COLUMN settled_amount REAL NOT NULL DEFAULT 0` |
| Destructive recreation | No — additive ALTER TABLE only |
| `customer_returns` data survives | Yes — column added with DEFAULT 0, then backfill UPDATE |
| `customer_return_items` | Untouched |
| `customer_transactions` | Untouched (read-only in backfill SELECT) |
| Convention | Matches project versioned `if (from < N)` blocks with try/catch debugPrint |
| Fresh DB | `onCreate` uses `m.createAll()` including `settledAmount` |
| Registration | v32 block follows v31; sequential version chain intact |

**MIGRATION: PASS**

---

## 5. Historical Backfill

Actual migration SQL:

```sql
UPDATE customer_returns
SET settled_amount = COALESCE((
  SELECT SUM(ct.amount)
  FROM customer_transactions ct
  WHERE ct.type = 'REFUND'
    AND ct.reference_id = customer_returns.id
    AND ct.amount > 0
), 0)
```

| Scenario | Verified |
|----------|----------|
| A. One linked REFUND | Test J (real v31 to v32 migration) |
| B. Multiple linked REFUNDs SUM | Test K |
| C. RETURN rows ignored | Test L |
| D. REFUND reference_id NULL ignored | Test M |
| E. REFUND for other return ignored | Test N |
| F. Negative/zero REFUND ignored | Helper test for negative; zero via SQL `amount > 0` |
| G. No REFUND to 0 | Test O |
| H. Unrelated transactions ignored | Test N |

Backfill does not derive from `customer_returns.total`, RETURN rows, aggregate balance, or invoice totals.

**BACKFILL: PASS**

---

## 6. settled_amount Semantics

Documentation and implementation agree: total positive REFUND cash settled against this `customer_returns.id`.

Does NOT mean goods return value, RETURN credit, customer balance, remaining refund, or credit cap.

Production references limited to table definition, migration, ReturnsDao helpers, and generated Drift code. No service, provider, or UI usage.

**SETTLED_AMOUNT_SEMANTICS: PASS**

---

## 7. DAO Read Helper

`getSettledAmountForCustomerReturn(returnId)` is read-only, returns `row?.settledAmount`, null when return missing (test C), no side effects.

**DAO_READ: PASS**

---

## 8. Conditional Increment

`incrementSettledAmountIfWithinCap` uses single atomic UPDATE:

```sql
UPDATE customer_returns
SET settled_amount = settled_amount + ?
WHERE id = ?
  AND settled_amount + ? <= ? + ?
```

| Check | Test |
|-------|------|
| Within cap | D |
| Above cap fails | E |
| Exact cap | G |
| Failed increment unchanged | F |
| Multiple increments | H |
| Independent return IDs | I |
| No REFUND creation | Q |
| creditCap dynamic parameter, not stored | Code review |

Returns `updated == 1`. No nested transaction. Caller must provide enclosing transaction.

**CONDITIONAL_INCREMENT: PASS**

---

## 9. Amount Validation

Entry guard: `if (amount <= 0) return false;`

Positive amounts proceed. Zero and negative rejected before SQL — monotonicity preserved. Tolerance 0.0001 on cap side matches project conventions.

Gap: no explicit test for zero/negative increment (NB-01).

---

## 10. Monotonicity

Write paths: (1) one-time migration backfill, (2) increment-only DAO primitive with positive guard. No production decrease/reset/overwrite path introduced.

**MONOTONICITY: PASS**

---

## 11. Concurrency Primitive

Single conditional UPDATE is atomic at SQLite row level. With settled=0, cap=100, amount=100: first call succeeds, second fails WHERE clause. WAL mode enabled in beforeOpen. No race test (INFO-02); primitive is safe. Service wiring deferred to 2.7B.

**CONCURRENCY_PRIMITIVE: PASS**

---

## 12. Financial Architecture Protection

`git diff HEAD` on refund service, UI, providers, PartialReturnService, FinancialLedgerRepository: empty. No settled_amount under lib/core/services/.

**FINANCIAL_ARCHITECTURE: PASS**

---

## 13. RETURN Architecture Protection

No changes to RETURN posting, sale_item_returns, document creation, stock restoration, credit reversal, or partial return behavior.

**RETURN_ARCHITECTURE: PASS**

---

## 14. Credit Cap Protection

No credit_cap column. No cap frozen at creation. creditCap is runtime parameter only. Future cap remains getCreditReversalTotalForSaleInvoice().

**PASS**

---

## 15. Migration Tests

Tests J-O use sqlite3 in-memory v31 schema, userVersion=31, AppDatabase.test triggering real v32 migration. Tests P and non-positive helper use runV32Backfill() with identical SQL.

**PASS**

---

## 16. Step 2.7A Test Integrity

18 tests in test/customer_return_settlement_state_phase_c_step_2_7a_test.dart covering A through Q plus non-positive REFUND helper. All real Drift/SQLite; no mocks.

Test R (Step 2.6 regression) covered by customer regression batch, not isolated in 2.7A file (NB-02).

---

## 17. Regression Results

| Suite | Result |
|-------|--------|
| Focused Step 2.7A | 18/18 PASS |
| Customer Steps 1 to 2.7A (8 files, -j 1) | 140/140 PASS |
| Supplier regression (11 files, -j 1) | 131/131 PASS |

---

## 18. Analyzer / Format / Build

| Check | Result |
|-------|--------|
| Analyzer (scoped 2.7A files) | 0 errors, 0 warnings, 1 info (sqlite3 dev_dependency) |
| Format (--output=none --set-exit-if-changed) | PASS |
| flutter build windows --debug | PASS |

---

## 19. Documentation

docs/customer_returns_phase_c_step_2_7a_settlement_state.md accurately states semantics, backfill, DAO helpers, no credit_cap storage, 2.7B/2.7C still required. Does not claim 2.7B complete.

**DOCUMENTATION: PASS**

---

## 20. Deferred 2.7B / 2.7C Work

Not implemented: service cap validation, refund failure codes, atomic REFUND+increment flow, UI remaining refund, UI cap validation, cash-invoice disabling, global idempotency, Invoice Details returnId wiring.

---

## 21. Findings

### BLOCKER — 0

None.

### REQUIRES HARDENING — 0

None.

### NON-BLOCKING — 4

| ID | Finding |
|----|---------|
| NB-01 | No explicit test for zero/negative increment rejection (code guard exists) |
| NB-02 | Test R not isolated in 2.7A file; covered by 140-test customer batch |
| NB-03 | Analyzer info: sqlite3 import without dev_dependency |
| NB-04 | Migration tests may emit harmless Drift multi-database debug warnings |

### INFORMATIONAL — 4

| ID | Finding |
|----|---------|
| INFO-01 | 0.0001 tolerance consistent with project; allows at most ~0.0001 over cap |
| INFO-02 | No explicit concurrency race test; UPDATE primitive is row-atomic |
| INFO-03 | Test P uses backfill helper not full migration path (same SQL) |
| INFO-04 | Zero-amount REFUND in backfill not explicitly tested |

---

## 22. Final Decision

Step 2.7A is correct, scoped, migration-safe, and regression-clean.

**GO TO FINAL AUDIT**

---

BLOCKERS: 0  
REQUIRES_HARDENING: 0  
NON_BLOCKING: 4  

FOCUSED_TESTS: 18/18 PASS  
CUSTOMER_REGRESSION: 140/140 PASS  
SUPPLIER_REGRESSION: 131/131 PASS  

ANALYZER: PASS  
FORMAT: PASS  
WINDOWS_BUILD: PASS  

SCHEMA: 32  
MIGRATION: PASS  
BACKFILL: PASS  
SETTLED_AMOUNT_SEMANTICS: PASS  
DAO_READ: PASS  
CONDITIONAL_INCREMENT: PASS  
MONOTONICITY: PASS  
CONCURRENCY_PRIMITIVE: PASS  
FINANCIAL_ARCHITECTURE: PASS  
RETURN_ARCHITECTURE: PASS  
DOCUMENTATION: PASS  
SCOPE: PASS  

FINAL DECISION: GO TO FINAL AUDIT