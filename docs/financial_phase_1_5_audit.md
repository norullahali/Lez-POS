# Financial Phase 1.5 — Pre-Implementation Audit

| Field | Value |
|-------|-------|
| **Project** | Lez POS |
| **Phase** | 1.5 — Audit only (no code, schema, UI, or service changes) |
| **Date** | June 8, 2026 |
| **Prerequisite** | `docs/financial_management_phase1_audit.md` |
| **Purpose** | Resolve accounting policy and integration ambiguities before Cash Ledger v1 |

---

## Executive Summary

This audit closes the gap between Phase 1 (foundation mapping) and Cash Ledger implementation. **The active purchase path is unambiguous** (`PurchasesRepository` → `PurchasesDao`), while **`PurchaseService` is dead code** with divergent ledger and stock behavior. **Session expected cash is incomplete and internally inconsistent** (UI expects `cash_returns`; DAO never computes it; partial returns are not subtracted). **Returns have four separate code paths** with no unified refund/payment-method model.

**Overall readiness for Cash Ledger v1: 48 / 100**

| Area | Score | Blocker? |
|------|-------|----------|
| Purchase flow | 52 | Policy decision on `paid_amount` sourcing |
| Session cash logic | 38 | Yes — formula and UI/DAO mismatch |
| Returns logic | 45 | Yes — cash vs credit policy undefined |
| Payments logic | 58 | Session attribution missing |
| Reporting integration | 55 | Partial overlap with `getCashFlow()` |

**Go / No-Go:** **Conditional GO** for a **read-only, derived Cash Ledger v1** scoped to explicitly defined sources and exclusion rules. **NO-GO** for session reconciliation UI and drawer-expected-cash fixes until product signs off on the recommended session formula (Section 2) and returns cash policy (Section 3).

---

## Section 1 — Purchase Posting Audit

### 1.1 Which purchase flow is actually used?

**Active path (production):**

```
PurchasesListScreen / PurchaseFormScreen
  → purchasesNotifierProvider.save()
  → PurchasesRepository.save()
  → PurchasesDao.savePurchaseInvoice()
```

**Evidence:**

| Layer | File | Role |
|-------|------|------|
| UI list | `lib/features/purchases/screens/purchases_list_screen.dart` | Routes to `/purchases/new` |
| UI form | `lib/features/purchases/screens/purchase_form_screen.dart` | `_saveInvoice()` builds model, calls notifier |
| Provider | `lib/features/purchases/providers/purchases_provider.dart` | `PurchasesNotifier.save()` → repository |
| Repository | `lib/features/purchases/repositories/purchases_repository.dart` | Wraps `PurchasesDao.savePurchaseInvoice()` |
| DAO | `lib/core/database/daos/purchases_dao.dart` | Single write transaction |

Form computes: `debtAmount = total - paidAmount` (line 636, `purchase_form_screen.dart`).

### 1.2 Is PurchaseService dead code?

**Yes — confirmed dead code.**

Repository-wide search for `PurchaseService` / `purchase_service` imports finds **only** `lib/core/services/purchase_service.dart` itself. No provider, screen, or repository references it.

Additionally dead: `PosSaleService.processReturn()` — defined but **never called** anywhere (only definition at line 167).

### 1.3 Does PurchaseService post different financial effects than PurchasesDao?

**Yes — materially different.**

| Effect | PurchasesDao (active) | PurchaseService (unused) |
|--------|-------------------------|---------------------------|
| Invoice insert | Yes | Yes |
| Stock increment | **Yes** — `current_stock + qty` | **No** — only updates `cost_price` |
| Stock ledger ref | `purchase_items` id | `purchase_invoices` id |
| Supplier ledger | `PURCHASE` for **`debtAmount` only** (if > 0) | `PURCHASE` for **`total`**, then `PAYMENT` for **`-paidAmount`** |
| Net supplier balance change | +debtAmount | +total − paid = +debtAmount (same net **if both succeed**) |
| Activity log | None | `logsDao` PURCHASE_CONFIRMED |

**PurchasesDao supplier posting (lines 115–128):**

```dart
if (debtAmt > 0) {
  await db.supplierAccountsDao.addTransaction(
    type: 'PURCHASE', amount: debtAmt, referenceId: invoiceId, ...);
}
```

**PurchaseService supplier posting (lines 35–52):**

```dart
await addTransaction(type: 'PURCHASE', amount: total, ...);
if (actualPaid > 0) {
  await addTransaction(type: 'PAYMENT', amount: -actualPaid, ...);
}
```

**Cash implication:** Neither path posts purchase cash to `supplier_transactions`. Cash paid at purchase lives **only** in `purchase_invoices.paid_amount`. Standalone supplier payments use `supplier_transactions` PAYMENT via `SupplierPaymentsScreen`.

### 1.4 Could keeping both create accounting inconsistencies?

**Yes — high risk if ever wired:**

1. **Duplicate invoice processing** — two entry points with different stock side effects.
2. **Ledger history divergence** — same net balance, different transaction rows (debt-only vs total+payment pair).
3. **Stock corruption** — PurchaseService does not increment `current_stock`.
4. **Future developer confusion** — two “canonical” purchase handlers.

### 1.5 Recommendation

| Option | Verdict |
|--------|---------|
| Keep both | **Reject** |
| Deprecate + remove | **Recommended** |
| Merge | **Not needed** — active DAO path is complete for UI |

**Action:** **Remove** `PurchaseService` in a pre-Phase-2 cleanup (separate from Cash Ledger). Do **not** merge its ledger logic into PurchasesDao without a product decision — the active path’s **debt-only PURCHASE posting** is internally consistent with `paid_amount` on the header.

**Cash Ledger policy (decision required):**

| Source | Use for cash OUT |
|--------|------------------|
| `purchase_invoices.paid_amount` | **Yes** — only source for at-invoice purchase cash |
| `supplier_transactions` PAYMENT | **Yes** — standalone supplier payments only |
| `supplier_transactions` PURCHASE | **No** — accrual (payable), not cash |

**Guard rule:** Never sum `paid_amount` and a PAYMENT row referencing the same invoice until payment-allocation exists (currently no link).

---

## Section 2 — Session Cash Formula Audit

### 2.1 Current implementation

**Storage:** `pos_sessions` — `opening_cash`, `closing_cash`, `expected_cash_amount`, `cash_difference`  
(`lib/core/database/tables/pos_sessions_table.dart`)

**On close** (`lib/features/pos/providers/pos_provider.dart`, lines 68–70):

```
cashSales     = getSessionSummary(sessionId)['cash']
expectedCash  = opening_cash + cashSales
cashDifference = closingCash - expectedCash
```

**getSessionSummary** (`lib/core/database/daos/sales_dao.dart`, lines 147–155):

```sql
SELECT COUNT(*), SUM(total), SUM(cash_paid), SUM(card_paid)
FROM sales_invoices
WHERE session_id = ? AND IFNULL(invoice_status, 'completed') != 'returned'
```

**UI close dialog** (`lib/features/pos/screens/widgets/session_dialog.dart`):

- Reads `summary['cash_returns']` (line 237) — **key never returned by DAO** → always **0**.
- Computes `_expectedCash = openingCash + cash` (line 241) — **does not subtract** `_cashReturns` even when displayed.
- Shows cash returns row only if `cashReturns > 0` (line 525) — **never visible today**.

**Excluded from current formula:**

| Component | In formula? |
|-----------|-------------|
| Opening cash | Yes |
| Cash sales (`cash_paid`) | Yes |
| Card sales | Display only — not in expected cash |
| Customer debt collections | **No** |
| Customer cash refunds | **No** (and `cash_returns` broken) |
| Expenses | **No** (table does not exist) |
| Other income | **No** (table does not exist) |
| Manual session adjustments | **No** |
| Purchase cash | **No** |
| POS cart returns (negative-qty sale) | Partially — net in `cash_paid` if same invoice |

**Partial return gap:** Invoice stays `partially_returned`; **full original `cash_paid` remains in session sum**; refund in `return_audit_logs` is **not subtracted**.

**Full return gap:** Invoice excluded when `invoice_status = 'returned'` — original cash sale drops from sum automatically (correct for full return path via `ReturnsDao.returnFullSaleInvoice`).

### 2.2 Recommended formula — Financial Center

Define two related metrics:

#### A) Drawer expected cash (session reconciliation)

For session `S` with `[opened_at, closed_at]`:

```
expected_drawer(S) =
    opening_cash(S)
  + SUM(cash_paid FROM sales_invoices
        WHERE session_id = S.id
          AND invoice_status NOT IN ('returned'))
  + SUM(ABS(amount) FROM customer_transactions
        WHERE type = 'PAYMENT'
          AND created_at >= S.opened_at
          AND created_at <= COALESCE(S.closed_at, NOW()))
  - SUM(returned_amount FROM return_audit_logs
        WHERE session_id = S.id
          AND return_type IN ('full','partial','manual')
          AND is_cash_refund = TRUE)          -- policy flag; v1 assume TRUE
  - SUM(paid_amount FROM purchase_invoices
        WHERE purchase_date >= S.opened_at
          AND purchase_date <= COALESCE(S.closed_at, NOW())
          AND paid_amount > 0)                -- optional; purchases not session-scoped today
  - SUM(amount FROM expenses
        WHERE session_id = S.id)              -- future table
  + SUM(amount FROM other_income
        WHERE session_id = S.id)              -- future table
  +/- SUM(amount FROM session_cash_adjustments
           WHERE session_id = S.id)          -- future table
```

```
cash_variance(S) = closing_cash(S) - expected_drawer(S)
```

#### B) Cash Ledger running balance (period / global)

Not tied to drawer; uses event timestamps from Section 5 UNION sources. Session formula is a **subset view** filtered by session + time window.

### 2.3 Policy notes

| Item | Recommendation |
|------|----------------|
| Customer collections | Include in drawer formula via **timestamp overlap** until `session_id` added to `customer_transactions` |
| Return refunds | Use `return_audit_logs.returned_amount` where `session_id` matches; v1 **assume cash refund** |
| Card sales | **Exclude** from drawer expected (not in physical drawer) |
| Credit sales | **Exclude** from drawer until collected (`debt_amount` is not cash) |
| POS cart returns | Count via **net `cash_paid`** on mixed invoices; **do not** also subtract matching audit rows |
| Purchases at invoice | **Exclude from session v1** unless product confirms purchases happen at POS drawer |

**Do not implement** until product approves formula A.

---

## Section 3 — Returns Financial Policy

### 3.1 Return paths in codebase

| Type | Entry point | Code |
|------|-------------|------|
| Full invoice return | Invoice details dialog | `ReturnsDao.returnFullSaleInvoice()` |
| Partial return | Invoice details dialog | `PartialReturnService.processPartialReturn()` |
| Manual return (no invoice) | Customer returns screen | `ReturnsDao.saveCustomerReturn()` |
| Quick return (no invoice) | Customer returns screen | `PosSaleService.processQuickReturn()` |
| POS cart return | POS checkout | `PosSaleService.processSale()` negative qty |
| Supplier return | Supplier returns UI | `ReturnsDao.saveSupplierReturn()` |
| Unused legacy | — | `PosSaleService.processReturn()` **dead** |

### 3.2 Policy matrix

| Return type | Money leaves business? | Customer debt ↓? | Supplier payable ↓? | Inventory value ↑/↓? | Cash Ledger v1? |
|-------------|------------------------|------------------|----------------------|----------------------|-----------------|
| **Full (credit sale)** | No cash movement; debt reversed | **Yes** — `recordReturn(debtAmount)` if `debt_amount > 0` | No | **↑** stock restored | **No** — accrual only (`customer_transactions RETURN`) |
| **Full (cash sale)** | **Yes** — implied cash refund | No | No | **↑** | **Yes** — `return_audit_logs.returned_amount` (line totals); invoice excluded from session cash sum |
| **Full (mixed)** | **Partial cash** | **Yes** — only `debt_amount` reversed | No | **↑** | **Yes** — audit amounts for cash portion; ledger must not also post full invoice `cash_paid` after return |
| **Partial** | **Assumed yes** (no payment method stored) | **No** | No | **↑** | **Yes** — `return_audit_logs` (`return_type = partial`); exclude if same refund captured in POS negative sale |
| **Manual** (`saveCustomerReturn`) | **Unknown** — UI sets `price: 0.0` | No | No | **↑** | **Conditional** — audit `returned_amount` often **0**; unreliable |
| **Quick return** | **Yes** — `refundAmount` param | No | No | **↑** | **Yes** — audit log + legacy `logs.amount` |
| **POS cart return** | **Yes** — via net `cash_paid` / payment dialog | No unless debt sale | No | **↑** | **Yes** — via `sales_invoices.cash_paid` (negative net); **exclude** duplicate audit row if both exist |
| **Supplier return** | No cash in app | No | **No** — no AP credit posted | **↓** stock out | **No** — stock only |

### 3.3 Required policy decisions

1. **Default refund method:** v1 assume all customer refunds are **cash from drawer** unless `customer_transactions RETURN` exists for same return (credit reversal only).
2. **Partial return on credit invoice:** Should proportional debt reversal be posted? **Currently: No** — gap in `PartialReturnService`.
3. **Manual return pricing:** Form allows `price: 0` — financial amount unusable until UI captures refund value.
4. **POS cart vs invoice return:** Pick **one authoritative cash source** per event to avoid double count.

---

## Section 4 — Double Counting Audit

| # | Scenario | Risk | Severity | Prevention strategy |
|---|----------|------|----------|---------------------|
| 1 | Credit sale: `sales_invoices.debt_amount` + `customer_transactions` SALE | Counting invoice total as cash | **High** | Cash Ledger: use **`cash_paid` only** from sales; never `total` or `debt_amount` |
| 2 | Cash sale + customer SALE transaction | Double revenue/cash | **Low** | `recordSale` only fires when `debtAmount > 0` (`pos_sale_service.dart:122`) |
| 3 | Customer collection + later applied to same invoice | Two cash events for one economic payment | **Low** | Collections are separate cash events by design; document as distinct ledger rows |
| 4 | `purchase_invoices.paid_amount` + future PAYMENT row for same invoice | Double cash out | **High** | Single source per invoice: header `paid_amount` OR supplier PAYMENT, not both |
| 5 | `supplier_transactions` PURCHASE + `paid_amount` | Counting payable as cash | **Medium** | Exclude PURCHASE type from cash ledger |
| 6 | `return_audit_logs` + `customer_transactions` RETURN | Cash out + accrual reversal | **Medium** | If RETURN tx exists for return_id, **exclude** audit amount from cash ledger |
| 7 | Full return: session excludes invoice + audit refund subtracted | Double subtraction | **Medium** | For returned invoices: use **either** session exclusion **or** audit refund, not both in same view |
| 8 | Partial return: session keeps full `cash_paid` + audit refund | Under-count drawer OR double subtract if fixed twice | **High** | Adjust session formula to subtract partial audit amounts OR allocate reduced cash_paid |
| 9 | POS cart return + `return_audit_logs` for same items | Double cash out | **High** | Dedup by `invoice_id` + timestamp; prefer POS net `cash_paid` OR audit, not both |
| 10 | `getCashFlow()` card sales + cash ledger `cash_paid` | Card counted as cash drawer | **Low** | Label card separately; drawer views exclude `card_paid` |
| 11 | `getCashFlow()` collections + `sales_invoices.cash_paid` on debt settlement day | Same cash counted with sale | **Low** | Debt sales have `cash_paid=0`; settlement is separate day — OK |
| 12 | Mixed invoice return + full invoice status change | Over-adjustment | **Medium** | Tie-break: `invoice_status` drives session; audit drives ledger detail |
| 13 | `logs.amount` + structured ledger sources | Legacy duplicate | **Low** | Exclude `logs` table from Cash Ledger v1 |
| 14 | Quick return: audit + `logs` RETURN_WITHOUT_INVOICE | Duplicate | **Low** | Use audit only |

---

## Section 5 — Ledger Design Validation (Hybrid Model)

### 5.1 Can Cash Ledger v1 be READ-ONLY DERIVED via UNION?

**Yes — with explicit inclusion/exclusion rules and documented limitations.**

Proposed UNION arms:

```sql
-- IN (+)
SELECT sale_date AS ts, cash_paid AS amount, 'SALE_CASH' AS kind, id AS ref
FROM sales_invoices WHERE cash_paid != 0 AND invoice_status != 'returned'

SELECT created_at, ABS(amount), 'CUSTOMER_PAYMENT', id
FROM customer_transactions WHERE type = 'PAYMENT'

SELECT created_at, amount, 'OTHER_INCOME', id          -- future table
FROM other_income

-- OUT (-)
SELECT purchase_date, paid_amount, 'PURCHASE_CASH', id
FROM purchase_invoices WHERE paid_amount > 0

SELECT created_at, ABS(amount), 'SUPPLIER_PAYMENT', id
FROM supplier_transactions WHERE type = 'PAYMENT'

SELECT created_at, returned_amount, 'RETURN_REFUND', id
FROM return_audit_logs
WHERE returned_amount > 0
  AND NOT EXISTS (
    SELECT 1 FROM customer_transactions ct
    WHERE ct.type = 'RETURN' AND ct.reference_id = return_audit_logs.reference_id
  )   -- simplified; refine join keys in implementation

SELECT expense_date, amount, 'EXPENSE', id              -- future table
FROM expenses
```

### 5.2 Included sources

| Source | Event types |
|--------|-------------|
| `sales_invoices` | `SALE_CASH` (and optionally `SALE_CARD` as non-drawer column) |
| `customer_transactions` | `CUSTOMER_PAYMENT` only |
| `supplier_transactions` | `SUPPLIER_PAYMENT` only |
| `purchase_invoices` | `PURCHASE_CASH` via `paid_amount` |
| `return_audit_logs` | `RETURN_REFUND` (with dedup rules) |
| `expenses` | Future |
| `other_income` | Future |

### 5.3 Excluded sources

| Source | Reason |
|--------|--------|
| `customer_transactions` SALE / RETURN / ADJUSTMENT | Accrual / AR |
| `supplier_transactions` PURCHASE / ADJUSTMENT | Accrual / AP |
| `sales_invoices.total`, `debt_amount`, `card_paid` (drawer view) | Non-cash or separate column |
| `customer_accounts` / `supplier_accounts` caches | Derived snapshots |
| `stock_ledger`, `stock_adjustments` | Inventory, not cash |
| `logs` / `activity_logs` | Audit only; redundant |
| `pos_sessions` opening/closing | Reconciliation snapshots, not flow events |

### 5.4 Known limitations (v1)

1. **No refund payment method** — must assume cash unless RETURN transaction present.
2. **No `session_id` on customer payments** — session-scoped ledger requires timestamp proxy.
3. **Manual returns often zero amount** in audit.
4. **Partial credit returns** do not post debt reversal.
5. **POS cart returns** may not appear in `return_audit_logs`.
6. **Purchase cash** not linked to POS session.
7. **No expenses / other income** until schema v29+.
8. **Performance** — UNION over large ranges needs date indexes (exist on most tables).
9. **Historical gap** — `return_audit_logs` backfilled at v28; older returns may be incomplete.

---

## Section 6 — Implementation Readiness Score

| Dimension | Score (/100) | Rationale |
|-----------|--------------|-----------|
| **Purchase flow** | 52 | Active path clear; dead code risk; cash from `paid_amount` policy defined but not enforced in reports |
| **Session cash logic** | 38 | Wrong/incomplete formula; UI/DAO bug; partial returns break drawer math |
| **Returns logic** | 45 | Four paths; no payment method; partial credit gap; manual zero amounts |
| **Payments logic** | 58 | Channels mapped; collections work; no session linkage |
| **Reporting integration** | 55 | `getCashFlow()` missing purchase cash + refunds; card mixed with cash inflow |
| **Overall** | **48** | Conditional GO only for narrow Cash Ledger v1 |

---

## Risks

| ID | Risk | Impact | Mitigation |
|----|------|--------|------------|
| R1 | Activating `PurchaseService` accidentally | Stock + ledger corruption | Delete file; add CI grep guard |
| R2 | Cash Ledger counts accrual transactions | Inflated/deflated cash | Strict type filter (Section 5.3) |
| R3 | Return double count (audit + invoice + RETURN tx) | False outflows | Dedup matrix (Section 4) |
| R4 | Session reconciliation before formula fix | Cashier distrust | No-GO on reconciliation UI until Section 2 approved |
| R5 | Partial return drawer drift | Persistent variance | Include audit subtract in session formula |
| R6 | `getCashFlow` diverges from Cash Ledger | Conflicting KPIs | Single `FinancialReadRepository` in Phase 2 |
| R7 | Manual returns with zero audit amount | Missing outflows | Fix UI to capture refund amount (later phase) |

---

## Decisions Required (Product / Architecture)

| ID | Decision | Options | Blocks |
|----|----------|---------|--------|
| D1 | Purchase cash source | A) `paid_amount` only B) Post PAYMENT in PurchasesDao | Cash Ledger outflows |
| D2 | Remove PurchaseService? | Yes (recommended) / No | R1 |
| D3 | Default refund = cash? | Yes for v1 / No — capture method | Return ledger rows |
| D4 | Session formula scope | Drawer (Section 2A) vs ledger-only | Reconciliation module |
| D5 | Include purchase cash in session? | Yes / No (recommended No for v1) | Session formula |
| D6 | Partial credit return debt reversal | Implement later / proportional now | AR accuracy |
| D7 | Card in Cash Ledger | Separate column / exclude | Dashboard KPIs |
| D8 | POS cart return authority | `sales_invoices` vs `return_audit_logs` | Dedup rules |

---

## Recommended Cash Ledger Scope (v1)

**In scope (read-only):**

- Derived UNION ledger service (no new tables)
- Date-range filter + pagination
- Event kinds: `SALE_CASH`, `CUSTOMER_PAYMENT`, `SUPPLIER_PAYMENT`, `PURCHASE_CASH`, `RETURN_REFUND`
- Dedup rules per Section 4
- Export via existing `ReportExportService` pattern
- Permission: existing `analytics.financial`

**Out of scope (v1):**

- Session drawer reconciliation fixes (separate P0 task)
- Expenses / other income (needs schema)
- Card settlement / bank reconciliation
- Payment allocation linking
- Writable ledger / adjustments
- Supplier return AP credits

---

## Go / No-Go Recommendation

| Initiative | Verdict | Condition |
|------------|---------|-----------|
| **Cash Ledger v1 (read-only derived)** | **GO** | Implement dedup rules; document limitations; no session reconciliation |
| **Session expected cash fix** | **NO-GO** until D4 approved | Requires implementation task separate from ledger read view |
| **Remove PurchaseService** | **GO** | Pre-implementation cleanup (low risk) |
| **PurchasesDao PAYMENT posting** | **NO-GO** unless D1 chooses ledger mirroring | Prefer Cash Ledger reading `paid_amount` |

---

## Appendix — Evidence Index

| Topic | Primary files |
|-------|---------------|
| Purchase active path | `purchases_dao.dart`, `purchases_repository.dart`, `purchase_form_screen.dart` |
| Purchase dead code | `purchase_service.dart` (zero imports) |
| Session close | `pos_provider.dart:58-100`, `sales_dao.dart:147-155`, `session_dialog.dart:231-242` |
| Full return | `returns_dao.dart:122-288` |
| Partial return | `partial_return_service.dart:94-201` |
| Quick / manual return | `pos_sale_service.dart:276-373`, `customer_returns_screen.dart:162-177` |
| Cash flow report | `advanced_analytics_repository.dart:132-210` |
| Customer ledger | `customer_accounts_dao.dart:49-151` |
| Supplier payments UI | `supplier_payments_screen.dart:54-58` |

---

*End of Phase 1.5 Pre-Implementation Audit — analysis only.*