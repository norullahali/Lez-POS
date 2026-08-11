# Supplier Returns SR.3.3 — Architecture & Implementation Plan

**Date:** 2026-08-11  
**Mode:** READ-ONLY PLANNING (no production code, tests, schema, migrations, commit, or push)

---

## Executive Summary

SR.3.3 closes the financial loop after a certified goods return creates **supplier credit** (negative `supplier_accounts.current_balance`). The goods-return path remains unchanged. A **new, separate settlement event** records cash actually received from the supplier, posts a **positive** supplier ledger movement that consumes credit, and surfaces as a **Cash Ledger inflow** via the existing derived-ledger UNION pattern.

**Recommendation:** Implement settlement using a new supplier transaction type **`REFUND`** (cash received from supplier), reusing `supplier_transactions` + `SupplierAccountsDao.applyTransaction()` inside one Drift transaction. Extend `FinancialLedgerRepository` with a `SUPPLIER_REFUND` inflow branch. **Schema version 31 is sufficient** for MVP.

**Financial risk:** MEDIUM  
**Blockers:** 0  
**Requires action before Step 1:** 0

---

## 1. Certified Baseline (verified)

| Item | Status |
|------|--------|
| Git working tree (code) | CLEAN |
| Untracked doc only | `docs/supplier_returns_sr_3_3_pre_phase_assessment.md` |
| Local commits ahead of origin | 3 (SR.3.1, SR.3.2 Step 1, SR.3.2 Step 2) |
| Regression | **67/67 PASS** (verified 2026-08-11) |
| Schema | **31** |
| Goods-return path | Certified — MUST NOT be rewritten |

---

## 2. Business Objective

**Today (certified):**

```
Purchase → Goods Return → Stock RETURN_OUT → Supplier txn RETURN (negative) → Credit if balance < 0
```

**Missing:**

```
Credit visibility → Settlement action → Cash received → Cash Ledger inflow → Credit consumed → Audit trail
```

**First principle (mandatory):**

| Event | Supplier txn | Cash Ledger |
|-------|--------------|-------------|
| A. Goods return | `RETURN`, negative amount | **0 events** |
| B. Cash refund received from supplier | new `REFUND`, positive amount | **exactly 1 inflow** |

A negative balance does **not** mean cash was received.

---

## 3. Existing Financial Architecture

### 3.1 Supplier transaction model

**Table:** `supplier_transactions` (schema v31)

| Field | Role |
|-------|------|
| `type` | Free-text discriminator: `PURCHASE`, `PAYMENT`, `RETURN`, `ADJUSTMENT` (comment omits RETURN but SR.2 uses it) |
| `amount` | Signed ledger amount; **balance = SUM(amount)** |
| `referenceId` | Optional link (return uses `returnId`; payment may link invoice) |
| `note` | Human-readable audit text |

**Sign contract** (`SupplierAccountsDao.applyTransaction`):

| Type | Stored amount | Effect on balance |
|------|---------------|-------------------|
| PURCHASE | +amount | Increases payable (we owe supplier) |
| PAYMENT | -amount | Decreases payable |
| RETURN | -amount | Decreases payable (SR.2 goods return) |
| ADJUSTMENT | signed | Explicit adjustment |

**Balance:** `supplier_accounts.current_balance = SUM(supplier_transactions.amount)` recalculated on each write.

**Credit definition:** When `current_balance < 0`, available credit = `-current_balance` (supplier owes the store).

### 3.2 Cash Ledger model

**Pattern:** Read-only **derived UNION** in `FinancialLedgerRepository` — no separate cash ledger table.

**Existing supplier branch:** `SUPPLIER_PAYMENT` outflow from `supplier_transactions WHERE type = 'PAYMENT'` (with double-count guard vs purchase invoice cash).

**Goods returns:** `RETURN` type is **excluded** from UNION (certified SR.2).

**Customer refund analogue:** `RETURN_REFUND` outflow from `return_audit_logs` (cash to customer).

**Other income analogue:** `OTHER_INCOME` inflow from dedicated `other_income_records` table (separate source-of-truth table). SR.3.3 should **not** copy this pattern unless product requires standalone refund records — supplier settlement fits the **SUPPLIER_PAYMENT mirror** pattern (supplier_transactions as source of truth).

### 3.3 Supplier payment workflow (existing)

`SupplierAccountService.processPayment()`:

- Validates supplier exists
- Rejects `amount > currentBalance` (prevents overpayment when balance is positive)
- Writes `PAYMENT` with `-amount`
- Creates activity log
- **Side effect:** When balance is negative, any positive payment is rejected (`amount > -20`), so payment UI cannot be misused to settle credit

**UI:** `SupplierPaymentsScreen` calls DAO directly (not service) — existing inconsistency; SR.3.3 settlement should use a **new canonical service** and not extend payment screen semantics.

### 3.4 Customer refund pattern (reference only)

Customer cash refunds use `return_audit_logs.returned_amount` → Cash Ledger `RETURN_REFUND` outflow. Customer account `RETURN` reduces receivable. Separate events for goods reversal vs cash movement.

Supplier SR.3.3 mirrors this separation: goods `RETURN` already exists; cash settlement is a **new** event.

### 3.5 Transaction boundaries

- Drift `db.transaction()` used throughout (`SupplierReturnService`, `SupplierAccountService`)
- `applyTransaction` / `recordReturnInTransaction` must run inside caller transaction (no nested transaction)
- Cash Ledger needs **no separate write** — derived on read once supplier txn commits

### 3.6 Audit / history

- `SupplierAccountsDao.getHistory()` / `watchHistory()`
- `logsDao.insertLog()` used by payment service
- Supplier profile shows transaction list but currently only distinguishes PAYMENT vs default (PURCHASE) — RETURN/REFUND display is a UX gap for SR.3.3 UI phase

---

## 4. Accounting Semantics (scenarios A–G)

Balance = SUM(supplier_transactions.amount). Credit available = `max(0, -balance)`.

| Scenario | Starting balance | Event | Expected balance | Cash Ledger |
|----------|------------------|-------|------------------|-------------|
| **A** | Payable 100 | Return 20 (`RETURN -20`) | 80 | 0 |
| **B** | Payable 20 | Return 20 (`RETURN -20`) | 0 | 0 |
| **C** | 0 | Return 20 (`RETURN -20`) | -20 (credit) | 0 |
| **D** | -20 credit | Refund 20 cash (`REFUND +20`) | 0 | +1 inflow |
| **E** | -20 credit | Refund 10 cash (`REFUND +10`) | -10 | +1 inflow (10) |
| **F** | -20 credit | Attempt refund 30 | REJECT — no change | 0 |
| **G** | >= 0 (no credit) | Attempt refund | REJECT — no change | 0 |

**Goods return path in all A–C:** unchanged SR.2 behavior.

---

## 5. Critical Decision — How Credit Is Settled

### 5.1 Is existing balance model sufficient?

**Yes**, for MVP settlement at **supplier aggregate credit** level.

Credit is implicit in negative balance. Settlement consumes credit by posting a transaction with **positive amount** (moving balance toward zero).

### 5.2 Reuse `supplier_transactions` vs new structure

| Option | Verdict |
|--------|---------|
| Reuse `PAYMENT` with negative amount | **REJECT** — worsens credit (more negative) |
| Reuse `ADJUSTMENT` with +amount | Possible mathematically; **not recommended** — no Cash Ledger branch today; weak audit semantics |
| New type **`REFUND`** with +amount | **RECOMMENDED** — mirrors PAYMENT/RETURN pattern; clear audit label |
| New table `supplier_refund_records` | **DEFER** — unnecessary for MVP; use if future product needs voiding/amendments like expenses |

### 5.3 Proposed `REFUND` transaction semantics

| Property | Value |
|----------|-------|
| `type` | `'REFUND'` |
| `amount` | **+settlementAmount** (positive — consumes credit) |
| `referenceId` | `supplier_return.id` when settled from return context; nullable for profile-level settlement |
| `note` | Arabic description + optional user note |
| Balance effect | `balance += amount` (e.g. -20 + 10 = -10) |
| Cash Ledger | Derived inflow event |
| Goods return link | Traceable via `referenceId` when provided |

**Why positive amount:** PURCHASE uses + to increase debt; REFUND uses + to **reduce credit** (move balance toward zero). Symmetric to RETURN (-) creating credit.

### 5.4 Per-return credit vs aggregate credit

**MVP:** Validate against **aggregate** `availableCredit = -balance when balance < 0`.

**Optional enhancement (defer):** Track `settled_amount` on `supplier_returns` for per-return caps. Not required for scenarios D–G if aggregate credit is enforced.

---

## 6. Cash Ledger Design

### 6.1 New event

| Property | Value |
|----------|-------|
| Event type code | `SUPPLIER_REFUND` |
| Direction | **inflow** |
| Amount | `st.amount` (positive) |
| Source table | `supplier_transactions` |
| Filter | `st.type = 'REFUND' AND st.amount > 0` |
| `ledger_id` | `'SUPPLIER_REFUND:' || st.id` |
| `reference_type` | `'supplier_transaction'` |
| `reference_id` | `st.id` |
| `supplier_id` | `st.supplier_id` |
| `invoice_id` | Optional: join via `supplier_returns.purchase_invoice_id` when `reference_id` points to return |
| Description | Arabic e.g. `استرداد نقدي من مورد` + return number when linked |

### 6.2 Invariants

- Goods `RETURN` → **0** Cash Ledger events (unchanged)
- Successful cash settlement → **exactly 1** inflow per `REFUND` txn
- Failed settlement → **0** new supplier txns → **0** ledger events

### 6.3 Duplicate prevention

- No duplicate ledger rows for one supplier txn (1:1 like SUPPLIER_PAYMENT)
- Double-count guard: not needed vs other sources (REFUND is unique type)

### 6.4 Rollback

Single Drift transaction wrapping validation + `applyTransaction`. Failure before commit → no supplier txn → ledger read unchanged.

---

## 7. Atomicity

**Target boundary:**

```
db.transaction(() async {
  1. Validate supplier exists
  2. Read current balance (inside txn)
  3. Compute availableCredit
  4. Validate 0 < amount <= availableCredit
  5. applyTransaction(type: REFUND, amount: +amount, referenceId: returnId?)
  6. insertLog (optional)
})
```

**Cash Ledger:** No step 7 write — UNION picks up committed row.

**Concurrency:** Balance re-read inside transaction prevents two partial settlements exceeding credit (both read -20, both try 15 — second must fail after first commits). Drift SQLite serializes transactions.

---

## 8. Idempotency

**Risk:** Double-click settlement UI posts two REFUND txns.

**Minimum reliable mechanism (recommended):**

1. UI: `isSettling` + disable button (SR.3.2 posting pattern)
2. Service: atomic credit validation inside transaction
3. Optional `clientRequestId` stored in `note` or future column — defer unless needed

**Do not** build generic idempotency framework in SR.3.3.

**Optional hardening (defer):** Partial unique index on `(supplier_id, reference_id, type)` where `reference_id IS NOT NULL` — prevents two REFUND txns against same return. Conflicts with multiple partial settlements against one return — **do not add** unless product chooses one-settlement-per-return rule.

---

## 9. Traceability Chain

**Auditor question:** "Why did this cash enter the register?"

**MVP chain:**

```
Cash Ledger SUPPLIER_REFUND (supplier_transaction.id)
  → supplier_transactions REFUND (+amount, referenceId = returnId?)
    → supplier_transactions RETURN (-amount, referenceId = returnId) [goods return]
      → supplier_returns (purchase_invoice_id, supplier_id)
        → purchase_invoices / purchase_items
```

**Schema v31 sufficient** when `referenceId` on REFUND points to `supplier_returns.id`.

**Gap without referenceId:** Profile-level settlement still traceable to supplier but not to specific return — acceptable for MVP; UI should encourage linking return when opened from detail dialog.

---

## 10. UI / UX Plan (design only)

### 10.1 Primary entry point — Supplier profile

When `balance < 0`:

- Show credit label clearly (profile already uses green for negative balance under "الرصيد الدائن")
- Add action: **"تسجيل استرداد نقدي"** (Record cash refund)
- Dialog fields: amount (default = full credit), note, confirmation showing remaining credit after settlement
- Success: SnackBar + invalidate balance/history providers

**Rationale:** Smallest coherent UX; credit is a **supplier-level** balance today.

### 10.2 Secondary entry point — Return detail dialog (optional Step 3)

When viewing a return that contributed to credit:

- Show linked supplier credit context (read-only)
- Button pre-fills `referenceId = returnId` and suggested amount = min(return.total, availableCredit) — **only if return.total <= availableCredit** or document aggregate rule

**Do not** create a third settlement path elsewhere.

### 10.3 Transaction history improvements

Extend supplier profile transaction list to render:

- `PURCHASE` — purchase icon
- `PAYMENT` — payment icon
- `RETURN` — return icon (goods)
- `REFUND` — cash-in icon (settlement)

### 10.4 Out of scope for SR.3.3 UI

- Pagination, reports export, manual return creation, multi-branch

---

## 11. Security / Validation Rules (service layer)

All validation in **`SupplierRefundSettlementService`** (new) or extended `SupplierAccountService` with separate method — prefer **new service** to avoid conflating with `processPayment` overpayment rules.

| Rule | Enforcement |
|------|-------------|
| Supplier exists | Required |
| `amount > 0` | Required |
| `amount <= availableCredit` | Required (inside txn) |
| No credit (`balance >= 0`) | Reject |
| Supplier ID match | Required |
| `returnId` valid and belongs to supplier | Required when return-scoped settlement |
| No UI-trusted balance | Service reads balance from DAO |
| No direct DAO writes from UI | Provider → service only |
| Duplicate rapid submit | UI state + service atomicity |
| Typed failure enum | For Arabic messages |

---

## 12. Schema Impact

### Verdict: **Schema 31 sufficient for MVP**

**Why:**

- `supplier_transactions.type` is free text — `REFUND` fits without migration
- `referenceId` already nullable — links to return
- Cash Ledger is code-only UNION extension
- No new tables required

### Optional future migrations (defer)

| Change | When |
|--------|------|
| Document `REFUND` in table comment | Hygiene pass |
| `supplier_returns.settled_amount` | Per-return settlement tracking |
| `idempotency_key` column | Strong duplicate protection |
| Unique partial index | One-refund-per-return policy |

**Do not migrate in SR.3.3 Step 1 unless product mandates per-return caps in DB.**

---

## 13. Test Plan (design only — do not implement yet)

| # | Test | Assert |
|---|------|--------|
| 1 | Full credit settlement | balance 0; one REFUND txn; one ledger inflow |
| 2 | Partial settlement | remaining credit correct |
| 3 | Over-settlement rejected | no txn; balance unchanged |
| 4 | Zero/negative amount rejected | no txn |
| 5 | No credit rejected | balance >= 0 |
| 6 | Supplier mismatch (return scoped) | reject |
| 7 | Duplicate UI submit | one txn (UI + service) |
| 8 | REFUND txn amount sign + type | +amount, type REFUND |
| 9 | Cash Ledger exactly one inflow | SUPPLIER_REFUND |
| 10 | Goods return still zero ledger events | SR.2 regression |
| 11 | Rollback on validation failure | no partial state |
| 12 | Ledger failure N/A (derived) | document as read-path test |
| 13 | Balance after settlement | numeric scenarios D/E |
| 14 | Traceability | referenceId → return → purchase |
| 15 | SR.2 regression suite | 67/67 remain green |
| 16 | Hardening: payment UI cannot settle credit | processPayment rejects when balance negative |

**New test file (planned):** `test/supplier_refund_settlement_sr_3_3_test.dart` (~12–16 tests)

---

## 14. Scope Control

### SR.3.3 IN scope

- REFUND supplier transaction type
- Settlement service + typed failures
- Cash Ledger SUPPLIER_REFUND inflow
- Credit visibility + settlement UI (supplier profile minimum)
- Tests + documentation

### SR.3.3 OUT of scope / DEFER

- Rewriting SR.2 goods posting
- Changing RETURN semantics or Cash Ledger exclusion for goods returns
- Pagination / server-side history search
- Full reports/export module
- Manual supplier return UI redesign
- Multi-branch
- Generic idempotency framework
- Per-return settled_amount column (unless later step requires)
- Using Other Income as workaround for supplier refunds

---

## 15. Implementation Phase Breakdown

### SR.3.3 Step 1 — Accounting Contract & Settlement Service

**Objective:** Define REFUND semantics; implement `SupplierRefundSettlementService` + DAO helper `recordRefundInTransaction`; failure enum + Arabic message mapper.

**Likely files:**

- `lib/core/services/supplier_refund_settlement_service.dart` (new)
- `lib/core/database/daos/supplier_accounts_dao.dart` (+recordRefundInTransaction)
- `lib/features/returns/utils/supplier_refund_settlement_messages.dart` (new)
- `docs/supplier_returns_sr_3_3_settlement_contract.md` (new)

**Dependencies:** Certified SR.2 balance semantics  
**Financial risk:** MEDIUM  
**Tests:** Service-level unit/DB tests for scenarios D–G  
**Outcome:** Callable settlement API; no UI; no ledger UI yet

### SR.3.3 Step 2 — Cash Ledger Integration & Test Hardening

**Objective:** Add `SUPPLIER_REFUND` to UNION + `CashLedgerEventType`; full test matrix; 67/67 regression.

**Likely files:**

- `lib/features/financial/repositories/financial_ledger_repository.dart`
- `lib/features/financial/models/cash_ledger_event_type.dart`
- `test/supplier_refund_settlement_sr_3_3_test.dart`
- `lib/features/financial/widgets/cash_ledger_event_drill_down.dart` (optional supplier drill-down)

**Dependencies:** Step 1  
**Outcome:** Settlement visible in Cash Ledger; certified tests

### SR.3.3 Step 3 — Settlement UI

**Objective:** Supplier profile credit indicator + settlement dialog; optional return detail entry; transaction history icons for RETURN/REFUND.

**Likely files:**

- `lib/features/suppliers/screens/supplier_profile_screen.dart`
- `lib/features/suppliers/screens/widgets/supplier_refund_settlement_dialog.dart` (new)
- `lib/features/returns/screens/widgets/supplier_return_detail_dialog.dart` (optional link)
- Riverpod providers for settlement

**Dependencies:** Steps 1–2  
**Outcome:** End-user settlement workflow

### SR.3.3 Step 4 — Review & Final Audit

**Objective:** Read-only certification; no scope creep.

---

## 16. SR.3.3 Architecture Decision Summary

| Decision | Choice |
|----------|--------|
| **Credit representation** | Negative `supplier_accounts.current_balance`; available credit = `-balance` when balance < 0 |
| **Settlement representation** | New `supplier_transactions.type = 'REFUND'` with **positive** `amount` |
| **Cash Ledger event** | New derived `SUPPLIER_REFUND` **inflow** from `supplier_transactions WHERE type = 'REFUND'` |
| **Transaction boundary** | Single `db.transaction`: validate credit → `applyTransaction(REFUND)` → log |
| **Idempotency** | UI posting guard + atomic credit check; no framework |
| **Schema** | **Remain on v31** for MVP |
| **UI location** | **Primary:** Supplier profile when credit exists; **Secondary:** Return detail (optional, pre-filled returnId) |
| **Recommended first step** | **SR.3.3 Step 1 — Accounting Contract & Settlement Service** |

### Deferred

- Per-return settled_amount tracking
- Idempotency key column
- Reports/export
- Pagination
- Manual return UI
- Drill-down to return from dashboard (optional nice-to-have)

### Risk

**MEDIUM** — touches supplier accounting and Cash Ledger; mitigated by derived ledger pattern, isolated new service, and strong test matrix.

---

## 17. Final Status

Supplier Returns — SR.3.3 Architecture Planning

**Assessment:** COMPLETE

**Production Code Changed:** NO

**Schema Changed:** NO

**Tests Added/Changed:** NO

**Current Regression Baseline:** 67/67 PASS

**Recommended First Step:** SR.3.3 Step 1 — Accounting Contract & Settlement Service

**Financial Risk:** MEDIUM

**Blockers:** 0

**Requires Action:** 0

**FINAL DECISION:** GO TO SR.3.3 IMPLEMENTATION STEP 1

---

*Planning complete. Awaiting explicit instruction before any implementation.*