# Customer Returns Phase C — Step 2.7A Settlement State

**Date:** 2026-09-22  
**Baseline:** Step 2.6 commit `09469da`  
**Schema:** 31 → **32**  
**Scope:** Persistent per-return REFUND settlement state only

---

## 1. Why settled_amount Exists

Step 2.6 linked partial returns to customer_returns documents, but the refund service still validates only aggregate customer credit. Multiple REFUND rows can reference the same return with no per-document limit.

Step 2.7A adds persistent state so Step 2.7B can enforce:

```
requested refund ≤ credit_cap - settled_amount
```

without redesigning the certified refund architecture.

---

## 2. Exact Meaning

customer_returns.settled_amount = total positive REFUND cash already settled against this customer_returns.id.

### Counts toward settled_amount

- customer_transactions rows where:
  - type = REFUND
  - amount > 0
  - reference_id = customer_returns.id

### Does NOT count

- Goods return value (customer_returns.total)
- RETURN transactions (credit generation)
- Aggregate customer credit balance
- REFUND rows with reference_id = NULL
- REFUND rows referencing a different return id

---

## 3. What Is NOT Stored

credit_cap is not stored on customer_returns.

Future cap remains dynamic at settlement time via:

```dart
CustomerAccountsDao.getCreditReversalTotalForSaleInvoice(
  customerId: customerId,
  invoiceId: originalInvoiceId,
)
```

This reflects invoice-level RETURN credit attributable to the one header-per-invoice document model from Step 2.6.

---

## 4. Schema Change (31 → 32)

```sql
ALTER TABLE customer_returns
ADD COLUMN settled_amount REAL NOT NULL DEFAULT 0;
```

Drift table definition: CustomerReturns.settledAmount with default 0.0.

---

## 5. Historical Backfill

During migration to schema 32:

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

- Returns with no linked REFUND → 0
- Multiple linked REFUNDs → summed
- Unlinked REFUNDs → ignored
- RETURN rows → ignored

Forward-only; no retroactive document creation.

---

## 6. DAO Helpers

Added to ReturnsDao:

| Method | Purpose |
|--------|---------|
| getSettledAmountForCustomerReturn(returnId) | Read-only; returns null if return missing |
| incrementSettledAmountIfWithinCap(...) | Atomic conditional UPDATE for Step 2.7B |

### Conditional increment primitive

```sql
UPDATE customer_returns
SET settled_amount = settled_amount + :amount
WHERE id = :returnId
  AND settled_amount + :amount <= :creditCap + 0.0001
```

- Returns true when exactly one row updated
- Uses project tolerance 0.0001
- Does not create REFUND rows
- Does not compute credit_cap — caller passes dynamic cap
- Must run inside caller transaction (no nested txn)

---

## 7. Unchanged in Step 2.7A

- CustomerRefundSettlementService — no return-cap validation yet
- REFUND / RETURN creation paths
- Customer credit calculation
- Financial Ledger / Cash Ledger
- Refund UI and providers
- Concurrency guard wiring (primitive exists; not connected)

---

## 8. Still Required

| Step | Responsibility |
|------|----------------|
| 2.7B | Service enforcement: validate cap, INSERT REFUND, conditional increment, rollback |
| 2.7C | UI/provider display of return remaining refundable amount |

Refund cap is NOT enforced yet. Step 2.7A is state layer only.

---

## 9. Validation

Focused tests: test/customer_return_settlement_state_phase_c_step_2_7a_test.dart

---

Step 2.7A — pending review validation