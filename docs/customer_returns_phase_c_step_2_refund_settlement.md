# Customer Returns Phase C Step 2.1 — Customer Refund Settlement Foundation

**Date:** 2026-08-17  
**Schema:** 31 (unchanged)  
**Scope:** Authoritative customer REFUND transaction service only (no UI, no Cash Ledger)

---

## Objective

Establish the financial foundation for settling accumulated **customer credit** as an actual cash refund.

```
Customer accumulated credit
    ↓
CustomerRefundSettlementService.settleCredit
    ↓
customer_transactions type = REFUND
    ↓
(Cash Ledger integration — deferred to Step 2.2+)
```

**CUSTOMER GOODS RETURN ≠ CUSTOMER CASH REFUND**

| Event | Transaction type | Meaning |
|-------|------------------|---------|
| Goods return | `RETURN` | Reverses receivable for returned goods (negative amount) |
| Cash refund | `REFUND` | Settles accumulated credit with cash paid to customer (positive amount) |

---

## Customer credit semantics

Authoritative balance from `CustomerAccountsDao.calculateBalanceFromTransactions`.

```
availableCredit = balance < 0 ? -balance : 0
```

- Negative balance = customer has credit (business owes customer)
- Non-negative balance = no refundable credit
- Service never accepts balance/credit from caller — DB is authoritative

Example:

| Step | Balance | Available credit |
|------|--------:|-----------------:|
| Overpayment | -100 | 100 |
| REFUND +40 | -60 | 60 |
| REFUND +60 | 0 | 0 |

---

## REFUND transaction contract

| Field | Value |
|-------|-------|
| `type` | `'REFUND'` |
| `amount` | Positive settlement amount |
| `referenceId` | Optional `customer_returns.id` when supplied |
| `note` | Optional note |

Distinct from: `SALE`, `PAYMENT`, `RETURN`, `ADJUSTMENT`.

---

## Transaction boundary

Single Drift transaction in `CustomerRefundSettlementService.settleCredit`:

1. Validate customer exists
2. Validate amount > 0
3. Validate optional return linkage
4. Calculate authoritative balance and available credit
5. Reject if no credit or amount exceeds credit
6. Persist REFUND via `CustomerAccountsDao.recordRefundInTransaction`
7. Activity log (`CUSTOMER_REFUND` via `logsDao`)

No nested transaction. DAO is low-level only.

---

## Validation rules

| Rule | Failure |
|------|---------|
| Customer not found | `customerNotFound` |
| amount <= 0 | `invalidAmount` |
| balance >= 0 | `noCustomerCredit` |
| amount > available credit | `amountExceedsCredit` |
| returnId not found | `returnNotFound` |
| return belongs to different customer | `returnCustomerMismatch` |
| Unexpected error | `unexpectedFailure` |

---

## Return linkage

When `returnId` is supplied:

- Load `customer_returns` row
- Derive customer via `originalInvoiceId` → `sales_invoices.customer_id`
- Reject if return missing or customer mismatch

No new columns. No per-return settled_amount tracking. Aggregate credit settlement only.

---

## Files

| Action | File |
|--------|------|
| NEW | `lib/core/services/customer_refund_settlement_service.dart` |
| MODIFIED | `lib/core/database/daos/customer_accounts_dao.dart` (+ `recordRefundInTransaction`) |
| NEW | `test/customer_refund_settlement_phase_c_step_2_test.dart` |

---

## Cash Ledger — explicitly deferred

NOT modified in this step:

- `FinancialLedgerRepository`
- `CashLedgerEventType`
- Cash Ledger UNION / UI

Goods-return `RETURN_REFUND` derivation unchanged.

---

## Schema

**31 → 31** — no migration, no new table/column/index.

---

## Test matrix

| ID | Scenario | Result |
|----|----------|--------|
| A | Full credit settlement (-100 → 0) | PASS |
| B | Partial settlement (-100 → -60) | PASS |
| C | Second partial (remaining 60) | PASS |
| D | Over-settlement rejected | PASS |
| E | No credit (balance >= 0) rejected | PASS |
| F | Zero amount rejected | PASS |
| G | Negative amount rejected | PASS |
| H | Customer not found | PASS |
| I | Return not found | PASS |
| J | Return/customer mismatch | PASS |
| K | REFUND type and positive amount | PASS |
| L | referenceId traceability | PASS |
| M | Rollback on post-refund failure | PASS |
| M2 | Rollback on accounting failure | PASS |
| N | PAYMENT regression | PASS |
| O | RETURN regression (Phase C.1 partial) | PASS |
| P | Credit authority from DB state | PASS |

**Focused tests: 17/17 PASS**

---

## Regression results

Combined suite (Phase C.1 + Step 2.1 + supplier refund + cash ledger forensic):

**75/76 PASS**

Sole failure: `test/cash_ledger_forensic_runtime_test.dart` (pre-existing harness issue).

Phase C Step 1 tests: **20/20 PASS** (unchanged).

---

## Known limitations

- No UI refund dialog
- No Customer Profile refund entry
- No Cash Ledger CUSTOMER_REFUND event
- No idempotency column or framework
- No per-return settled_amount tracking
- UI double-submit protection deferred to UI step

---

## Deferred work

- Customer Refund Cash Ledger integration (Step 2.2+)
- Customer Profile Refund UI
- Refund settlement UI dialog
- `CustomerReturnService` architecture refactor
- Arabic failure message mapping for UI

---

## Validation summary

| Check | Result |
|-------|--------|
| flutter analyze (Step 2 scope) | 0 errors, 0 warnings, 3 infos |
| flutter analyze (project) | 0 errors |
| dart format | 0 files changed (after format) |
| Windows build | PASS |
| Schema | 31 |
| Cash Ledger changes | 0 |
| Protected architecture | UNCHANGED |