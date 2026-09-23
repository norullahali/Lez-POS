# Customer Returns Phase C - Step 2.7A Final Audit

**Date:** 2026-09-23  
**Auditor:** Independent read-only final certification  
**Review Pass:** GO TO FINAL AUDIT (0 blockers, 0 requires hardening)  
**Baseline HEAD:** `09469da` - feat(customer-returns): link partial returns to customer returns  
**Branch:** `main` (uncommitted working tree; nothing staged)

---

## 1. Final Certification

Step 2.7A - Persistent Per-Return REFUND Settlement State - is **CERTIFIED FOR COMMIT**.

Independent re-verification confirms the implementation is correct, scoped, migration-safe, semantically aligned with discovery, and regression-clean. All certification criteria are met with zero blockers and zero items requiring hardening.

---

## 2. Actual Baseline

```
09469da feat(customer-returns): link partial returns to customer returns
* main 09469da [origin/main]
```

Working tree (uncommitted):

- Modified: 4 production database files
- Untracked: Step 2.7A test, Step 2.7A implementation doc, review pass doc, plus pre-existing unrelated docs from earlier steps
- Nothing staged, committed, or pushed during this audit

---

## 3. Scope

### Production changes (4 files only)

| File | Change |
|------|--------|
| `lib/core/database/app_database.dart` | schemaVersion 32; v32 migration |
| `lib/core/database/app_database.g.dart` | Regenerated Drift code |
| `lib/core/database/tables/customer_returns_table.dart` | `settledAmount` column |
| `lib/core/database/daos/returns_dao.dart` | Read + conditional increment helpers |

### Step 2.7A deliverables (untracked)

- `test/customer_return_settlement_state_phase_c_step_2_7a_test.dart`
- `docs/customer_returns_phase_c_step_2_7a_settlement_state.md`

### Diff stat

```
4 files changed, 152 insertions(+), 8 deletions(-)
```

Protected services, UI, refund providers, RETURN posting, and supplier architecture: **no diff**.

**SCOPE: PASS**

---

## 4. Schema 31 to 32

| Property | Value |
|----------|-------|
| `schemaVersion` | **32** |
| Column | `customer_returns.settled_amount` |
| Type | REAL |
| Nullability | NOT NULL |
| Default | 0 |
| Other schema changes | None |

Drift table: `RealColumn get settledAmount => real().withDefault(const Constant(0.0))();`

Generated column nullable flag: `false` (NOT NULL).

**SCHEMA: PASS**

---

## 5. Migration

Migration block: `if (from < 32)` in `app_database.dart`.

```sql
ALTER TABLE customer_returns
ADD COLUMN settled_amount REAL NOT NULL DEFAULT 0;
```

Followed by backfill UPDATE (see Section 6).

| Check | Result |
|-------|--------|
| Non-destructive | Yes - ALTER TABLE only, no table recreation |
| Existing `customer_returns` rows preserved | Yes - DEFAULT 0 then backfill |
| `customer_return_items` preserved | Untouched |
| `customer_transactions` preserved | Untouched (read-only in backfill) |
| Project conventions | Versioned `if (from < N)`, try/catch with debugPrint |
| Fresh database at v32 | `onCreate` -> `m.createAll()` includes column; test A + B |
| Migration from v31 | Tests J-O use in-memory v31 schema + `userVersion=31` + real Drift migration |

**MIGRATION: PASS**

---

## 6. Historical Backfill

Migration SQL:

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

| Rule | Verified |
|------|----------|
| SUM positive REFUND only | Tests J, K |
| RETURN excluded | Test L |
| NULL reference excluded | Test M |
| Unrelated return excluded | Test N |
| Zero amount excluded | SQL `amount > 0` |
| Negative excluded | Helper test |
| No REFUND -> 0 | Test O |
| Multiple REFUNDs summed | Test K |

Does NOT derive from `customer_returns.total`, invoice total, customer balance, or RETURN transactions. Test P confirms `settled_amount` may exceed goods total.

**BACKFILL: PASS**

---

## 7. settled_amount Semantics

**Certified meaning:** total positive REFUND cash already settled against this `customer_returns.id`.

**Does NOT mean:** returned goods value, RETURN credit, customer balance, credit cap, or remaining refundable amount.

Production references confined to database layer (4 files under `lib/core/database/`). No service, provider, or UI usage. No misuse detected.

**SETTLED_AMOUNT_SEMANTICS: PASS**

---

## 8. DAO Read

`getSettledAmountForCustomerReturn(returnId)`:

- Read-only via `getCustomerReturnById` -> `row?.settledAmount`
- Returns `null` when return missing (test C)
- No REFUND creation, credit calculation, or financial side effects

**DAO_READ: PASS**

---

## 9. Conditional Increment

`incrementSettledAmountIfWithinCap({returnId, amount, creditCap})`:

```sql
UPDATE customer_returns
SET settled_amount = settled_amount + ?
WHERE id = ?
  AND settled_amount + ? <= ? + ?
```

| Requirement | Verified |
|-------------|----------|
| Single atomic UPDATE | Yes |
| Positive amount only | `if (amount <= 0) return false` |
| Exact cap succeeds | Test G |
| Above cap fails | Test E |
| Failed update unchanged | Test F |
| Multiple increments accumulate | Test H |
| Independent return IDs | Test I |
| No nested transaction | Single `customUpdate`; caller provides txn |
| No REFUND creation | Test Q |
| `creditCap` runtime parameter | Not stored anywhere |

Tolerance: `0.0001` on cap side - consistent with project financial conventions.

**CONDITIONAL_INCREMENT: PASS**

---

## 10. Monotonicity

Production write paths:

1. One-time migration backfill (historical initialization)
2. `incrementSettledAmountIfWithinCap` - additive only, positive guard

No production decrease, reset, or arbitrary overwrite path introduced.

**MONOTONICITY: PASS**

---

## 11. Concurrency Primitive

Conditional UPDATE is row-atomic in SQLite. Example `settled_amount=0, creditCap=100, amount=100`:

- First call: WHERE `0 + 100 <= 100.0001` -> SUCCESS, `settled_amount=100`
- Second call: WHERE `100 + 100 <= 100.0001` -> FAIL, 0 rows updated

WAL mode enabled in `beforeOpen`. Service wiring correctly deferred to Step 2.7B.

**CONCURRENCY_PRIMITIVE: PASS**

---

## 12. Financial Architecture

`git diff HEAD` on protected paths: **empty**.

Unchanged:

- CustomerRefundSettlementService
- CustomerRefundSettlementUiNotifier / providers
- CustomerCreditRefundEntry
- CustomerRefundSettlementDialog
- CustomerReturnCredit
- FinancialLedgerRepository
- Cash Ledger integration
- PartialReturnService
- Supplier refund architecture

**FINANCIAL_ARCHITECTURE: PASS**

---

## 13. RETURN Architecture

No changes to RETURN posting, RETURN amounts/reference_id, sale_item_returns, stock restoration, credit reversal, partial return behavior, or customer_returns document creation.

**RETURN_ARCHITECTURE: PASS**

---

## 14. Credit Cap

- No `credit_cap` column on `customer_returns` (grep over table definitions: no matches)
- No cap frozen at document creation
- Future cap remains dynamic via `CustomerAccountsDao.getCreditReversalTotalForSaleInvoice()`
- Step 2.7A does NOT enforce cap at service or UI level

**PASS**

---

## 15. Step Boundary

Confirmed NOT implemented (deferred to 2.7B / 2.7C):

- Service-level cap enforcement
- Atomic REFUND + settled_amount service flow
- New refund failure codes for cap exceeded
- UI remaining refund display
- UI cap validation
- Cash-invoice UI changes
- Global idempotency
- Invoice Details returnId wiring

**PASS**

---

## 16. Tests

File: `test/customer_return_settlement_state_phase_c_step_2_7a_test.dart`

**18 tests - all real Drift/SQLite, no mocks**

| ID | Coverage |
|----|----------|
| A | Schema 32 |
| B | Default zero on insert |
| C | DAO read + missing return |
| D-G | Increment within/exact/over cap |
| F | Failed increment unchanged |
| H-I | Accumulation + independence |
| J-O | Migration backfill scenarios |
| P | settled_amount may exceed goods total |
| Q | No REFUND side effect |
| - | Non-positive REFUND ignored in backfill |

**FOCUSED_TESTS: 18/18 PASS**

---

## 17. Regression

| Suite | Result |
|-------|--------|
| Customer Steps 1 to 2.7A (8 files, `-j 1`) | **140/140 PASS** |
| Supplier (11 files, `-j 1`) | **131/131 PASS** |

Step 2.6 regression included via `customer_return_phase_c_step_2_6_test.dart` in customer batch.

**CUSTOMER_REGRESSION: 140/140 PASS**  
**SUPPLIER_REGRESSION: 131/131 PASS**

---

## 18. Analyzer / Format / Build

| Check | Result |
|-------|--------|
| Scoped analyzer | **0 errors, 0 warnings**, 1 info (`depend_on_referenced_packages` - sqlite3 in test) |
| Format (`--output=none --set-exit-if-changed`) | **PASS** |
| `flutter build windows --debug` | **PASS** |

**ANALYZER: PASS**  
**FORMAT: PASS**  
**WINDOWS_BUILD: PASS**

---

## 19. Documentation

`docs/customer_returns_phase_c_step_2_7a_settlement_state.md` matches implementation:

- settled_amount REFUND-only meaning
- Historical backfill SQL and exclusions
- DAO read + conditional increment
- No credit_cap storage
- Step 2.7B required; Step 2.7C deferred
- Does not claim enforcement is live

**DOCUMENTATION: PASS**

---

## 20. Findings

### BLOCKER - 0

None.

### REQUIRES HARDENING - 0

None. Review Pass findings reassessed; none warrant escalation.

### NON-BLOCKING - 3

| ID | Finding | Reassessment |
|----|---------|--------------|
| NB-01 | No explicit unit test for zero/negative increment rejection | Code guard `amount <= 0` is clear and prevents monotonicity violation; acceptable for state-layer primitive |
| NB-02 | Step 2.6 regression not isolated in 2.7A file | Fully covered by 140-test customer batch including step_2_6 suite |
| NB-03 | Analyzer info: sqlite3 import without dev_dependency | Test-only; does not affect production or certification |

### INFORMATIONAL - 3

| ID | Finding | Reassessment |
|----|---------|--------------|
| INFO-01 | 0.0001 tolerance allows at most ~0.0001 over cap | Consistent with established project financial tolerance; immaterial at POS scale |
| INFO-02 | No explicit multi-isolate concurrency race test | Single-statement conditional UPDATE is database-atomic; acceptable for 2.7A; 2.7B should test rollback |
| INFO-03 | Migration tests may emit harmless Drift multi-database debug warnings | Test harness artifact only |

Previously noted items (zero REFUND backfill test, Test P via helper) remain covered by SQL semantics and identical backfill SQL - not escalated.

---

## 21. Final Decision

All certification criteria satisfied:

- BLOCKERS = 0
- REQUIRES_HARDENING = 0
- Schema, migration, backfill, semantics, DAO, increment, monotonicity, concurrency: PASS
- Financial and RETURN architecture: PASS
- Tests and regression: PASS
- Analyzer, format, Windows build: PASS
- Documentation and scope: PASS

**Step 2.7A is CERTIFIED FOR COMMIT.**

Recommended commit scope: 4 production files + Step 2.7A test + Step 2.7A implementation doc (+ review pass doc if desired). Unrelated untracked docs from earlier steps should remain excluded unless explicitly intended.

---

BLOCKERS: 0  
REQUIRES_HARDENING: 0  
NON_BLOCKING: 3  
INFORMATIONAL: 3  

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

FINAL DECISION: CERTIFIED FOR COMMIT