# Customer Returns — Phase C Step 1
## Partial Credit Reversal + Return All Remaining

**Date:** 2026-08-16  
**Schema:** 31 (unchanged)  
**Scope:** F-02 blocker fix, F-04 hardening, Return All Remaining, tests only.

---

## 1. Existing behavior (before Step 1)

| Path | Stock | Invoice status | Customer credit |
|------|-------|----------------|-----------------|
| Full return (no prior partials) | Restored via `customer_returns` + `customer_return_items` | `returned` | Full `debtAmount` reversed via `customer_transactions RETURN` |
| Partial return | Restored via `sale_item_returns` | `partially_returned` or `returned` | **Not posted** (F-02) |
| Full return after partial (DAO) | Attempted original sold quantities | Broken | N/A |

Cash sales (`debtAmount == 0`): no customer RETURN transaction; Cash Ledger derived from `return_audit_logs` (unchanged).

---

## 2. F-02 root cause

`PartialReturnService.processPartialReturn` restored stock and wrote audit rows atomically, but never called `CustomerAccountsDao` for credit invoices. Only `ReturnsDao.returnFullSaleInvoice` (pure full path) posted `customer_transactions.type = RETURN`.

**Impact:** Partial returns on credit invoices left customer receivables overstated.

---

## 3. F-04 root cause

`ReturnsDao.returnFullSaleInvoice` always iterated original `sale_items` quantities. After partial returns, this would over-return stock and could duplicate financial effects if the UI block were removed.

**Impact:** DAO was unsafe for full return after partial; UI blocked the scenario.

---

## 4. Partial credit reversal semantics

Authoritative calculation in `CustomerReturnCredit` (not UI):

```
returnedGoodsValue = sum((returnedQty / soldQty) * line.total) per line
creditReversal     = returnedGoodsValue * (invoice.debtAmount / invoice.total)
```

- Capped so `alreadyReversed + newReversal <= invoice.debtAmount`
- `alreadyReversed` from `CustomerAccountsDao.getCreditReversalTotalForSaleInvoice`
- Posted inside the same Drift transaction as return persistence via `recordReturnInTransaction`
- `referenceId` = first `sale_item_returns.id` in the batch
- Cash / zero-debt invoices: skip (unchanged)

---

## 5. Return All Remaining semantics

`PartialReturnService.returnAllRemainingSaleInvoice`:

```
remainingQty = soldQty - alreadyReturnedQty  (per sale line)
```

- Only lines with `remainingQty > 0` are included
- Uses the partial-return path (`sale_item_returns`), not `customer_returns`
- `returnReason` = `إرجاع الكل`
- Sets invoice return metadata when the batch completes full return

`ReturnsDao.returnFullSaleInvoice` delegates to Return All Remaining when prior partial returns exist or status is `partially_returned`. Pure full return (no partials) keeps the existing `customer_returns` flow.

---

## 6. Multiple partial return behavior

Each batch:

1. Validates quantities against DB inside the transaction
2. Computes proportional credit for that batch only
3. Caps against cumulative reversal for the invoice

Sequence Partial A + Partial B + Return All Remaining cannot exceed total invoice debt.

---

## 7. Atomicity

All writes for one return share one Drift transaction:

- `sale_item_returns` / `customer_returns` + items
- stock restore + stock ledger + stock movements
- `return_audit_logs`
- `customer_transactions RETURN` (credit only)
- invoice status refresh

Failure at any step rolls back all related writes. Tests cover accounting failure (`withCreditPoster`), batch validation failure, and excess quantity rejection.

---

## 8. Cash Ledger preservation

No changes to `FinancialLedgerRepository` or Cash Ledger insertion. RETURN_REFUND derivation from audit logs remains the existing architecture. Customer Refund Settlement is **deferred**.

---

## 9. Test matrix

| ID | Scenario | Result |
|----|----------|--------|
| A | Full return on credit | PASS |
| B | Partial creates RETURN txn | PASS |
| C | Partial credit amount | PASS |
| D | No over-reversal vs goods | PASS |
| E | Multiple partials cumulative | PASS |
| F | Partial then Return All Remaining | PASS |
| G | Remaining quantities only | PASS |
| H | Fully returned line excluded | PASS |
| I | No duplicate stock restore | PASS |
| J | No duplicate credit reversal | PASS |
| K | Third return rejected | PASS |
| L | Wrong item validation | PASS |
| M | Excess qty validation | PASS |
| N | Accounting failure rollback | PASS |
| O | Batch failure rollback | PASS |
| P | Persistence failure no accounting | PASS |
| Q | Cash sale regression | PASS |
| R | Credit ledger integrity | PASS |
| — | Partial A + B + Return All Remaining | PASS |

File: `test/customer_return_phase_c_step_1_test.dart` (20 tests)

---

## 10. Deferred items

- Customer Refund Settlement service
- Customer Profile Refund Entry
- CustomerReturnService architecture refactor
- Mixed-payment edge cases beyond current POS semantics
- UI/provider widget tests (S/T) — service/DAO path covered
- Dedicated stock-failure injection (batch rollback covers txn atomicity)

---

## Files changed

**Added**
- `lib/core/services/customer_return_credit.dart`
- `test/customer_return_phase_c_step_1_test.dart`
- `docs/customer_returns_phase_c_step_1_credit_and_remaining.md`

**Modified**
- `lib/core/services/partial_return_service.dart`
- `lib/core/database/daos/customer_accounts_dao.dart`
- `lib/core/database/daos/returns_dao.dart`
- `lib/core/database/daos/sale_item_returns_dao.dart`
- `lib/features/invoices/widgets/invoice_details_dialog.dart`