# Customer Returns Phase C — Step 2.7B Review Pass

**Date:** 2026-09-23  
**Reviewer:** Independent read-only validation  
**Baseline commit:** `580e463` — `feat(customer-returns): add per-return refund settlement state`  
**Schema:** 32 (unchanged)

---

## 1. Baseline

| Check | Result |
|-------|--------|
| `git log -1 --oneline` | `580e463 feat(customer-returns): add per-return refund settlement state` |
| Branch | `main` @ `580e463`, tracking `origin/main` |
| Working tree | Uncommitted Step 2.7B work only |

**Modified (tracked):**

- `lib/core/services/customer_refund_settlement_service.dart` (+55 lines)
- `lib/features/customers/utils/customer_refund_settlement_messages.dart` (+4 lines)
- `test/customer_return_linked_refund_ui_phase_c_step_2_4_test.dart` (fixture correction)

**Untracked (Step 2.7B scope):**

- `test/customer_return_settlement_enforcement_phase_c_step_2_7b_test.dart`
- `docs/customer_returns_phase_c_step_2_7b_service_enforcement.md`

No staged files. No commits or pushes during this review.

---

## 2. Scope

Production diff is limited to the two intended service-layer files. No changes to:

- `app_database.dart`, migrations, or `customer_returns_table.dart`
- `ReturnsDao.incrementSettledAmountIfWithinCap()` (read-only use; SQL unchanged)
- `FinancialLedgerRepository`, Cash Ledger, `PartialReturnService`, `CustomerReturnCredit`
- Supplier refund architecture
- Refund UI widgets, providers (except pre-existing message map consumption)
- Invoice Details `returnId` wiring

**SCOPE: PASS**

---

## 3. Actual settleCredit Flow

Verified in `CustomerRefundSettlementService.settleCredit()` — all steps run inside a **single** `_db.transaction()` with **no nested transaction** (`recordRefundInTransaction` calls `applyTransaction` directly, not `addTransaction`).

| Step | When | Verified |
|------|------|----------|
| 1. Customer validation | always | `getCustomerById` -> `customerNotFound` |
| 2. Amount validation | always | `amount <= 0` -> `invalidAmount` |
| 3. Return linkage validation | `returnId != null` | `_resolveReturnCustomerId` -> `returnNotFound` / `returnCustomerMismatch` |
| 4. Dynamic `creditCap` | `returnId != null` | `getCreditReversalTotalForSaleInvoice(customerId, originalInvoiceId)` |
| 5. `settled_amount` read | `returnId != null` | `getSettledAmountForCustomerReturn` |
| 6. Return-cap pre-check | `returnId != null` | `remaining = creditCap - settled`, tolerance `0.0001` |
| 7. Customer credit validation | always | `calculateBalanceFromTransactions` -> `availableCredit` |
| 8. REFUND insert | always | `recordRefundInTransaction` |
| 9. Conditional increment | `returnId != null` | `incrementSettledAmountIfWithinCap` |
| 10. `postRefundHook` | if injected | after increment |
| 11. `CUSTOMER_REFUND` log | always on success path | `logsDao.insertLog` |
| 12. Commit | implicit | Drift transaction commit |

**TRANSACTION_ATOMICITY: PASS**

---

## 4. Return-Linked Enforcement

For `returnId != null`:

- Validates `customer_returns` exists via `_resolveReturnCustomerId`
- Requires resolvable `originalInvoiceId` and invoice customer match
- Preserves existing `returnNotFound` and `returnCustomerMismatch` semantics
- **Does not** use `customer_returns.total` as cap (grep: zero matches in service)
- Cap source: sum of invoice-linked RETURN credit via `getCreditReversalTotalForSaleInvoice`

Tolerance and failure mapping:

- `remaining <= 0.0001` -> `noReturnRefundableAmount`
- `amount > remaining + 0.0001` -> `amountExceedsReturnRefundableAmount`
- Failed pre-checks: no REFUND, no increment, no log (tests I, C, E, N, P)

**RETURN_CAP: PASS**

---

## 5. Customer Credit Enforcement

Existing aggregate logic preserved:

```dart
balance = calculateBalanceFromTransactions(customerId)
availableCredit = balance < 0 ? -balance : 0.0
```

- `availableCredit <= 0` -> `noCustomerCredit`
- `amount > availableCredit + 0.0001` -> `amountExceedsCredit`

For return-linked refunds, **both** return cap (step 6) and customer credit (step 7) are enforced sequentially. Neither replaces the other (test G: 120 aggregate credit but 50 blocked by return remaining 40).

**CUSTOMER_CREDIT: PASS**

---

## 6. settled_amount Integration

- Read before REFUND insert (pre-check only)
- Increment only after successful REFUND insert when `returnId != null`
- Uses certified Step 2.7A DAO primitives unchanged
- `returnId == null`: no read, no increment (test Q)

**PASS**

---

## 7. Transaction Atomicity

Single Drift transaction wraps validation, REFUND, increment, hook, and log. No application-level locks added. `recordRefundInTransaction` does not open a nested transaction.

**TRANSACTION_ATOMICITY: PASS**

---

## 8. Rollback

**Increment failure (critical path):** Test J uses `refundInTransactionOverride` to insert REFUND then force `settled_amount = 100` before conditional increment. On `incrementSettledAmountIfWithinCap` returning false, service throws `amountExceedsReturnRefundableAmount`. Verified post-failure:

- Customer balance unchanged
- REFUND count unchanged
- `settled_amount` unchanged
- `CUSTOMER_REFUND` log count unchanged
- Financial ledger CUSTOMER_REFUND events unchanged

**REFUND insert failure:** Test K forces refund override exception. Verified `settled_amount = 0`, `refundTxnCount = 0`. Existing Step 2.1 `postRefundHook` rollback behavior unchanged (covered by `customer_refund_settlement_phase_c_step_2_test.dart` in regression batch).

**ROLLBACK: PASS**

---

## 9. Race Guard

Authoritative guard remains the Step 2.7A conditional UPDATE in `ReturnsDao.incrementSettledAmountIfWithinCap`:

```sql
UPDATE customer_returns
SET settled_amount = settled_amount + ?
WHERE id = ?
  AND settled_amount + ? <= ? + ?
```

Increment failure maps to `amountExceedsReturnRefundableAmount` (justified; concurrent loss indistinguishable from over-cap at UX layer).

- Test J proves losing transaction rolls back its REFUND after increment failure
- Test T proves sequential exhaustion after full settlement (not true parallel dual-request)
- No application-level fake locking added

True concurrent dual-request test (two simultaneous 100 against cap 100) is not present; rollback path and certified DAO guard are sufficient for this step.

**RACE_GUARD: PASS**

---

## 10. returnId Null Compatibility

When `returnId == null`:

- No `settled_amount` read
- No return cap calculation
- No `incrementSettledAmountIfWithinCap` call
- No `customer_returns` requirement
- Aggregate customer-credit-only behavior preserved (test Q: two unlinked refunds succeed)

Step 2.5 Invoice Details and Customer Profile paths remain valid (no production changes to those flows; regression 164/164 PASS).

**RETURN_ID_NULL: PASS**

---

## 11. Failure Types

Exactly two new enum values:

- `noReturnRefundableAmount`
- `amountExceedsReturnRefundableAmount`

Existing failures unchanged. Increment-race failure maps to `amountExceedsReturnRefundableAmount`.

**FAILURE_MAPPING: PASS**

---

## 12. Arabic Messages

Exact strings verified in `customer_refund_settlement_messages.dart` and test `messages map new failure codes to Arabic text`:

| Code | Arabic |
|------|--------|
| `noReturnRefundableAmount` | لا يوجد مبلغ متبقٍ قابل للاسترداد على هذا المرتجع |
| `amountExceedsReturnRefundableAmount` | مبلغ الاسترداد يتجاوز المبلغ المتبقي القابل للاسترداد على هذا المرتجع |

`CustomerRefundSettlementNotifier.submit()` surfaces failures via `customerRefundSettlementFailureMessage(e.code)`. No new UI architecture.

**PASS**

---

## 13. Cash Invoice

Test P: cash invoice partial return -> `creditCap = 0`. Linked refund fails with `noReturnRefundableAmount` despite unrelated aggregate credit. No REFUND created (`refundTxnCount = 0`).

**PASS**

---

## 14. Historical State

Test R: simulates Step 2.7A backfill (`settled_amount = 35` from historical REFUND). New refund 65 succeeds -> `settled_amount = 100`.

Partial/over-cap at historical baseline covered by tests B/C/G (settled 70 -> 30 pass, 31 fail; settled 60 + amount 50 fails return cap).

**PASS**

---

## 15. Reference ID Safety

| Transaction | `reference_id` | Verified |
|-------------|----------------|----------|
| Partial RETURN | `sale_item_returns.id` | Test V |
| Linked REFUND | `customer_returns.id` | Test U |
| Unlinked REFUND | `null` | Test Q (implicit) |

No RETURN rows modified by settlement. Step 2.7B does not alter RETURN reference IDs.

**PASS**

---

## 16. Ledger Architecture

Test W: successful linked REFUND produces derived `CUSTOMER_REFUND` via `FinancialLedgerRepository.getEntries`. No direct Cash Ledger or Financial Ledger writes in service changes.

**LEDGER_ARCHITECTURE: PASS**

---

## 17. Test Integrity

File: `test/customer_return_settlement_enforcement_phase_c_step_2_7b_test.dart` — **24 tests**, real Drift/SQLite, no mocks.

| ID | Scenario | Exercises production path |
|----|----------|---------------------------|
| A | Within-cap linked refund | Yes |
| B | Exact remaining (70->30) | Yes |
| C | Over-cap (31 from 70) | Yes |
| D | Cumulative partial (20+30) | Yes |
| E | Fully settled | Yes |
| F | Customer credit cap only | Yes (`returnId` null) |
| G | Both caps | Yes |
| H | Increment on success | Yes |
| I | Failed pre-check | Yes |
| J | Increment failure rollback | Yes (override simulates race loss) |
| K | REFUND failure rollback | Yes |
| L | Customer mismatch | Yes |
| M | Missing return | Yes |
| N | Zero cap (header only) | Yes |
| O | General Customer boundary | Model-only (`CustomerReturnDetail`) |
| P | Cash invoice | Yes |
| Q | `returnId` null | Yes |
| R | Historical settled_amount | Yes |
| S | Independent returns | Yes |
| T | Post-full-settlement guard | Yes (sequential, not parallel) |
| U | REFUND reference_id | Yes |
| V | RETURN reference_id | Yes |
| W | Derived CUSTOMER_REFUND | Yes |
| — | Arabic messages | Yes |

Test O validates UI eligibility model only (acceptable boundary check). Test T name implies concurrent race but verifies sequential exhaustion; concurrent loss path covered by Test J.

**TEST_INTEGRITY: PASS**

---

## 18. Step 2.4 Fixture Assessment

**Change:** `seedLinkedReturn()` replaced manual `customer_returns` header insert with `PartialReturnService.processPartialReturn()` posting real RETURN credit. Test I updated to compute refund amount from `min(availableCredit, returnRemaining)`.

**Why required:** Pre-2.7B fixture created a linked return header without RETURN credit transactions. Under Step 2.7B, `creditCap = getCreditReversalTotalForSaleInvoice()` would be **0**, causing linked refunds to fail with `noReturnRefundableAmount` — invalid for UI tests intended to exercise successful linked settlement.

**Classification:** Legitimate test fixture correction. Does **not** change production behavior. Does **not** mask a regression; it aligns fixtures with real return-credit semantics that cap enforcement now correctly depends on. Appropriately scoped to Step 2.7B regression maintenance.

**NON-BLOCKING** (test-only, justified)

---

## 19. Regression

| Suite | Command | Result |
|-------|---------|--------|
| Focused Step 2.7B | `flutter test test/customer_return_settlement_enforcement_phase_c_step_2_7b_test.dart -j 1` | **24/24 PASS** |
| Customer Steps 1->2.7B (9 files) | `-j 1` batch | **164/164 PASS** |
| Supplier regression (11 files) | `-j 1` batch | **131/131 PASS** |

Customer batch files: Step 1, 2, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7A, 2.7B.

---

## 20. Analyzer / Format / Build

| Check | Result |
|-------|--------|
| Scoped analyzer (4 Step 2.7B files) | **0 errors, 0 warnings**, 5 info (`prefer_const_constructors` on service exceptions) |
| `dart format --output=none --set-exit-if-changed` | **PASS** (0 changed) |
| `flutter build windows --debug` | **PASS** (`build\windows\x64\runner\Debug\lez_pos.exe`) |
| `schemaVersion` | **32** — no migration changes |

**ANALYZER: PASS**  
**FORMAT: PASS**  
**WINDOWS_BUILD: PASS**  
**SCHEMA: 32**

---

## 21. Documentation

`docs/customer_returns_phase_c_step_2_7b_service_enforcement.md` accurately reflects:

- Dual-cap enforcement when `returnId != null`
- Dynamic cap via `getCreditReversalTotalForSaleInvoice`
- REFUND-then-increment order and rollback
- Conditional UPDATE as race guard
- Cash invoice zero-cap behavior
- Deferred: customer-wide credit concurrency, global idempotency, Step 2.7C UI remaining display, Invoice Details `returnId` wiring

Does not over-claim implemented features.

**DOCUMENTATION: PASS**

---

## 22. Findings

| ID | Classification | Summary |
|----|----------------|---------|
| F-01 | INFORMATIONAL | Test T title suggests concurrent race; test verifies sequential post-settlement rejection. Concurrent loss rollback proven by Test J + certified 2.7A DAO. |
| F-02 | INFORMATIONAL | Customer-wide aggregate credit concurrency remains deferred (documented). Two refunds on different returns consuming same aggregate credit concurrently is a pre-existing risk. |
| F-03 | INFORMATIONAL | Analyzer reports 5 `prefer_const_constructors` info on exception throws in service (non-blocking style). |
| F-04 | NON-BLOCKING | Step 2.4 test fixture change is test-only but necessary for valid linked-refund regression under cap enforcement (see section 18). |
| F-05 | INFORMATIONAL | Test O exercises `CustomerReturnDetail` model boundary, not `settleCredit` directly. |
| F-06 | INFORMATIONAL | Test R validates historical PASS path (35+65); explicit 41-fail at settled=60 covered equivalently by tests C/G. |

**BLOCKERS: 0**  
**REQUIRES HARDENING: 0**  
**NON-BLOCKING: 1**  
**INFORMATIONAL: 5**

---

## 23. Final Decision

Independent verification confirms Step 2.7B implementation matches discovery design and review criteria. Protected architecture untouched. Transaction order is REFUND -> conditional increment -> hook -> log inside one transaction. Dual-cap enforcement, rollback, race guard, `returnId` null compatibility, failure types, Arabic messages, ledger derivation, and test coverage all pass.

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
SCOPE: PASS  

**FINAL DECISION:**

**GO TO FINAL AUDIT**