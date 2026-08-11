# Supplier Returns SR.3.3 — Settlement Contract (Step 1)

**Date:** 2026-08-11  
**Schema:** 31 (unchanged)  
**Scope:** Supplier accounting REFUND transaction + settlement service only

---

## 1. REFUND meaning

`REFUND` on `supplier_transactions` records **actual cash received from a supplier** against existing **supplier credit**.

**GOODS RETURN != CASH REFUND**

| Event | Type | Amount sign | Meaning |
|-------|------|-------------|---------|
| Goods return (SR.2) | `RETURN` | Negative | Reduces payable; may create credit |
| Cash received (SR.3.3) | `REFUND` | **Positive** | Consumes credit |

---

## 2. Positive amount semantics

`REFUND` stores a **positive** `amount`. Balance effect:

```
newBalance = oldBalance + refundAmount
```

Examples:

- balance -20 + REFUND 20 → 0
- balance -20 + REFUND 10 → -10

---

## 3. Credit calculation

Authoritative balance: `SUM(supplier_transactions.amount)` via `calculateBalanceFromTransactions`.

```
availableCredit = balance < 0 ? -balance : 0
```

Aggregate credit only — per-return settled amounts deferred.

---

## 4. Validation rules (service layer)

| Rule | Failure |
|------|---------|
| Supplier exists | `supplierNotFound` |
| amount > 0 | `invalidAmount` |
| availableCredit > 0 | `noSupplierCredit` |
| amount <= availableCredit | `amountExceedsCredit` |
| return exists (if returnId) | `returnNotFound` |
| return.supplierId == supplierId | `returnSupplierMismatch` |

Credit check runs **inside** `db.transaction()`.

---

## 5. Return linkage

Optional `returnId` → stored in `supplier_transactions.referenceId`.

Traceability: REFUND → supplier return → purchase (when linked).

---

## 6. Transaction ownership

`SupplierRefundSettlementService.settleCredit()` owns `db.transaction()`.

`SupplierAccountsDao.recordRefundInTransaction()` calls `applyTransaction` only — no nested transaction.

---

## 7. Cash Ledger — not in Step 1

**RETURN (goods):** 0 Cash Ledger events (unchanged).

**REFUND:** Cash Ledger integration **deferred to SR.3.3 Step 2** (`SUPPLIER_REFUND` inflow UNION).

---

## 8. Schema

Version **31**. No migration. `type = 'REFUND'` uses free-text discriminator.

---

## 9. Idempotency boundary

No idempotency column or unique index in Step 1.

Protection: atomic transaction + in-txn credit validation. UI double-submit guard deferred to Step 3.

---

## 10. Future Step 2 contract

Add `SUPPLIER_REFUND` derived inflow in `FinancialLedgerRepository` from `supplier_transactions WHERE type = 'REFUND'`.

One committed REFUND txn → exactly one Cash Ledger inflow event.

---

## Canonical API

`SupplierRefundSettlementService.settleCredit({ supplierId, amount, returnId?, note? })`

Activity log: `SUPPLIER_REFUND` (non-authoritative audit).