# Customer Returns Phase C - Step 2.7B Service Enforcement

**Date:** 2026-09-23  
**Baseline:** Step 2.7A commit `580e463`  
**Schema:** 32 (unchanged)

---

## 1. Scope

Step 2.7B connects the certified Step 2.7A state layer to `CustomerRefundSettlementService.settleCredit()` for return-linked refunds only.

Production changes:

- `lib/core/services/customer_refund_settlement_service.dart`
- `lib/features/customers/utils/customer_refund_settlement_messages.dart`

---

## 2. Dual-Cap Enforcement

When `returnId != null`, both gates must pass:

1. **Customer available credit** (existing aggregate rule)
2. **Return remaining refundable capacity** (new)

```
remainingReturnRefund = creditCap - settled_amount
```

When `returnId == null`, only customer credit is enforced (Profile, Invoice Details).

---

## 3. Dynamic Return Credit Cap

Not stored. Computed at settlement time:

```dart
creditCap = CustomerAccountsDao.getCreditReversalTotalForSaleInvoice(
  customerId: customerId,
  invoiceId: header.originalInvoiceId,
);
```

This sums invoice-linked RETURN credit (via `customer_returns.id` or `sale_item_returns.id` references).

**Not** `customer_returns.total`.

---

## 4. settled_amount Integration

Read: `ReturnsDao.getSettledAmountForCustomerReturn(returnId)`

After successful REFUND insert (linked only):

```dart
incrementSettledAmountIfWithinCap(
  returnId: returnId,
  amount: amount,
  creditCap: creditCap,
)
```

Uses the certified Step 2.7A SQL primitive unchanged.

---

## 5. Transaction Order

Inside the existing single `_db.transaction()`:

1. Customer / amount / return linkage validation
2. Return cap pre-check (if linked)
3. Customer credit validation
4. `recordRefundInTransaction()`
5. `incrementSettledAmountIfWithinCap()` (if linked)
6. `postRefundHook` (tests)
7. `CUSTOMER_REFUND` activity log

---

## 6. Rollback

Any failure aborts the Drift transaction.

If conditional increment returns false after REFUND insert, throws `amountExceedsReturnRefundableAmount` and rolls back the REFUND row.

---

## 7. Race Guard

Pre-check is UX-oriented. Authoritative guard is the conditional UPDATE after REFUND insert.

---

## 8. Failure Types

Added to `CustomerRefundSettlementFailure`:

| Code | Arabic message |
|------|----------------|
| `noReturnRefundableAmount` | لا يوجد مبلغ متبقٍ قابل للاسترداد على هذا المرتجع |
| `amountExceedsReturnRefundableAmount` | مبلغ الاسترداد يتجاوز المبلغ المتبقي القابل للاسترداد على هذا المرتجع |

Existing failures unchanged.

---

## 9. Cash Invoice

Linked refund on zero RETURN credit (`creditCap = 0`) fails with `noReturnRefundableAmount` even if unrelated aggregate credit exists.

---

## 10. Deferred

- Customer-wide credit concurrency hardening
- Global refund idempotency
- Step 2.7C UI remaining refundable display / client cap validation
- Invoice Details `returnId` wiring

---

## 11. Tests

Focused: `test/customer_return_settlement_enforcement_phase_c_step_2_7b_test.dart` (24 tests)

Step 2.4 linked-return fixture updated to post real RETURN credit (required for linked refunds under cap enforcement).

---

Step 2.7B - pending review validation