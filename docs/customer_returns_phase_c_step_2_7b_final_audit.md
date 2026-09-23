# Customer Returns Phase C — Step 2.7B Final Audit

**Date:** 2026-09-23  
**Auditor:** Independent read-only final certification  
**Review Pass:** GO TO FINAL AUDIT (0 blockers, 0 requires hardening)  
**Baseline HEAD:** `580e463` — `feat(customer-returns): add per-return refund settlement state`  
**Branch:** `main` @ `580e463` (Step 2.7B uncommitted; nothing staged)

---

## 1. Final Certification

Step 2.7B — Service-Level Per-Return Refund Cap Enforcement — is **CERTIFIED FOR COMMIT**.

Independent re-verification confirms dual-cap enforcement is correctly wired into `CustomerRefundSettlementService.settleCredit()`, protected architecture remains untouched, transaction atomicity and rollback behave as required, and all regression suites pass.

---

## 2. Actual Baseline

```
580e463 feat(customer-returns): add per-return refund settlement state
* main 580e463 [origin/main]
```

Working tree (uncommitted Step 2.7B):

| Status | Path |
|--------|------|
| Modified | `lib/core/services/customer_refund_settlement_service.dart` |
| Modified | `lib/features/customers/utils/customer_refund_settlement_messages.dart` |
| Modified | `test/customer_return_linked_refund_ui_phase_c_step_2_4_test.dart` (fixture only) |
| Untracked | `test/customer_return_settlement_enforcement_phase_c_step_2_7b_test.dart` |
| Untracked | `docs/customer_returns_phase_c_step_2_7b_service_enforcement.md` |
| Untracked | `docs/customer_returns_phase_c_step_2_7b_review_pass.md` |

Nothing staged, committed, or pushed during this audit.

---

## 3. Scope

### Production changes (2 files only)

| File | Change |
|------|------|
| `lib/core/services/customer_refund_settlement_service.dart` | Dual-cap enforcement, REFUND-then-increment, new failure codes |
| `lib/features/customers/utils/customer_refund_settlement_messages.dart` | Arabic messages for two new failures |

### Step 2.7B deliverables (untracked)

- `test/customer_return_settlement_enforcement_phase_c_step_2_7b_test.dart` (24 tests)
- `docs/customer_returns_phase_c_step_2_7b_service_enforcement.md`

### Test-only collateral

- `test/customer_return_linked_refund_ui_phase_c_step_2_4_test.dart` — `seedLinkedReturn()` now posts real RETURN credit via `PartialReturnService`; Test I uses dynamic `min(availableCredit, returnRemaining)`. Required because cap enforcement reads `getCreditReversalTotalForSaleInvoice()`, which would be 0 for the old header-only fixture. Does not change production behavior.

### Protected (zero diff)

- `app_database.dart`, migrations, generated schema
- `customer_returns_table.dart`, `ReturnsDao` SQL primitives
- `FinancialLedgerRepository`, Cash Ledger
- `PartialReturnService`, `CustomerReturnCredit`
- Supplier refund architecture
- Refund UI widgets/providers (pre-existing message consumption only)
- Invoice Details `returnId` wiring

**SCOPE: PASS**

---

## 4. Schema Protection

- `schemaVersion = 32` (unchanged)
- No migration changes
- No generated database schema changes
- Step 2.7A `settled_amount` column and DAO primitives consumed read-only

**SCHEMA: 32 — PASS**

---

## 5. Dual-Cap Enforcement

When `returnId != null`, both gates enforced in `settleCredit()`:

**A. Return remaining refundable capacity**

```dart
creditCap = getCreditReversalTotalForSaleInvoice(customerId, originalInvoiceId)
settled = getSettledAmountForCustomerReturn(returnId) ?? 0
remainingReturnRefund = creditCap - settled
```

- Tolerance: `0.0001`
- `remaining <= tolerance` -> `noReturnRefundableAmount`
- `amount > remaining + tolerance` -> `amountExceedsReturnRefundableAmount`
- Does **not** use `customer_returns.total` (verified: zero references in service)

**B. Customer available credit**

```dart
balance = calculateBalanceFromTransactions(customerId)
availableCredit = balance < 0 ? -balance : 0.0
```

Both caps required for linked refunds (test G: 120 aggregate credit blocked by return remaining 40).

**RETURN_CAP: PASS**  
**CUSTOMER_CREDIT: PASS**

---

## 6. Non-Linked Refunds

When `returnId == null`:

- Customer-credit-only validation
- No `settled_amount` read
- No return cap calculation
- No `incrementSettledAmountIfWithinCap` call
- No `customer_returns` requirement

Test Q confirms two aggregate refunds succeed. Step 2.5 Invoice Details and Customer Profile paths unchanged (164/164 regression PASS).

**RETURN_ID_NULL: PASS**

---

## 7. Transaction Boundary

Exactly **one** `_db.transaction()` in `settleCredit()`. `recordRefundInTransaction` calls `applyTransaction` directly (no nested `transaction()`).

Verified order:

1. Customer / amount / return linkage validation
2. Dynamic return cap + `settled_amount` read + return-cap validation (linked only)
3. Customer-credit validation
4. REFUND insert (`recordRefundInTransaction`)
5. Conditional `incrementSettledAmountIfWithinCap` (linked only)
6. `postRefundHook` (test injection)
7. `CUSTOMER_REFUND` activity log
8. Commit

**TRANSACTION_ATOMICITY: PASS**

---

## 8. Rollback

**Increment failure after REFUND insert (Test J):** Override inserts REFUND then forces `settled_amount = 100` before conditional increment. Service throws `amountExceedsReturnRefundableAmount`. Verified unchanged:

- Customer balance
- REFUND row count
- `settled_amount`
- `CUSTOMER_REFUND` log count
- Derived Financial Ledger CUSTOMER_REFUND events

**REFUND insert failure (Test K):** Override throws before insert. Verified `settled_amount = 0`, `refundTxnCount = 0`.

**ROLLBACK: PASS**

---

## 9. Race Guard

Authoritative guard: Step 2.7A conditional UPDATE in `ReturnsDao.incrementSettledAmountIfWithinCap`:

```sql
UPDATE customer_returns
SET settled_amount = settled_amount + ?
WHERE id = ?
  AND settled_amount + ? <= ? + ?
```

Increment failure maps to `amountExceedsReturnRefundableAmount`. No application-level locking added.

Test J proves losing-transaction rollback. Test T verifies sequential post-settlement rejection. True parallel dual-request stress test absent (informational only; DAO primitive + rollback path establish required protection).

**RACE_GUARD: PASS**

---

## 10. Customer Credit

Existing semantics unchanged:

- `availableCredit <= 0` -> `noCustomerCredit`
- `amount > availableCredit + tolerance` -> `amountExceedsCredit`

Return-linked refunds must satisfy **both** return cap and aggregate credit. Customer-wide aggregate credit concurrency hardening remains explicitly deferred (not attempted in 2.7B).

**CUSTOMER_CREDIT: PASS**

---

## 11. Failure Types

Exactly two new enum values:

- `noReturnRefundableAmount` — zero/fully settled (tests E, N, P, T)
- `amountExceedsReturnRefundableAmount` — over remaining + conditional increment race loss (tests C, G, J)

All pre-existing failure codes unchanged.

**FAILURE_MAPPING: PASS**

---

## 12. Arabic Messages

Verified exact strings in `customer_refund_settlement_messages.dart` and dedicated test:

| Code | Arabic |
|------|--------|
| `noReturnRefundableAmount` | لا يوجد مبلغ متبقٍ قابل للاسترداد على هذا المرتجع |
| `amountExceedsReturnRefundableAmount` | مبلغ الاسترداد يتجاوز المبلغ المتبقي القابل للاسترداد على هذا المرتجع |

`CustomerRefundSettlementNotifier.submit()` surfaces via `customerRefundSettlementFailureMessage(e.code)`. No new UI architecture.

**PASS**

---

## 13. Cash Invoice

Test P: cash invoice partial return yields `creditCap = 0`. Linked refund rejected with `noReturnRefundableAmount` despite unrelated aggregate credit. `refundTxnCount = 0`.

**PASS**

---

## 14. Historical State

Test R: historical REFUND + backfill yields `settled_amount = 35`; new refund 65 succeeds -> `settled_amount = 100`. Further refund rejection covered by tests E and T. No double-counting.

**PASS**

---

## 15. Multiple Return Documents

Test S: Return A (60 settled) and Return B (25 settled) operate independently. Refund against A does not consume B capacity.

**PASS**

---

## 16. Reference ID Safety

| Transaction | `reference_id` | Test |
|-------------|----------------|------|
| Partial RETURN | `sale_item_returns.id` | V |
| Linked REFUND | `customer_returns.id` | U |
| Unlinked REFUND | `null` | Q |

No RETURN rows modified by settlement. Step 2.7B does not alter RETURN reference semantics.

**PASS**

---

## 17. Ledger Architecture

Test W: successful linked REFUND produces derived `CUSTOMER_REFUND` via `FinancialLedgerRepository.getEntries`. No direct Cash Ledger or Financial Ledger writes in service changes.

**LEDGER_ARCHITECTURE: PASS**

---

## 18. Test Integrity

`test/customer_return_settlement_enforcement_phase_c_step_2_7b_test.dart` — **24 tests**, real Drift/SQLite, no mocks.

Critical paths verified:

| Area | Tests |
|------|-------|
| Successful linked refund | A, H |
| Exact remaining / over-cap | B, C |
| Cumulative partial refunds | D |
| Fully settled | E |
| Both caps | G |
| Increment failure rollback | J |
| REFUND failure rollback | K |
| Cash invoice | P |
| `returnId` null | Q |
| Historical settled_amount | R |
| Independent returns | S |
| Reference IDs | U, V |
| Derived CUSTOMER_REFUND | W |
| Arabic messages | messages test |

Test O is model-only (`CustomerReturnDetail.isRefundLinkEligible`) — acceptable UI boundary check. Step 2.4 fixture correction is test-only and justified (see section 3).

**TEST_INTEGRITY: PASS**

---

## 19. Regression

Independent re-run (`-j 1`):

| Suite | Result |
|-------|--------|
| Focused Step 2.7B | **24/24 PASS** |
| Customer Steps 1->2.7B (9 files) | **164/164 PASS** |
| Supplier regression (11 files) | **131/131 PASS** |

**REGRESSION: PASS**

---

## 20. Analyzer / Format / Build

| Check | Result |
|-------|--------|
| Scoped analyzer (4 Step 2.7B files) | **0 errors, 0 warnings**, 5 info (`prefer_const_constructors`) |
| `dart format --output=none --set-exit-if-changed` | **PASS** (0 changed) |
| `flutter build windows --debug` | **PASS** |

**ANALYZER: PASS**  
**FORMAT: PASS**  
**WINDOWS_BUILD: PASS**

---

## 21. Documentation

`docs/customer_returns_phase_c_step_2_7b_service_enforcement.md` accurately documents:

- Dual-cap enforcement and dynamic `creditCap`
- `settled_amount` integration
- Transaction order (REFUND then increment)
- Rollback and race guard
- Failure types and cash invoice behavior
- `returnId` null compatibility
- Deferred: customer-wide credit concurrency, global idempotency, Step 2.7C UI, Invoice Details `returnId` wiring

No over-claiming.

**DOCUMENTATION: PASS**

---

## 22. Deferred Work

Confirmed not implemented in Step 2.7B:

- Customer-wide aggregate credit concurrency hardening
- Global refund idempotency
- Step 2.7C remaining refundable UI display
- Client-side cap validation
- Invoice Details `returnId` wiring

All documented as deferred in implementation doc.

**PASS**

---

## 23. Findings

Independent reassessment (not inherited from Review Pass):

| ID | Classification | Summary |
|----|----------------|---------|
| F-01 | INFORMATIONAL | No true parallel dual-request stress test. Test J rollback + certified 2.7A conditional UPDATE provide required protection. |
| F-02 | INFORMATIONAL | Customer-wide aggregate credit concurrency remains deferred by design. |
| F-03 | INFORMATIONAL | 5 analyzer `prefer_const_constructors` info hints on exception throws (style only). |
| F-04 | NON-BLOCKING | Step 2.4 fixture correction is test-only, required for valid linked-refund regression under cap enforcement. |
| F-05 | INFORMATIONAL | Test O validates UI model boundary only, not `settleCredit` directly. |
| F-06 | INFORMATIONAL | Test R validates historical PASS path; further-refund rejection at full cap covered by E/T. |

**BLOCKERS: 0**  
**REQUIRES HARDENING: 0**  
**NON-BLOCKING: 1**  
**INFORMATIONAL: 5**

---

## 24. Final Decision

All certification criteria met:

- Scope limited to service layer + messages
- Schema 32 unchanged
- Dual-cap enforcement correct for linked refunds
- Non-linked refunds preserved
- Single-transaction atomicity with REFUND-then-increment order
- Rollback proven on increment and REFUND failures
- Race guard via certified DAO primitive
- Failure types, Arabic messages, ledger derivation correct
- 24 focused tests + full regression clean
- Analyzer, format, Windows build pass
- Documentation accurate; deferred work not implemented

---

BLOCKERS: 0  
REQUIRES_HARDENING: 0  
NON_BLOCKING: 1  
INFORMATIONAL: 5  

FOCUSED_TESTS: 24/24 PASS  
CUSTOMER_REGRESSION: 164/164 PASS  
SUPPLIER_REGRESSION: 131/131 PASS  

ANALYZER: PASS  
FORMAT: PASS  
WINDOWS_BUILD: PASS  
SCHEMA: 32  

TRANSACTION_ATOMICITY: PASS  
ROLLBACK: PASS  
RACE_GUARD: PASS  
RETURN_CAP: PASS  
CUSTOMER_CREDIT: PASS  
RETURN_ID_NULL: PASS  
FAILURE_MAPPING: PASS  
LEDGER_ARCHITECTURE: PASS  
TEST_INTEGRITY: PASS  
DOCUMENTATION: PASS  
SCOPE: PASS  

**FINAL DECISION:**

**CERTIFIED FOR COMMIT**