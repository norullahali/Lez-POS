# Customer Returns Phase C — Step 2.7C UI Remaining Refundable

**Date:** 2026-09-23  
**Baseline:** `57f48e1` — Step 2.7B per-return refund cap (schema 32)  
**Type:** UI / provider layer (informational only)

---

## 1. Purpose

When a customer refund is linked to a persisted return document (`returnId != null`), show the user how much can still be refunded **on that return** before submitting cash settlement. This complements the existing aggregate customer credit display without replacing it.

---

## 2. Formula (display only)

```
remainingRefundable = creditCap - settledAmount
```

Where:

- `creditCap` = `CustomerAccountsDao.getCreditReversalTotalForSaleInvoice(customerId, originalInvoiceId)`
- `settledAmount` = `ReturnsDao.getSettledAmountForCustomerReturn(returnId)`

Display normalization: if `remainingRefundable <= 0.0001`, show `0`.

These are the **same DAO sources** used by Step 2.7B service enforcement.

---

## 3. Authoritative service boundary

`CustomerRefundSettlementService.settleCredit()` remains the **sole financial mutation boundary**. UI/provider code:

- Does not write `customer_transactions`, `customer_returns`, Cash Ledger, or Financial Ledger
- Does not enforce caps financially — only informs and validates client-side for UX
- Service wins if UI state is stale

---

## 4. Read model

`ReturnRefundableSnapshot` in `customer_return_history_models.dart`:

| Field | Meaning |
|-------|---------|
| `returnId` | Linked return header id |
| `customerId` | Resolved from original invoice |
| `originalInvoiceId` | From `customer_returns.original_invoice_id` |
| `creditCap` | Invoice-scoped credit reversal total |
| `settledAmount` | Persisted `customer_returns.settled_amount` |
| `remainingRefundable` | Normalized cap minus settled |

Loaded by `CustomerReturnReadRepository.getReturnRefundableSnapshot(returnId)`.

Resolution chain: `customer_returns` → `originalInvoiceId` → sales invoice → `customerId`.

Returns `null` when header missing or invoice/customer cannot be resolved.

---

## 5. Provider architecture

`customerReturnRemainingRefundableProvider` — `FutureProvider.autoDispose.family<ReturnRefundableSnapshot?, int>` keyed by `returnId`.

- Does not overload `customerReturnDetailProvider`
- Not watched when `returnId == null`
- One return id → one scoped provider instance

---

## 6. UI placement

### CustomerCreditRefundEntry

When `returnId != null`:

- Keeps aggregate credit row (`الرصيد الدائن`)
- Adds return-specific row: **المبلغ المتبقي القابل للاسترداد على هذا المرتجع**
- Disables refund button when remaining `<= 0.0001` even if aggregate credit exists

When `returnId == null`: unchanged (no new provider, no new row).

### CustomerRefundSettlementDialog

When `ui.returnId != null`:

- Inserts `_ReturnRemainingInfoRow` after aggregate credit, before return label / amount
- Syncs `maxReturnRefundable` into dialog notifier via `ref.listen` on the remaining provider

When `returnId == null`: unchanged.

---

## 7. Loading / error behavior

- **Loading:** small inline `LinearProgressIndicator` (does not block entire dialog)
- **Error:** `تعذر تحميل المبلغ المتبقي للمرتجع` — never silently shows zero
- **Null snapshot:** neutral unavailable copy (same error convention)
- **Success:** formatted remaining amount in IQD

---

## 8. Zero remaining

When `remainingRefundable <= 0.0001`:

- Display `0`
- Disable refund entry button and dialog submit for linked returns
- Opening return detail dialog itself is **not** blocked

---

## 9. Client validation

`validateCustomerRefundAmountText(..., maxReturnRefundable: ...)` extended:

When linked and remaining known, effective max = `min(availableCredit, remainingRefundable)`.

Reuses Step 2.7B failure codes/messages:

- `noReturnRefundableAmount`
- `amountExceedsReturnRefundableAmount`

No new failure enum values. `canSubmit` requires positive return remaining when `returnId != null`.

---

## 10. Invalidation

`invalidateCustomerRefundDisplays(ref, customerId, {int? returnId})` also invalidates `customerReturnRemainingRefundableProvider(returnId)` when `returnId != null`.

Entry widget invalidates the return provider after successful dialog completion.

---

## 11. Cash return behavior

Linked return on a **cash invoice** (`creditCap = 0`):

- Remaining displays `0`
- Refund submission disabled
- Unrelated aggregate customer credit may still display but cannot enable return-linked refund

---

## 12. returnId null behavior

Profile refund and Invoice Details refund (`returnId == null`):

- No return-specific provider watch
- No return-specific row
- Aggregate credit + validation unchanged (optional parameter unused)

---

## 13. Deferred work

**Invoice Details `returnId` wiring remains deferred** (Step 2.5 intentional). Step 2.7C applies where callers already pass `returnId` (Customer Return Detail).

---

## 14. Tests

`test/customer_return_remaining_refundable_ui_phase_c_step_2_7c_test.dart` — 13 tests covering display, settled reduction, zero/disable, independence, null returnId, aggregate credit visibility, invalidation, cash invoice, historical settled, error handling, client validation, Arabic messages, dialog row.

Step 2.4 test A updated for async provider fixture (return remaining preload override).
