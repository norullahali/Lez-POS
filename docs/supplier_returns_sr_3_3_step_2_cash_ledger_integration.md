# Supplier Returns SR.3.3 Step 2 - Cash Ledger Integration

**Date:** 2026-08-11
**Schema:** 31 (unchanged)
**Scope:** Derived Cash Ledger SUPPLIER_REFUND inflow from supplier_transactions REFUND rows

---

## 1. Cash refund vs goods return

| Event | Supplier txn | Cash Ledger |
|-------|--------------|-------------|
| Goods return (SR.2) | RETURN, negative | 0 events |
| Cash refund (SR.3.3) | REFUND, positive | 1 SUPPLIER_REFUND inflow |

GOODS RETURN != CASH REFUND. These concepts remain separate.

---

## 2. Cash Ledger event type

- **Code:** `SUPPLIER_REFUND`
- **Enum:** `CashLedgerEventType.supplierRefund`
- **Label (AR):** استرداد من مورد
- **Direction:** `inflow` (cash received from supplier)
- **Source table:** `supplier_transactions` WHERE `type = 'REFUND'` AND `amount > 0`

---

## 3. Amount / sign convention

**Supplier accounting (source of truth):**
- `REFUND` stores positive `amount`
- Effect: `balance += refundAmount` (credit consumed toward zero)

**Cash Ledger (derived read model):**
- `amount` = positive magnitude (`st.amount`)
- `direction` = `'inflow'`
- Running balance increases (cash enters the business)

This mirrors `SUPPLIER_PAYMENT` (outflow, negative supplier txn) in reverse.

---

## 4. Transaction boundary

Lez POS uses a **Hybrid Cash Ledger** — no ledger persistence table.

Atomicity is guaranteed by the existing service transaction:

```
SupplierRefundSettlementService.settleCredit()
  db.transaction {
    validate supplier / amount / optional return
    read balance + credit
    recordRefundInTransaction()   // supplier_transactions REFUND
    [optional test hooks]
    activity log SUPPLIER_REFUND
  }
```

One committed `REFUND` row produces exactly one derived `SUPPLIER_REFUND` ledger event via UNION SQL. No separate Cash Ledger insert API exists.

---

## 5. REFUND + Cash Ledger atomicity

| Outcome | REFUND rows | Cash Ledger SUPPLIER_REFUND |
|---------|-------------|----------------------------|
| Success | 1 | 1 (after commit, via UNION) |
| Validation failure | 0 | 0 |
| Rollback (post-refund hook / accounting failure) | 0 | 0 |

Tests K and L verify rollback using `@visibleForTesting` hooks on the settlement service.

---

## 6. Reference / traceability

UNION branch:

- `reference_type` = `supplier_transaction`
- `reference_id` = supplier transaction id
- `supplier_id` = supplier
- `invoice_id` = `supplier_returns.purchase_invoice_id` when `reference_id` links a return

Trace chain: Cash Ledger -> REFUND txn -> optional supplier return -> purchase invoice.

---

## 7. Failure rollback behavior

Failed `settleCredit()` leaves:
- supplier balance unchanged
- zero REFUND transactions
- zero visible SUPPLIER_REFUND ledger events
- activity log unchanged when failure occurs before log insert

---

## 8. Existing Cash Ledger compatibility

No changes to other UNION branches. `SUPPLIER_PAYMENT`, expenses, sales, customer payments, and goods-return paths unchanged.

UI updates (minimal):
- Filter dropdown auto-includes new enum value
- Drill-down routes to supplier profile (same as SUPPLIER_PAYMENT)
- Dashboard recent activity icon: `call_received`

---

## 9. Schema status

**31 -> 31** — no migration. Uses existing `supplier_transactions` and `supplier_returns` tables.

---

## 10. Test results

| Suite | Result |
|-------|--------|
| SR.3.3 Step 2 focused | 14/14 PASS |
| Full supplier-returns regression | 94/94 PASS |
| flutter analyze (Step 2 files) | 0 errors |
| Windows debug build | PASS |

---

## 11. Deferred work

- UI refund dialog / settlement button (Step 3)
- Arabic failure mapper (Step 3)
- Generic idempotency / double-submit guard (Step 3)
- Per-return settled_amount tracking (architecture deferred)

---

## Canonical API (unchanged)

`SupplierRefundSettlementService.settleCredit({ supplierId, amount, returnId?, note? })`

Cash Ledger visibility: `FinancialLedgerRepository.getEntries()` / `getSummary()`.
