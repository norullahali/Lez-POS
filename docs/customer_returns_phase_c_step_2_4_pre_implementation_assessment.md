# Customer Returns Phase C Step 2.4 — Pre-Implementation Assessment

Assessment date: 2026-08-20  
Mode: READ-ONLY  
Baseline commit: 24a45e2 (Step 2.3 certified and pushed)  
Branch: main | Working tree: clean

## 1. Executive Summary

Step 2.4 (Return-Linked Customer Refund Entry) can be implemented safely by reusing the certified Step 2.3 refund UI stack and passing `returnId` / `returnLabel` into the existing dialog and settlement service. **No schema change, no new financial service, and no protected-architecture modification are required.**

The main gap is **navigation and data assembly**: Lez POS currently has **no Customer Return detail screen**. The customer returns list is read-only tiles with no drill-down. The supplier side already implements the exact pattern (list → detail dialog → credit refund entry with return linkage).

Implementation is therefore **UI integration + read-only detail loading**, not a new refund architecture. Aggregate customer credit remains the sole refundable amount authority; `customer_returns.total` must be displayed as return metadata only, never as a per-return refundable balance.

**FINAL DECISION: READY FOR IMPLEMENTATION**

## 2. Current Certified Baseline

| Step | Commit | Capability |
|------|--------|------------|
| Phase C Step 1 | 9900c2f | Partial/full customer returns, credit reversal |
| Step 2.1 | a01993d | `CustomerRefundSettlementService.settleCredit()` |
| Step 2.2 | bc72432 | Derived `CUSTOMER_REFUND` Cash Ledger UNION |
| Step 2.3 | 24a45e2 | Profile refund UI, dialog, provider, tests A–R |

Certified refund path (unchanged):

```
Customer Profile / Return Detail
  → CustomerCreditRefundEntry
  → customerAvailableCreditProvider (read-only)
  → showCustomerRefundSettlementDialog
  → CustomerRefundSettlementUiNotifier.submit()
  → CustomerRefundSettlementService.settleCredit()
  → customer_transactions REFUND
  → FinancialLedgerRepository UNION
  → CUSTOMER_REFUND OUTFLOW
```

Git baseline at assessment time:

- Branch: `main`
- Latest commit: `24a45e2 feat(customer-returns): add customer refund UI foundation`
- Working tree: **clean**

## 3. Current Customer Return Detail Architecture

### Finding: no dedicated Customer Return detail screen exists

| Asset | Path | Status |
|-------|------|--------|
| Customer returns list | `lib/features/returns/screens/customer_returns_screen.dart` | Exists — flat list, **no row tap** |
| Customer return detail dialog | — | **Does not exist** |
| Supplier analog (reference) | `lib/features/returns/screens/widgets/supplier_return_detail_dialog.dart` | Exists with embedded refund entry |
| Invoice-centric return UI | `lib/features/invoices/widgets/invoice_details_dialog.dart` | Full/partial return actions; **no refund entry** |

### Customer returns list data (current)

Query in `customerReturnsProvider`:

```sql
SELECT cr.*, si.invoice_number AS sale_invoice_number
FROM customer_returns cr
LEFT JOIN sales_invoices si ON si.id = cr.original_invoice_id
```

**Shown:** return_number, sale_invoice_number, reason  
**Available in row but not shown:** id, original_invoice_id, return_date, total, notes  
**Not loaded:** customer id, customer name, return status column, refund state

List tiles have **no `onTap`** — unlike `supplier_returns_screen.dart` which opens `showSupplierReturnDetailDialog`.

### `customer_returns` schema

`lib/core/database/tables/customer_returns_table.dart`:

- id, originalInvoiceId (nullable FK → sales_invoices), returnNumber, returnDate, total, reason, notes
- **No** customer_id, status, return_type, or settled_amount columns

Partial returns use `sale_item_returns` keyed by `sale_invoice_id` and **do not create** `customer_returns` rows.

## 4. Existing Refund UI Architecture (Step 2.3)

Already certified and reusable without modification:

| Component | Path | returnId support |
|-----------|------|------------------|
| `CustomerCreditRefundEntry` | `lib/features/customers/screens/widgets/customer_credit_refund_entry.dart` | Optional `returnId`, `returnLabel` — forwarded to dialog |
| `showCustomerRefundSettlementDialog` | `lib/features/customers/screens/widgets/customer_refund_settlement_dialog.dart` | Accepts and stores both |
| `CustomerRefundSettlementUiNotifier` | `lib/features/customers/providers/customer_refund_settlement_provider.dart` | Persists in state; passes to `settleCredit()` |
| Dialog display | Same dialog file | Shows `مرتجع بضاعة للعميل` row when `returnLabel != null` |
| Profile wiring | `lib/features/customers/screens/customer_profile_screen.dart` | Uses entry with **returnId = null** |

Step 2.3 explicitly deferred: *"Return-linked refund entry from customer return detail screen"*.

## 5. Return Data Availability

### Per return row (`customer_returns`)

| Field | Available | Source |
|-------|-----------|--------|
| return id | Yes | `customer_returns.id` |
| return number | Yes | `return_number` |
| original invoice id | Yes (nullable) | `original_invoice_id` |
| returned amount (goods) | Yes | `total` |
| return date | Yes | `return_date` |
| reason / notes | Yes | `reason`, `notes` |
| line items | Yes | `customer_return_items` via `ReturnsDao.getCustomerReturnItems()` |
| customer id | **Indirect** | `original_invoice_id → sales_invoices.customer_id` |
| customer name | **Indirect** | join customers on resolved customer_id |
| return status | **No column** | invoice may have `invoice_status` (returned / partially_returned) |
| return type | **Audit log only** | `'full'`, `'partial'`, `'manual'` in audit logs — not on return row |
| existing REFUND for return | **No per-return tracking** | `customer_transactions.reference_id` may point to returnId on REFUND rows, but no settled_amount aggregate per return |

### Can the return detail screen open the existing refund dialog today?

**Not without new UI work.** Required data for the dialog:

- `customerId` — must be resolved via invoice linkage
- `customerName` — from customers table
- `availableCredit` — from `customerAvailableCreditProvider` (aggregate)
- `returnId` — from return header
- `returnLabel` — e.g. return_number

All dialog/provider/service plumbing exists. Missing pieces: detail screen, customer resolution query, list navigation.

## 6. Return-to-Customer Linkage

### Step 2.1 canonical validation (do not alter)

When `returnId != null`, `CustomerRefundSettlementService.settleCredit()`:

1. Loads `customer_returns` row by id
2. Reads `originalInvoiceId`; if null → `_resolveReturnCustomerId` returns null → **`returnNotFound`**
3. Loads invoice via `salesDao.getInvoiceById(invoiceId)`
4. Returns `invoice.customerId`
5. If resolved customer ≠ supplied `customerId` → **`returnCustomerMismatch`**
6. If row missing → **`returnNotFound`**

```dart
// customer_refund_settlement_service.dart — _resolveReturnCustomerId
customer_returns.id
  → original_invoice_id
  → sales_invoices.customer_id
```

REFUND persistence stores `referenceId: returnId` on the REFUND transaction via `recordRefundInTransaction`.

### Customer eligibility convention (existing codebase)

Across POS/returns code, **`customerId != null && customerId != 1`** denotes a real customer (id 1 = `زبون عام`). Refund entry should be hidden or disabled when customer cannot be resolved or is general customer.

### Linkage gaps

| Return origin | `customer_returns` row | Invoice link | Refund entry eligible |
|---------------|------------------------|--------------|------------------------|
| Full invoice return | Yes | Yes | Yes (if real customer + credit) |
| Manual return dialog (no invoice) | Yes | **null** | **No** — service rejects returnId linkage |
| Quick return (no invoice) | Yes (`originalInvoiceId` null) | null | **No** |
| Partial return only | **No row** | via invoice | **Out of Step 2.4 returnId scope** |

## 7. Refund Amount Semantics

### Authoritative model (unchanged)

```
availableCredit = balance < 0 ? -balance : 0
```

where `balance = CustomerAccountsDao.calculateBalanceFromTransactions(customerId)`.

### What NOT to do

- Do **not** treat `customer_returns.total` as refundable amount
- Do **not** invent per-return settled_amount or remaining-refund balance
- Do **not** pre-fill dialog amount with return total
- Do **not** imply whole return is automatically refundable

### What the UI should show

| Display | Source | Purpose |
|---------|--------|---------|
| Return total | `customer_returns.total` | Goods return metadata only |
| Available credit | `customerAvailableCreditProvider` | Sole gating + validation display |
| Refund amount | User-entered | Service validates ≤ availableCredit |

Step 2.1 explicitly deferred per-return settled_amount tracking. **Aggregate credit is sufficient** for this entry point. Multiple REFUND rows may reference the same returnId; service does not cap by return total.

### Partial return UX concern

A partial return may create credit via RETURN transactions linked to `sale_item_returns`, not `customer_returns`. User may have aggregate credit while viewing an invoice with partial return status — but **no `customer_returns.id` exists** for that flow. Step 2.4 must not conflate invoice partial-return UI with return-linked refund unless a future step adds a separate entry strategy.

## 8. Proposed Step 2.4 Flow

Mirror supplier Step 3.2 pattern:

```
CustomerReturnsScreen (list row tap)
  → showCustomerReturnDetailDialog(context, ref, returnId)
  → customerReturnDetailProvider(returnId)  [NEW read-only loader]
  → CustomerReturnDetailDialog  [NEW]
       ├─ header: return number, customer, invoice, date, total, reason
       └─ if customerId resolvable and != 1:
            CustomerCreditRefundEntry(
              customerId: resolvedCustomerId,
              customerName: resolvedCustomerName,
              returnId: returnHeader.id,
              returnLabel: returnHeader.returnNumber,
            )
  → (existing Step 2.3 dialog + submit path unchanged)
  → CustomerRefundSettlementService.settleCredit(returnId: ...)
```

**Answer to integration style:** **Option A** — pass `returnId` / `returnLabel` into existing dialog/entry. **Plus Option B-lite** — new detail dialog, read repository/provider, and list navigation (no new settlement provider logic).

## 9. UI Scope

### Smallest safe UX addition

1. **Add** `CustomerReturnDetailDialog` modeled on `SupplierReturnDetailDialog`
2. **Add** read-only detail loader resolving customer via invoice join
3. **Wire** list row tap in `customer_returns_screen.dart`
4. **Embed** existing `CustomerCreditRefundEntry` at dialog bottom when customer linkable
5. **Do not** duplicate refund dialog, provider submit logic, or messages

### Enable / disable rules

| Condition | Refund entry |
|-----------|--------------|
| `originalInvoiceId == null` | Hidden or disabled + Arabic explanation (no resolvable customer) |
| `customerId == null` or `== 1` | Hidden or disabled (general customer) |
| `availableCredit <= 0` | Disabled (existing entry behavior) |
| `availableCredit > 0` + resolvable customer | Enabled |

### Error paths (existing Arabic mapping — no new codes)

- Return not found → service `returnNotFound` → `مرتجع العميل غير موجود`
- Customer mismatch → `returnCustomerMismatch` → `المرتجع لا ينتمي إلى هذا العميل`
- No credit → `noCustomerCredit` → existing message
- Amount exceeds credit → existing message

### Display guidance

- Show return reference in dialog via existing `returnLabel` row
- Show aggregate credit via existing entry widget
- Label return total as return value, not "refundable balance"
- Optional helper text: cash refund settles aggregate customer credit, not necessarily the full return total

## 10. Financial Safety

Proposed flow preserves all certified boundaries:

| Rule | Status |
|------|--------|
| UI financial writes = 0 | Preserved — same Step 2.3 providers |
| All persistence via `settleCredit()` | Preserved |
| No direct DAO writes from UI | Preserved |
| No Cash Ledger direct write | Preserved — Step 2.2 UNION only |
| No duplicate settlement service | Preserved |
| RETURN ≠ REFUND semantics | Preserved — UI only creates REFUND via service |
| No balance mutation in UI | Preserved — invalidate + reread |

## 11. Schema Assessment

**Schema 31 unchanged — preferred outcome confirmed.**

Existing schema supports Step 2.4:

- `customer_returns` + `customer_return_items` for detail display
- `sales_invoices.customer_id` for linkage
- `customer_transactions.reference_id` for REFUND → return traceability

**No migration required.**

Limitation is **behavioral**, not schema: no per-return settled_amount column (intentionally deferred in Step 2.1).

## 12. Test Plan (future Step 2.4)

New focused suite recommended: `test/customer_return_linked_refund_ui_phase_c_step_2_4_test.dart`

Extend Step 2.3 patterns; minimum scenarios:

| ID | Scenario |
|----|----------|
| A | Return detail opens refund-capable entry when customer + credit exist |
| B | Resolved customer matches invoice customer |
| C | `returnId` propagated through entry → dialog → `settleCredit()` |
| D | `returnLabel` displayed in dialog |
| E | Customer mismatch rejected by canonical service (Arabic mapped) |
| F | Missing/unlinked return → entry hidden or service `returnNotFound` |
| G | No customer credit → entry disabled |
| H | Partial refund amount via service |
| I | Full available credit refund via service |
| J | No direct DAO write from UI |
| K | No direct Cash Ledger write |
| L | Step 2.3 profile entry unchanged (`returnId = null`) |
| M | Opening detail / entry causes zero financial writes |
| N | Derived CUSTOMER_REFUND after success (reuse Step 2.3 test R pattern) |

Regression: existing Step 2.3 (18) + Step 2.1/2.2 + supplier suites must remain green.

## 13. Protected Files (must not modify)

- `lib/core/services/customer_refund_settlement_service.dart`
- `lib/core/database/daos/customer_accounts_dao.dart`
- `lib/features/financial/repositories/financial_ledger_repository.dart`
- `lib/features/financial/models/cash_ledger_event_type.dart`
- Step 2.1 / 2.2 tests and settlement logic
- Supplier refund architecture

**Allowed:** new read repository, new detail dialog, list screen navigation, new tests/docs. Optional read helper on `ReturnsDao` (not protected) mirroring `getSupplierReturnById`.

## 14. Deferred / Out-of-Scope Items

Must **NOT** be included in Step 2.4:

- Per-return `settled_amount` tracking or remaining-refund balance
- Idempotency framework / duplicate-refund prevention per return
- Partial-return detail entry without `customer_returns` row
- Invoice details dialog refund entry (optional future enhancement)
- `CustomerReturnService` architecture refactor
- Cash Ledger / schema / customer accounting changes
- New refund settlement service or financial write path
- Remaining-quantity "return all" UX redesign
- Rewriting Step 2.3 profile refund behavior

## 15. Risks / Findings

| ID | Severity | Finding |
|----|----------|---------|
| F-1 | Implementation | No customer return detail screen — must be created |
| F-2 | Semantic | `customer_returns.total` ≠ refundable amount — UI must not imply otherwise |
| F-3 | Scope | Partial returns lack `customer_returns.id` — not returnId-linkable in Step 2.4 |
| F-4 | Eligibility | Manual/quick returns with null invoice cannot use return-linked refund |
| F-5 | Read API | `ReturnsDao` has `getCustomerReturnItems` but no `getCustomerReturnById` (supplier has one) — trivial read helper needed |
| F-6 | Encoding | Windows UTF-16 risk on new Dart files — use UTF-8 write discipline from Step 2.3 |
| F-7 | NON-BLOCKING | `CustomerCreditRefundEntry` comment references supplier Step 3.1/3.2 — cosmetic only |

**No business-rule ambiguity blocking implementation.** Constraints are documented and align with Step 2.1 deferrals.

## 16. Exact Implementation File List

### New files (recommended)

| File | Purpose |
|------|---------|
| `lib/features/returns/models/customer_return_history_models.dart` | Detail/list view models |
| `lib/features/returns/repositories/customer_return_read_repository.dart` | Read-only detail + customer resolution |
| `lib/features/returns/providers/customer_return_detail_provider.dart` | `customerReturnDetailProvider(returnId)` |
| `lib/features/returns/screens/widgets/customer_return_detail_dialog.dart` | Detail UI + embed `CustomerCreditRefundEntry` |
| `test/customer_return_linked_refund_ui_phase_c_step_2_4_test.dart` | Step 2.4 focused tests |
| `docs/customer_returns_phase_c_step_2_4_refund_ui.md` | Implementation doc (post-build) |

### Modified files (minimal)

| File | Change |
|------|--------|
| `lib/features/returns/screens/customer_returns_screen.dart` | Row tap → `showCustomerReturnDetailDialog` |

### Optional (read convenience)

| File | Change |
|------|--------|
| `lib/core/database/daos/returns_dao.dart` | Add `getCustomerReturnById(int id)` mirroring supplier |

### Reused unchanged (Step 2.3)

- `customer_credit_refund_entry.dart`
- `customer_refund_settlement_dialog.dart`
- `customer_refund_settlement_provider.dart`
- `customer_refund_settlement_messages.dart`
- `customer_profile_screen.dart` (regression only)

## 17. Implementation Boundaries

**In scope:** List → detail navigation; read-only return detail; embed existing refund entry with `returnId`/`returnLabel`; tests; docs.

**Out of scope:** Any change to settlement service, accounts DAO, ledger, schema, or refund amount authority model.

**Success criteria:** User opens a linked customer return, sees return context + aggregate credit, settles cash refund through existing dialog/service, REFUND row references returnId, Cash Ledger derives CUSTOMER_REFUND via Step 2.2.

## 18. Final Recommendation

Step 2.4 is a **narrow UI integration step** following the proven supplier return-detail + refund-entry pattern. The certified Step 2.3 stack already accepts `returnId` and `returnLabel`; Step 2.1 already validates return ownership; aggregate credit remains sufficient.

Implement by creating customer return detail navigation and embedding `CustomerCreditRefundEntry` with return context. Do not add financial logic, schema, or per-return refund accounting.

**FINAL DECISION: READY FOR IMPLEMENTATION**