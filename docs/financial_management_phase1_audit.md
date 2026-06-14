# Financial Management Center — Phase 1 Foundation Audit

| Field | Value |
|-------|-------|
| **Project** | Lez POS |
| **Database** | SQLite via Drift (`lib/core/database/app_database.dart`, schema v28) |
| **Date** | June 8, 2026 |
| **Phase** | 1 — Analysis only (no implementation) |
| **Prior art** | `docs/financial_management_center_blueprint.md` (Phase 0) |

---

## Executive Summary

Lez POS already captures substantial financial data across POS sales, purchases, dual account ledgers (customer/supplier), session cash reconciliation, returns audit, and advanced analytics. **There is no unified accounting layer**: payments are distributed across six storage patterns, expenses and other income do not exist, and cash-flow reporting omits purchase cash paid and return refunds.

**Implementation readiness score: 62 / 100**

| Dimension | Score | Notes |
|-----------|-------|-------|
| Data availability | 75 | Strong sales/session/ledger data; weak payment metadata |
| Schema readiness | 55 | No expense/income/reconciliation tables |
| UI/report reuse | 70 | Rich reports module; no financial hub route |
| Integration clarity | 60 | Known asymmetries (PurchasesDao vs PurchaseService, returns) |
| Risk profile | 55 | Double-count and sync risks if materialized ledger misdesigned |

**Recommendation:** Adopt a **hybrid accounting architecture** — operational tables remain source of truth; a **derived cash ledger view** plus **native supplemental tables** for expenses, other income, and reconciliation snapshots. Phase 2 should begin with **Cash Ledger (read-only)** and **pre-work fixes** to session summary and purchase payment posting.

---

## Step 1 — Existing Financial Data Mapping

### 1.1 Sales & Invoices

| Domain | Source Table(s) | Repository / Service | Current Usage | Financial Relevance |
|--------|-----------------|----------------------|---------------|---------------------|
| Sale invoices | `sales_invoices`, `sale_items` | `SalesDao`, `PosSaleService`, `PosRepository` | POS checkout, invoice history | **Primary revenue document**; `total`, `cash_paid`, `card_paid`, `debt_amount`, `change_amount` |
| Payment split | `sales_invoices` | `payment_dialog.dart`, `PaymentInfo` | CASH / CARD / MIXED / DEBT | Cash drawer vs card vs receivable |
| Line COGS | `sale_items.unit_cost` | `SalesDao.getDailyTotals`, `AdvancedAnalyticsRepository` | Profit KPIs | Gross margin calculation |
| Invoice lifecycle | `sales_invoices.invoice_status` | `ReturnsDao`, `PosSaleService` | completed / partially_returned / returned | Revenue exclusion in reports |

### 1.2 Purchases

| Domain | Source Table(s) | Repository / Service | Current Usage | Financial Relevance |
|--------|-----------------|----------------------|---------------|---------------------|
| Purchase invoices | `purchase_invoices`, `purchase_items` | `PurchasesDao`, `PurchasesRepository` | Purchase entry UI | `total`, `paid_amount`, `debt_amount` |
| Supplier payable | `supplier_transactions` (PURCHASE) | `PurchasesDao.savePurchaseInvoice()` | Debt portion only | Payable accrual |
| Purchase cash | `purchase_invoices.paid_amount` | Header field only | **Not in supplier PAYMENT ledger** | Cash outflow (missing from `getCashFlow`) |
| Unused path | Same tables | `PurchaseService` (not wired to UI) | Would post PURCHASE(total)+PAYMENT(-paid) | **Ledger divergence risk** |

### 1.3 Returns

| Domain | Source Table(s) | Repository / Service | Current Usage | Financial Relevance |
|--------|-----------------|----------------------|---------------|---------------------|
| Customer returns | `customer_returns`, `customer_return_items` | `ReturnsDao` | Full return flow | Stock restoration |
| Partial returns | `sale_item_returns`, `return_audit_logs` | `PartialReturnService`, `ReturnAuditLogsDao` | Partial return UI | `returned_amount` for analytics |
| Debt reversal | `customer_transactions` (RETURN) | `ReturnsDao.returnFullSaleInvoice()` | Credit sales only | Payable to customer (accrual) |
| Cash refund | `return_audit_logs.returned_amount` | Audit only | **Not posted to cash ledger** | Implied cash out |
| Supplier returns | `supplier_returns` | `ReturnsDao` | UI placeholder | Stock only; no payable credit |

### 1.4 Customer Balances & Debts

| Domain | Source Table(s) | Repository / Service | Current Usage | Financial Relevance |
|--------|-----------------|----------------------|---------------|---------------------|
| Cached balance | `customer_accounts.current_balance` | `CustomerAccountsDao` | Customer profile, POS | Receivable snapshot |
| Immutable ledger | `customer_transactions` | `CustomerAccountsDao` | SALE/PAYMENT/RETURN/ADJUSTMENT | **Authoritative balance history** |
| Collections | `customer_transactions` PAYMENT | `CustomerAccountService`, `customer_payments_screen`, `settleDebt()` | Debt collection | Cash inflow |
| Credit limit | `customers.credit_limit` | `CustomerAccountsDao.wouldExceedCreditLimit()` | POS credit sales | Risk control (non-cash) |

### 1.5 Supplier Balances & Debts

| Domain | Source Table(s) | Repository / Service | Current Usage | Financial Relevance |
|--------|-----------------|----------------------|---------------|---------------------|
| Cached balance | `supplier_accounts.current_balance` | `SupplierAccountsDao` | Supplier profile | Payable snapshot |
| Immutable ledger | `supplier_transactions` | `SupplierAccountsDao` | PURCHASE/PAYMENT/ADJUSTMENT | **Authoritative payable history** |
| Payments | `supplier_transactions` PAYMENT | `SupplierAccountService`, `supplier_payments_screen` | Standalone payments | Cash outflow |

### 1.6 Payments (Distributed — No Unified Table)

| Channel | Storage | Entry Point |
|---------|---------|-------------|
| POS cash | `sales_invoices.cash_paid` | Checkout |
| POS card | `sales_invoices.card_paid` | Checkout |
| POS credit | `sales_invoices.debt_amount` + customer SALE | Checkout |
| Customer collection | `customer_transactions` PAYMENT | Payments screen, POS settle |
| Supplier payment | `supplier_transactions` PAYMENT | Supplier payments screen |
| Purchase at invoice | `purchase_invoices.paid_amount` | Purchase form |

### 1.7 Cash Sessions

| Domain | Source Table(s) | Repository / Service | Current Usage | Financial Relevance |
|--------|-----------------|----------------------|---------------|---------------------|
| Session open | `pos_sessions.opening_cash` | `PosSessionNotifier`, `SalesDao` | Shift start | Opening float |
| Session close | `pos_sessions.closing_cash`, `expected_cash_amount`, `cash_difference` | `PosSessionNotifier.closeSession()` | Shift end | Drawer reconciliation |
| Session sales link | `sales_invoices.session_id` | `PosSaleService` | Per-session cash sum | Expected cash basis |
| **Gap** | — | `session_dialog` reads `cash_returns` | Not computed by `SalesDao.getSessionSummary()` | UI/DAO mismatch |

**Current expected cash formula:** `opening_cash + SUM(cash_paid)` (non-returned invoices). Does not include collections, refunds, or expenses.

### 1.8 Expenses

| Status | Detail |
|--------|--------|
| **Does not exist** | No table, no CRUD, no service |
| Placeholder | `AdvancedAnalyticsRepository.getCashFlow()` hardcodes `expenses = 0.0` |
| UI hint | CashFlowTab shows "مصروفات (مستقبلي)" |

### 1.9 Adjustments

| Domain | Source Table(s) | Repository / Service | Usage |
|--------|-----------------|----------------------|-------|
| Customer balance | `customer_transactions` ADJUSTMENT | `CustomerAccountsDao.adjustBalance()` | Manual correction |
| Supplier balance | `supplier_transactions` ADJUSTMENT | `SupplierAccountsDao` | Manual correction |
| Stock adjustment | `stock_adjustments` | `StockDao` | Inventory qty/cost; **not cash** unless future link |

### 1.10 Inventory Valuation

| Domain | Source Table(s) | Repository / Service | Usage |
|--------|-----------------|----------------------|-------|
| Product valuation | `products.current_stock`, `products.cost_price` | `StockDao.getInventoryValueReport()` | Reports inventory tab |
| Analytics valuation | Same | `AdvancedAnalyticsRepository` (executive dashboard) | KPI: inventory value |
| Stock ledger | `stock_ledger` | All stock mutations | Audit trail; unit cost for COGS |

### 1.11 Reports & Analytics

| Report | Repository | Financial outputs |
|--------|------------|-------------------|
| Daily/monthly sales | `ReportsRepository` / `SalesDao` | Revenue, profit, cash/card split |
| Purchases by supplier | `ReportsRepository` | Purchase totals |
| Inventory value | `ReportsRepository` / `StockDao` | Stock at cost |
| Customer debts | `CustomerAccountsDao` via providers | Outstanding receivables |
| Supplier debts | `SupplierAccountsDao` | Outstanding payables |
| Cash flow | `AdvancedAnalyticsRepository.getCashFlow()` | In/out/net (incomplete) |
| Profit analysis | `AdvancedAnalyticsRepository.getProfitAnalysis()` | Gross profit only |
| Return impact | `AdvancedAnalyticsRepository.getReturnImpact()` | Return amounts |
| Executive dashboard | `AdvancedAnalyticsRepository` | Revenue, profit, net cash flow, return rate |

### 1.12 Dashboard KPIs

| KPI | Source | Location |
|-----|--------|----------|
| Today sales | `SalesDao.getDailyTotals()` | `dashboard_screen.dart` |
| Invoice count | Same | Dashboard |
| Today profit | Same (revenue - line cost) | Dashboard |
| Executive KPIs | `AdvancedAnalyticsRepository` | `executive_dashboard_panel.dart` |

### 1.13 Activity & Audit Logs

| System | Table | Financial fields | Usage |
|--------|-------|------------------|-------|
| Modern | `activity_logs` | metadata JSON, session_id, user_id | Structured ops audit |
| Legacy | `logs` | `amount`, `action_type`, `user_id` | SALE_CONFIRMED, CUSTOMER_PAYMENT, SUPPLIER_PAYMENT |
| Return audit | `return_audit_logs` | `returned_amount`, session, cashier | Immutable return financial audit |

---
## Step 2 — Existing Database Audit

**Schema reference:** `lib/core/database/app_database.dart` (v28), table definitions under `lib/core/database/tables/`.

### A) Existing Financial Tables

| Table | Primary financial columns | Role |
|-------|---------------------------|------|
| `sales_invoices` | total, cash_paid, card_paid, debt_amount, change_amount, session_id, invoice_status | Revenue + payment split |
| `sale_items` | quantity, unit_price, unit_cost, line_total | Revenue detail + COGS |
| `purchase_invoices` | total, paid_amount, debt_amount, supplier_id | Purchase document |
| `purchase_items` | quantity, unit_cost, line_total | Purchase detail |
| `customer_accounts` | current_balance | Receivable cache |
| `customer_transactions` | amount, type, reference_id, balance_after | Receivable ledger |
| `supplier_accounts` | current_balance | Payable cache |
| `supplier_transactions` | amount, type, reference_id, balance_after | Payable ledger |
| `pos_sessions` | opening_cash, closing_cash, expected_cash_amount, cash_difference | Shift cash control |
| `return_audit_logs` | returned_amount, session_id | Return financial audit |
| `customer_returns` / `customer_return_items` | return totals | Return documents |
| `sale_item_returns` | returned_qty, returned_amount | Partial return lines |
| `logs` | amount, action_type | Legacy financial audit |
| `activity_logs` | metadata (JSON) | Modern audit (amount optional) |

### B) Tables That Already Contain Accounting Data

These tables hold double-entry–like or ledger semantics without a general ledger:

1. **`customer_transactions`** — Signed amounts by type (SALE increases balance, PAYMENT decreases, RETURN/ADJUSTMENT vary). Immutable append-only pattern.
2. **`supplier_transactions`** — Same pattern for payables.
3. **`pos_sessions`** — Cash reconciliation snapshot at shift close.
4. **`return_audit_logs`** — Financial amount tied to return events.
5. **`sales_invoices` / `purchase_invoices`** — Document-level payment allocation (cash/card/debt/paid).

### C) Tables That Can Become Accounting Sources

| Table | Potential ledger events |
|-------|-------------------------|
| `sales_invoices` | CASH_IN, CARD_IN, AR_SALE |
| `customer_transactions` | AR_PAYMENT, AR_ADJUSTMENT, AR_RETURN |
| `supplier_transactions` | AP_PAYMENT, AP_ADJUSTMENT |
| `purchase_invoices` | AP_PURCHASE, CASH_OUT (paid portion) |
| `return_audit_logs` | CASH_OUT (refund), REVENUE_REVERSAL |
| `pos_sessions` | OPENING_FLOAT, CLOSING_COUNT |
| `stock_adjustments` | Future: inventory write-off expense (not cash today) |
| `logs` / `activity_logs` | Historical backfill for migration |

### D) Missing Accounting Structures

| Missing entity | Purpose | Priority |
|----------------|---------|----------|
| `cash_ledger_entries` (or materialized view) | Unified cash in/out timeline | High |
| `expenses` | Operating expenses | High |
| `other_income` | Non-POS income | Medium |
| `financial_accounts` / chart of accounts (lite) | Category taxonomy | Medium |
| `reconciliation_records` | Formal session vs ledger tie-out | Medium |
| `payment_allocations` | Link payments to invoices | Low (future) |
| `journal_entries` (full GL) | Double-entry | **Out of scope** (Accounting Lite) |

**Existing indexes:** Financial queries rely on date filters on invoice/transaction tables; no dedicated indexes on `session_id` for ledger aggregation (performance note for Phase 2).

---

## Step 3 — Reusable Components Audit

### Repositories

| Component | Path | Verdict | Notes |
|-----------|------|---------|-------|
| `SalesDao` | `lib/core/database/daos/sales_dao.dart` | **Reusable** | Daily totals, session summary, invoice queries |
| `PurchasesDao` | `lib/core/database/daos/purchases_dao.dart` | **Partially reusable** | Needs payment ledger alignment |
| `CustomerAccountsDao` | `lib/core/database/daos/customer_accounts_dao.dart` | **Reusable** | Balance, transactions, payments |
| `SupplierAccountsDao` | `lib/core/database/daos/supplier_accounts_dao.dart` | **Reusable** | Same for suppliers |
| `ReturnsDao` | `lib/core/database/daos/returns_dao.dart` | **Partially reusable** | Full returns OK; partial lacks cash reversal |
| `AdvancedAnalyticsRepository` | `lib/features/reports/data/advanced_analytics_repository.dart` | **Partially reusable** | Extend getCashFlow, getProfitAnalysis |
| `ReportsRepository` | `lib/features/reports/data/reports_repository.dart` | **Reusable** | Sales/purchase/inventory reports |
| `ReturnAuditLogsDao` | `lib/core/database/daos/return_audit_logs_dao.dart` | **Reusable** | Refund amounts for ledger |
| `PurchaseService` | `lib/features/purchases/services/purchase_service.dart` | **Not reusable** | Dead code; divergent ledger logic |

### Services

| Component | Path | Verdict | Notes |
|-----------|------|---------|-------|
| `PosSaleService` | `lib/features/pos/services/pos_sale_service.dart` | **Reusable** | Sale + session link |
| `PosSessionNotifier` | `lib/features/pos/providers/pos_session_notifier.dart` | **Partially reusable** | Fix expected cash formula |
| `CustomerAccountService` | `lib/features/customers/services/customer_account_service.dart` | **Reusable** | Payment posting |
| `SupplierAccountService` | `lib/features/suppliers/services/supplier_account_service.dart` | **Reusable** | Payment posting |
| `DailyClosingService` | `lib/features/reports/services/daily_closing_service.dart` | **Partially reusable** | Daily close; not full reconciliation |
| `ReportExportService` | `lib/features/reports/services/report_export_service.dart` | **Reusable** | PDF/Excel export |
| `PartialReturnService` | `lib/features/returns/services/partial_return_service.dart` | **Partially reusable** | Audit only today |

### Providers

| Component | Path | Verdict | Notes |
|-----------|------|---------|-------|
| `reportDailySalesProvider` | reports providers | **Reusable** | Dashboard KPIs |
| `cashFlowProvider` / analytics providers | `lib/features/reports/providers/` | **Partially reusable** | Wire to new ledger |
| `customerDebtsProvider`, supplier equivalents | customers/suppliers | **Reusable** | AR/AP widgets |
| Permission: `analytics.financial` | permissions config | **Reusable** | Gate Financial Center |

### Dashboards, Charts, Widgets

| Component | Path | Verdict | Notes |
|-----------|------|---------|-------|
| `AnalyticsModuleScaffold` | `lib/features/reports/widgets/` | **Reusable** | Shell for financial hub |
| `ReportFilterBar` | reports widgets | **Reusable** | Date range, export |
| `ExecutiveDashboardPanel` | reports | **Partially reusable** | KPI cards pattern |
| Cash flow / profit tabs | `lib/features/reports/screens/` | **Partially reusable** | Placeholder expenses |
| Chart widgets (fl_chart) | reports | **Reusable** | Time series, pie |
| `dashboard_screen.dart` | `lib/features/dashboard/` | **Partially reusable** | Add financial summary card |

### Filters & Export

| Component | Verdict | Notes |
|-----------|---------|-------|
| Date range filters (reports) | **Reusable** | Standard pattern |
| `ReportExportService` | **Reusable** | Extend for P&L export |
| Permission-gated export | **Reusable** | Existing RBAC |

### Not Reusable (without refactor)

- Monolithic `PurchaseService` vs `PurchasesDao` split
- Session expected cash as currently implemented
- Any UI assuming single payment table

---
## Step 4 — Accounting Architecture Proposal (Accounting Lite)

**Design principle:** Hybrid model — **operational tables remain source of truth**; Financial Management Center consumes **derived views** plus **native supplemental tables** for gaps (expenses, other income, reconciliation notes).

```
┌─────────────────────────────────────────────────────────────────┐
│                    Financial Management Center                   │
├─────────────┬─────────────┬──────────────┬──────────────────────┤
│ Cash Ledger │  Expenses   │ Other Income │  P&L / Dashboard     │
└──────┬──────┴──────┬──────┴──────┬───────┴──────────┬─────────┘
       │             │             │                  │
       ▼             ▼             ▼                  ▼
┌──────────────┐ ┌─────────┐ ┌────────────┐ ┌───────────────────┐
│ Derived view │ │ expenses│ │other_income│ │ Aggregation layer │
│ (UNION cash  │ │ (new)   │ │ (new)      │ │ (repos/services)  │
│  events)     │ └─────────┘ └────────────┘ └───────────────────┘
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│ sales_invoices │ customer_tx PAYMENT │ supplier_tx PAYMENT       │
│ purchase_invoices.paid │ return_audit_logs │ pos_sessions       │
└──────────────────────────────────────────────────────────────────┘
```

### Module 1 — Cash Ledger

| Aspect | Detail |
|--------|--------|
| **Responsibilities** | Chronological cash in/out; filter by date, session, user; running balance optional |
| **Required entities** | Derived `CashLedgerEntry` (virtual); optional materialized cache table later |
| **Dependencies** | SalesDao, CustomerAccountsDao, SupplierAccountsDao, PurchasesDao, ReturnAuditLogsDao |
| **Data sources** | POS cash_paid; customer PAYMENT; supplier PAYMENT; purchase paid_amount; return_audit returned_amount; session opening (info) |

**Event mapping (proposed):**

| Event type | Source | Sign |
|------------|--------|------|
| SALE_CASH | sales_invoices.cash_paid | + |
| CUSTOMER_PAYMENT | customer_transactions PAYMENT | + |
| SUPPLIER_PAYMENT | supplier_transactions PAYMENT | - |
| PURCHASE_CASH | purchase_invoices.paid_amount | - |
| RETURN_REFUND | return_audit_logs.returned_amount | - |
| EXPENSE | expenses.amount | - |
| OTHER_INCOME | other_income.amount | + |

Card payments tracked separately (non-cash ledger) unless extended module added.

### Module 2 — Expense Management

| Aspect | Detail |
|--------|--------|
| **Responsibilities** | CRUD operating expenses; categories; date; optional session link; attachment note |
| **Required entities** | `expenses` table, `ExpenseCategory` enum or lookup |
| **Dependencies** | New DAO; Cash Ledger; permissions |
| **Data sources** | User-entered only (no operational backfill) |

### Module 3 — Other Income

| Aspect | Detail |
|--------|--------|
| **Responsibilities** | Non-POS cash in (rent, services, misc) |
| **Required entities** | `other_income` table |
| **Dependencies** | Cash Ledger; P&L |
| **Data sources** | User-entered |

### Module 4 — Financial Dashboard

| Aspect | Detail |
|--------|--------|
| **Responsibilities** | KPI cards: cash in/out/net, expenses, gross profit, AR/AP totals, session variance |
| **Required entities** | Read models from ledger + existing analytics |
| **Dependencies** | Cash Ledger service, AdvancedAnalyticsRepository (extended), dashboard providers |
| **Data sources** | All modules + customer_accounts + supplier_accounts |

### Module 5 — Profit & Loss (Lite)

| Aspect | Detail |
|--------|--------|
| **Responsibilities** | Period P&L: revenue, COGS, gross profit, expenses, other income, net profit (cash-basis lite) |
| **Required entities** | P&L aggregation (no journal) |
| **Dependencies** | SalesDao (revenue/COGS), expenses, other_income, return impact |
| **Data sources** | sales_invoices + sale_items; expenses; other_income; return_audit_logs (adjust revenue) |

**Formula (proposed):**
- Revenue = SUM(sales total) - return adjustments
- COGS = SUM(sale_items qty * unit_cost) - return COGS
- Gross Profit = Revenue - COGS
- Net Profit (lite) = Gross Profit - expenses + other_income

Accrual AR/AP excluded from P&L lite unless extended.

### Module 6 — Cash Reconciliation

| Aspect | Detail |
|--------|--------|
| **Responsibilities** | Compare session expected vs counted; explain variance; tie to ledger events in session window |
| **Required entities** | Extend pos_sessions or add `session_reconciliation_notes` |
| **Dependencies** | PosSessionNotifier fix, Cash Ledger filtered by session_id |
| **Data sources** | pos_sessions; sales_invoices.session_id; customer payments with session; returns in session |

**Revised expected cash (proposed):**
```
expected = opening_cash
         + SUM(sale cash_paid in session)
         + SUM(customer PAYMENT in session)
         - SUM(return refunds in session)
         - SUM(purchase cash in session)   [if linked]
         - SUM(expenses in session)
```

---

## Step 5 — Integration Risk Assessment

### Duplicate Data Risks

| Risk | Description | Mitigation |
|------|-------------|------------|
| **Dual purchase paths** | PurchasesDao vs unused PurchaseService post different ledger entries | Deprecate PurchaseService; single write path in Phase 2 pre-work |
| **Balance cache vs ledger** | customer_accounts.current_balance vs sum(transactions) | Continue ledger-as-truth; reconcile on read or periodic audit job |
| **Materialized ledger** | Copying cash events to new table duplicates sources | Prefer derived view first; materialize only if performance requires |
| **Invoice paid vs transaction** | purchase paid_amount not mirrored in supplier_transactions | Align PurchasesDao to post PAYMENT for paid portion OR document as ledger exception |

### Synchronization Risks

| Risk | Description | Mitigation |
|------|-------------|------------|
| **Partial returns** | Stock/audit updated; no automatic cash reversal | Map return_audit_logs to ledger; flag cash vs credit returns |
| **Session close timing** | Payments after close not in session | Timestamp all events; session filter by closed_at window |
| **Multi-user sessions** | Shared session_id across cashiers | Document ownership; filter by user_id where available |
| **Card vs cash** | Mixed payments split across columns | Ledger reads both columns; reconciliation module cash-only |

### Performance Risks

| Risk | Description | Mitigation |
|------|-------------|------------|
| **UNION ledger query** | Large date ranges scan multiple tables | Index session_id, created_at; paginate; optional summary table |
| **P&L aggregation** | Full sale_items scan | Reuse SalesDao.getDailyTotals patterns; cache daily rollups |
| **Dashboard load** | Many parallel queries | Single FinancialReadRepository with batched SQL |

### Migration Risks

| Risk | Description | Mitigation |
|------|-------------|------------|
| **Historical expenses** | No backfill source | Start expenses from go-live date; document gap |
| **Legacy logs** | logs.amount inconsistent with new model | Optional one-time import script (Phase 3+) |
| **Schema version** | v28 → v29+ for new tables | Standard Drift migration; no retroactive invoice changes |

### Reporting Risks

| Risk | Description | Mitigation |
|------|-------------|------------|
| **Cash flow vs P&L mismatch** | Cash-basis ledger vs accrual sales | Label reports clearly; Accounting Lite = cash-basis default |
| **Return double-count** | Revenue reduced in P&L and cash out in ledger | Define net revenue formula with return_audit dedup |
| **Executive dashboard drift** | Existing KPIs vs new Financial Center | Single aggregation service; deprecate duplicate formulas |

---

## Step 6 — Delivery Summary

### Findings (Consolidated)

1. **Financial data exists but is fragmented** across six payment storage patterns with no unified cash timeline.
2. **Strong foundation** in customer/supplier immutable ledgers and POS session model.
3. **Critical gaps:** no expenses, no other income, incomplete cash-flow SQL, session expected cash ignores collections/refunds.
4. **Known bugs:** `getSessionSummary()` missing `cash_returns`; PurchasesDao does not post purchase cash to supplier ledger.
5. **Rich reports UI** can host Financial Center with minimal shell work.
6. **Hybrid architecture** recommended over full GL — derived ledger + supplemental tables.

### Recommended Phase 2 Scope

| Priority | Deliverable |
|----------|-------------|
| P0 | Fix session summary (`cash_returns`, expected cash formula design doc + implementation) |
| P0 | Align PurchasesDao payment posting (or document exception in ledger mapper) |
| P1 | **Cash Ledger (read-only UI)** — derived view, no new tables |
| P1 | **Financial Dashboard** — KPI cards wired to ledger + existing analytics |
| P2 | Schema: `expenses` + CRUD + permission |
| P2 | Schema: `other_income` + CRUD |
| P3 | **P&L Lite** screen + export |
| P3 | **Cash Reconciliation** enhancements on session close dialog |

**Out of Phase 2:** Full double-entry GL, payment allocations, supplier return payables, card settlement reconciliation.

### Estimated Complexity per Module

| Module | Complexity | Effort (relative) | Rationale |
|--------|------------|-------------------|-----------|
| Cash Ledger (derived) | **Medium** | 3–5 days | Multi-table UNION, testing edge cases |
| Expense Management | **Low–Medium** | 2–3 days | New table + standard CRUD |
| Other Income | **Low** | 1–2 days | Mirror expenses |
| Financial Dashboard | **Medium** | 3–4 days | Wire providers, reuse charts |
| Profit & Loss Lite | **Medium–High** | 4–6 days | COGS/return logic, export |
| Cash Reconciliation | **High** | 5–7 days | Session formula, UX, variance explanations |

**Total Phase 2–3 (core):** ~18–27 dev-days (single developer, excluding QA).

### Dependencies Before Implementation

| Dependency | Owner | Blocking |
|------------|-------|----------|
| Product decision: cash-basis vs accrual labels | Product | P&L reporting |
| Purchase paid_amount ledger policy | Architecture | Cash Ledger accuracy |
| Session expected cash formula sign-off | Product + POS | Reconciliation |
| Permission key for Financial Center (`analytics.financial` exists) | RBAC | UI access |
| Drift migration pipeline for v29 | Dev | Expenses/income tables |
| Deprecate/remove `PurchaseService` | Dev | Duplicate data risk |
| Partial return cash vs credit classification | Returns module | Refund ledger events |

### Implementation Readiness Score Breakdown

| Category | Weight | Score | Weighted |
|----------|--------|-------|----------|
| Operational data coverage | 25% | 78 | 19.5 |
| Schema extensibility | 20% | 55 | 11.0 |
| Code reuse (reports/UI) | 20% | 72 | 14.4 |
| Integration risk (inverse) | 20% | 50 | 10.0 |
| Team clarity (post-audit) | 15% | 80 | 12.0 |
| **Total** | 100% | — | **62.9 ≈ 62** |

**Verdict:** Proceed to Phase 2 with **read-only Cash Ledger** and **pre-work fixes** before introducing writable expense tables.

---

## Appendix A — Key File Index

| Area | Primary files |
|------|---------------|
| Schema | `lib/core/database/app_database.dart`, `lib/core/database/tables/*.dart` |
| Sales / sessions | `lib/core/database/daos/sales_dao.dart`, `lib/features/pos/services/pos_sale_service.dart`, `lib/features/pos/providers/pos_session_notifier.dart` |
| Purchases | `lib/core/database/daos/purchases_dao.dart` |
| AR/AP | `lib/core/database/daos/customer_accounts_dao.dart`, `lib/core/database/daos/supplier_accounts_dao.dart` |
| Returns | `lib/core/database/daos/returns_dao.dart`, `lib/core/database/daos/return_audit_logs_dao.dart` |
| Analytics | `lib/features/reports/data/advanced_analytics_repository.dart` |
| Reports UI | `lib/features/reports/` |
| Dashboard | `lib/features/dashboard/dashboard_screen.dart` |
| Phase 0 blueprint | `docs/financial_management_center_blueprint.md` |

---

*End of Phase 1 Foundation Audit — analysis only, no code or schema changes.*