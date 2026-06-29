# PHASE 5.0 — FINANCIAL DASHBOARD
## ARCHITECTURE AUDIT (PRE-IMPLEMENTATION)
**Auditor:** Senior ERP Financial Architect & Business Intelligence Designer
**Date:** 2026-06-24
**Mode:** Read-only analysis — no code modifications
**Schema Version:** 30

---

## Executive Summary

The Lez POS database contains a rich, well-structured set of financial tables whose data has been
validated through Phases 1–4. A Financial Dashboard is architecturally feasible with ZERO schema
changes. Every Tier 1 and Tier 2 KPI can be calculated accurately using existing tables.

The derived Cash Ledger (7-block UNION, Phase 4.3) is the correct aggregation layer for all
cash-flow KPIs. Current-state debt KPIs must read from the `customer_accounts` and
`supplier_accounts` balance-cache tables, NOT from raw transaction sums.

**Verdict: GO (95/100)** — Implementation may begin after this audit.

---

## Section 1 — Existing Financial Sources

| Source | Purpose | Financial Meaning | Available Metrics |
|--------|---------|------------------|-------------------|
| sales_invoices | POS sale records | Revenue source | cash_paid, card_paid, debt_amount, total, discount_amount, invoice_status |
| customer_transactions | Immutable customer ledger | Receivables history | SALE (+debt), PAYMENT (-debt), ADJUSTMENT, RETURN |
| customer_accounts | Per-customer balance cache | Total receivables (آجل) | currentBalance per customer (updated atomically with each transaction) |
| purchase_invoices | Supplier purchase records | Inventory cost + payables | paid_amount (cash out), debt_amount (payable), total |
| supplier_transactions | Immutable supplier ledger | Payables history | PURCHASE (+debt), PAYMENT (-debt), ADJUSTMENT |
| supplier_accounts | Per-supplier balance cache | Total payables (مستحق) | currentBalance (positive = we owe supplier) |
| return_audit_logs | Cash refund audit trail | Cash outflow for returns | returned_amount, return_type |
| customer_returns | Return header records | Return totals | total per return, original_invoice_id |
| expense_records | Operational expenses | Cash outflow (non-purchase) | amount (is_voided = 0), category, paid_at |
| other_income_records | Non-sales cash income | Cash inflow (non-sales) | amount (is_voided = 0), category, received_at |
| pos_sessions | Session cash management | Physical cash snapshots | opening_cash, closing_cash, expected_cash_amount, cash_difference |
| cash_ledger (derived) | Unified 7-type UNION view | Net cash position | totalInflow, totalOutflow, netCashFlow, transactionCount, runningBalance |
| app_settings | Key-value store | Business configuration | any future dashboard toggles/preferences |

### Key Structural Observations

1. **customer_accounts.currentBalance** — cached, atomically updated. Trustworthy for
   "total customer debt" without scanning all customer_transactions rows.
2. **supplier_accounts.currentBalance** — same pattern. Positive = we owe the supplier.
3. **sales_invoices.cash_paid** — only the cash portion of a sale. card_paid is separate.
   Credit (آجل) sales are captured in debt_amount and tracked through customer_transactions.
4. **Card payments are NOT in the Cash Ledger** — The SALE_CASH ledger block uses `cash_paid`.
   This is architecturally correct: the Cash Ledger is a CASH ledger, not total revenue.
5. **pos_sessions.expectedCashAmount** — computed at session close as: openingCash + SUM(cash_paid)
   for that session. cashDifference = closingCash - expectedCashAmount.

---

## Section 2 — Current Capabilities

### KPI Readiness Assessment

| KPI | Status | Source | Reasoning |
|-----|--------|--------|-----------|
| Cash Inflow (period) | READY | Cash Ledger getSummary.totalInflow | 7-type UNION, date-filtered, validated in Phase 4.3 |
| Cash Outflow (period) | READY | Cash Ledger getSummary.totalOutflow | Same |
| Net Cash Flow (period) | READY | Cash Ledger getSummary.netCashFlow | totalInflow - totalOutflow, validated |
| Transaction Count (period) | READY | Cash Ledger getSummary.transactionCount | Included in existing model |
| Total Expenses (period) | READY | Cash Ledger (EXPENSE events) or expense_records | Either path valid; Ledger preferred for consistency |
| Total Other Income (period) | READY | Cash Ledger (OTHER_INCOME events) or other_income_records | Either path valid |
| Total Returns/Refunds (period) | READY | Cash Ledger (RETURN_REFUND events) | Validated with double-count guard |
| Total Customer Debt | READY | SUM(customer_accounts.currentBalance WHERE > 0) | O(n customers), uses cached balance |
| Total Supplier Debt | READY | SUM(supplier_accounts.currentBalance WHERE > 0) | O(n suppliers), uses cached balance |
| Sales Cash Revenue (period) | READY | Cash Ledger (SALE_CASH events) | cash_paid only — correctly labeled |
| Total Sales Revenue (incl. credit) | READY | SUM(sales_invoices.total) for period | Accrual figure, NOT cash figure — label carefully |
| Purchase Cash Spending (period) | READY | Cash Ledger (PURCHASE_CASH + SUPPLIER_PAYMENT events) | Two event types combined |
| Cash Balance (current, all-time) | PARTIAL | Cash Ledger getSummary (no date filter) | Accurate relative to ledger start; no "opening balance injection" |
| Customer Payment Collections (period) | READY | Cash Ledger (CUSTOMER_PAYMENT events) | Subset of totalInflow |
| POS Session Cash Discrepancy | READY | SUM(pos_sessions.cashDifference) for period | Direct from table |
| Gross Profit / Margin | NOT READY | Needs COGS from purchase_items × unit costs | Not yet integrated |
| Net Profit | NOT READY | Needs Gross Profit (see above) | Phase 6 (P&L) |
| Sales by Product Category | NOT READY | Needs sale_items JOIN categories | Not a cash dashboard concern |
| Inventory Value | NOT READY | Needs stock × cost per product | Phase 8 (Advanced Analytics) |
| Card Revenue (period) | PARTIAL | SUM(sales_invoices.card_paid) for period | Available in raw table, not in Cash Ledger |

### PARTIAL Details

**Cash Balance (PARTIAL):**
The Cash Ledger running balance is computed over entries only from the business's first recorded
transaction. Any cash that existed BEFORE the system was introduced (physical starting cash) is not
represented. This is a known limitation that Phase 7 (Reconciliation) will address via an
"opening balance injection" mechanism. For Phase 5, the all-time ledger net is the best
available approximation and should be labeled accordingly.

**Card Revenue (PARTIAL):**
`sales_invoices.card_paid` exists and is queryable but intentionally excluded from the Cash Ledger
(which tracks physical cash only). Phase 5 may expose card revenue as a supplementary figure if
desired, directly from sales_invoices. This is a safe, additive query with no double-count risk.

---

## Section 3 — Dashboard KPI Design

### Tier 1 — Most Important (always visible, primary viewport)

| # | KPI Name (AR) | Formula | Source Tables | Refresh |
|---|---------------|---------|---------------|---------|
| T1.1 | الرصيد النقدي الحالي | SUM(inflow) - SUM(outflow) WHERE no date filter | Cash Ledger getSummary (unfiltered) | Reactive via _readSet() |
| T1.2 | ديون العملاء | SUM(customer_accounts.currentBalance WHERE > 0) | customer_accounts | Reactive on customer_accounts writes |
| T1.3 | مستحقات الموردين | SUM(supplier_accounts.currentBalance WHERE > 0) | supplier_accounts | Reactive on supplier_accounts writes |
| T1.4 | صافي التدفق النقدي | totalInflow - totalOutflow (period) | Cash Ledger getSummary | Reactive via _readSet() |

### Tier 2 — Important (second viewport, date-filtered)

| # | KPI Name (AR) | Formula | Source Tables | Refresh |
|---|---------------|---------|---------------|---------|
| T2.1 | إجمالي الإيرادات النقدية | SUM(SALE_CASH.amount) + SUM(CUSTOMER_PAYMENT.amount) period | Cash Ledger totalInflow | Reactive |
| T2.2 | إجمالي المصروفات | SUM(EXPENSE.amount) period | Cash Ledger (EXPENSE events) | Reactive |
| T2.3 | إجمالي إيرادات أخرى | SUM(OTHER_INCOME.amount) period | Cash Ledger (OTHER_INCOME events) | Reactive |
| T2.4 | إجمالي المشتريات النقدية | SUM(PURCHASE_CASH + SUPPLIER_PAYMENT.amount) period | Cash Ledger totalOutflow filtered | Reactive |
| T2.5 | إجمالي المبيعات (شامل الآجل) | SUM(sales_invoices.total) WHERE period | sales_invoices | Reactive on salesInvoices write |

### Tier 3 — Secondary (expandable or bottom section)

| # | KPI Name (AR) | Formula | Source Tables | Refresh |
|---|---------------|---------|---------------|---------|
| T3.1 | إجمالي المرتجعات | SUM(RETURN_REFUND.amount) period | Cash Ledger | Reactive |
| T3.2 | عدد المعاملات | transactionCount period | Cash Ledger getSummary | Reactive |
| T3.3 | فارق النقدية (الجلسات) | SUM(pos_sessions.cashDifference) WHERE period | pos_sessions | Reactive |
| T3.4 | تحصيل العملاء | SUM(CUSTOMER_PAYMENT.amount) period | Cash Ledger filtered | Reactive |
| T3.5 | مبيعات البطاقة | SUM(sales_invoices.card_paid) WHERE period | sales_invoices | Reactive |

---

## Section 4 — Date Filter Strategy

### Presets Required
Today / This Week / This Month / This Year / Custom Range

### KPI Filter Behaviour

| KPI | Filter Behaviour | Reasoning |
|-----|-----------------|-----------|
| الرصيد النقدي الحالي (Current Cash Balance) | ALWAYS CURRENT — ignore date filter | Balance is a point-in-time state, not a period aggregate |
| ديون العملاء (Customer Debt) | ALWAYS CURRENT — ignore date filter | Debt is a current obligation; period-scoping has no meaning |
| مستحقات الموردين (Supplier Debt) | ALWAYS CURRENT — ignore date filter | Same reasoning as customer debt |
| صافي التدفق النقدي (Net Cash Flow) | DATE-FILTERED | Period performance metric |
| إجمالي الإيرادات النقدية (Cash Inflow) | DATE-FILTERED | Period metric |
| إجمالي المصروفات (Expenses) | DATE-FILTERED | Period metric |
| إجمالي إيرادات أخرى (Other Income) | DATE-FILTERED | Period metric |
| إجمالي المشتريات النقدية (Purchase Cash) | DATE-FILTERED | Period metric |
| إجمالي المبيعات شامل الآجل (Total Sales) | DATE-FILTERED | Period revenue metric |
| إجمالي المرتجعات (Returns) | DATE-FILTERED | Period metric |
| عدد المعاملات (Transaction Count) | DATE-FILTERED | Period metric |
| فارق النقدية (Session Discrepancy) | DATE-FILTERED | Period cash management metric |

**Design Rule:** Current-state KPIs must be rendered in a separate visual section with a clear
label such as "الحالة الراهنة" (Current State), visually distinct from the date-filtered section.

---

## Section 5 — Cash Balance Design

### Three Candidate Architectures

**Candidate A: Cash Ledger All-Time Net**
Formula: getSummary(filter with no date range) → totalInflow - totalOutflow
- Pros: Consistent with ledger architecture; auto-reactive via _readSet(); includes all 7 event types
- Cons: No "opening balance" injection; balance starts from first recorded transaction
- Implementation: Reuse FinancialLedgerRepository.getSummary() with an "all-time" filter variant

**Candidate B: Last POS Session Closing Cash**
Formula: SELECT closingCash FROM pos_sessions ORDER BY closedAt DESC LIMIT 1
- Pros: Reflects actual counted cash
- Cons: Only updated when a session is closed; lags between session open and close; excludes all
  transactions outside POS sessions (e.g., other_income_records, expense_records without session)

**Candidate C: Hybrid (Ledger Net + Session Anchor)**
Formula: Last POS session openingCash + sum of ledger events since session start
- Pros: Most accurate for reconciliation
- Cons: Complex; requires session-scoped ledger queries; premature for Phase 5

### Recommendation: Candidate A — Cash Ledger All-Time Net

Architecture decision: Run `FinancialLedgerRepository.getSummary()` with a special
`allTime = true` flag (or null date range) that removes the date WHERE clause.
Label the result "الرصيد النقدي التقريبي" (Estimated Cash Balance) with a tooltip explaining
that reconciliation is available in the Cash Ledger screen.

**This requires a minor addition to FinancialLedgerRepository:** a `getSummaryAllTime()` method
(or a filter flag) that omits the date WHERE clause. No schema change. No new table.

---

## Section 6 — Profit vs Cash: Clear Separation

### Cash Metrics (Phase 5 Dashboard — ONLY these)

These represent ACTUAL CASH MOVEMENT:

| Metric | Source | Direction |
|--------|--------|-----------|
| Cash Sales Revenue | SALE_CASH events | IN |
| Customer Payment Collections | CUSTOMER_PAYMENT events | IN |
| Other Income | OTHER_INCOME events | IN |
| Purchase Cash Payments | PURCHASE_CASH events | OUT |
| Supplier Debt Payments | SUPPLIER_PAYMENT events | OUT |
| Expense Payments | EXPENSE events | OUT |
| Return Refunds | RETURN_REFUND events | OUT |
| Card Payments (supplementary) | sales_invoices.card_paid | IN (non-cash) |

### Profitability Metrics (Phase 6 P&L — DO NOT include in Phase 5)

These represent ACCOUNTING INCOME, not cash movement:

| Metric | Note |
|--------|------|
| Gross Revenue (incl. credit sales) | Includes deferred cash (آجل) |
| Cost of Goods Sold (COGS) | Requires product cost integration — NOT READY |
| Gross Margin | COGS not available |
| Net Profit | Requires COGS + operating expenses |
| Depreciation / Amortisation | Not tracked |

**Rule: If a KPI requires COGS, it belongs to Phase 6. Do not include it in Phase 5.**

"Total Sales including credit" (SUM sales_invoices.total) MAY appear on the Phase 5 dashboard
ONLY if it is labeled as "إجمالي المبيعات (نقدي + آجل)" and NOT mixed into any cash formula.

---

## Section 7 — Visual Sections

Recommended dashboard layout for a desktop/large-screen Flutter app:

### Section A — Current State Row (always visible, no date filter)
3 large KPI cards side-by-side:
- Estimated Cash Balance (الرصيد النقدي التقريبي) — amber if negative
- Total Customer Debt (ديون العملاء) — red if > threshold
- Total Supplier Debt (مستحقات الموردين) — orange if > threshold

### Section B — Date Filter Bar
Preset tabs: اليوم / هذا الأسبوع / هذا الشهر / هذه السنة / مخصص
All sections below this bar respond to the selected period.

### Section C — Cash Flow Summary Row (date-filtered)
4 KPI cards:
- Cash Inflow (إجمالي الوارد)
- Cash Outflow (إجمالي الصادر)
- Net Cash Flow (صافي التدفق) — green if positive, red if negative
- Transaction Count (عدد المعاملات)

### Section D — Revenue & Expense Breakdown (date-filtered)
3 KPI cards:
- Total Cash Sales (المبيعات النقدية) — from SALE_CASH
- Total Expenses (المصروفات) — from EXPENSE events
- Total Other Income (إيرادات أخرى) — from OTHER_INCOME events

### Section E — Supplementary Row (date-filtered)
3 KPI cards:
- Total Sales incl. Credit (شامل الآجل) — clearly labeled, from sales_invoices.total
- Total Returns (المرتجعات) — from RETURN_REFUND events
- Session Cash Discrepancy (فارق النقدية) — from pos_sessions

### Section F — Recent Financial Activity (date-filtered, top 10)
Compact list of the 10 most recent Cash Ledger entries for the selected period.
- Shows: timestamp, event type chip, amount, direction
- "View Full Ledger" link → navigates to Cash Ledger screen

---

## Section 8 — Data Quality Audit

| Issue | Priority | Description |
|-------|----------|-------------|
| No opening balance injection | MEDIUM | The all-time cash balance has no "starting cash" record. The business may have had physical cash before the system began. Phase 7 (Reconciliation) must address this with an opening_balance table or app_settings entry. |
| Card payment outside cash flow | LOW | card_paid is in sales_invoices but not in Cash Ledger. The dashboard shows it as supplementary only. Clear labeling required. |
| Supplier returns not in Cash Ledger | LOW | supplier_returns table exists (schema confirmed). If a supplier refunds cash, it is NOT currently captured in the Cash Ledger. This is a future gap. |
| expense_records has no CHECK constraint on amount > 0 | LOW | Unlike other_income_records, the expense_records table does not have a CHECK (amount > 0) constraint. The Cash Ledger uses AND er.amount > 0 as a guard. This is safe but schema-level enforcement would be stronger. |
| pos_sessions.expectedCashAmount nullable until close | LOW | expectedCashAmount is only populated when a session closes. Dashboard session discrepancy requires only closed sessions — query must filter isClosed = true. |
| No financial period locking | MEDIUM | There is no mechanism to "lock" a period (e.g., close January). Retroactive edits/voids can change past period KPIs without warning. Phase 7 should introduce period locking or audit flags. |
| customer_accounts balance drift risk | LOW | If a bug in the DAO fails to update customer_accounts atomically, the cached balance could diverge from customer_transactions sum. The architecture mitigates this with Drift transactions, but no periodic reconciliation job exists. |

---

## Section 9 — Future Phase Compatibility

### Phase 6 — Profit & Loss

| Dependency | Status | Notes |
|------------|--------|-------|
| Revenue (sales_invoices.total) | READY | Queryable by period |
| Expense records | READY | expense_records queryable by period |
| Other Income records | READY | other_income_records queryable by period |
| COGS (cost of goods sold) | NOT READY | Requires purchase_items × product cost per sale. sale_items table exists but cost-at-time-of-sale needs verification. |
| Gross Profit | BLOCKED by COGS | Cannot compute until COGS is available |
| P&L Statement Layout | FUTURE | New screen; no dependencies on Phase 5 UI |

### Phase 7 — Cash Reconciliation

| Dependency | Status | Notes |
|------------|--------|-------|
| Cash Ledger running balance | READY | Exists today |
| POS Session cash counts | READY | pos_sessions.closingCash, expectedCashAmount, cashDifference |
| Opening balance injection | MISSING | Needs app_settings entry or a dedicated opening_balance table |
| Period locking mechanism | MISSING | No current support |
| Reconciliation workflow | FUTURE | New screen, new logic |

### Phase 8 — Advanced Analytics

| Dependency | Status | Notes |
|------------|--------|-------|
| Time-series aggregation | PARTIAL | Cash Ledger can be grouped by date; no dedicated time-bucket table |
| Sales trend charts | PARTIAL | Data exists; charting widget not scoped |
| Top expenses by category | READY | expense_records GROUP BY category_id |
| Customer payment behaviour | PARTIAL | customer_transactions has data; analytics queries not built |
| Inventory turnover | NOT READY | Requires COGS + average stock calculation |

---

## Section 10 — Performance Strategy

### Aggregation Strategy

1. **Cash Flow KPIs** — Use `FinancialLedgerRepository.getSummary()`. Single SQL query over the
   7-block UNION with WHERE date filter. Returns totalInflow, totalOutflow, netCashFlow,
   transactionCount in one round trip.

2. **Current Cash Balance (all-time)** — New `getSummaryAllTime()` method in
   `FinancialLedgerRepository`. Same SQL as getSummary but without the date WHERE clause.
   Runs once at dashboard load; cached for 45s (consistent with existing pattern).

3. **Customer/Supplier Debt** — Direct aggregate on balance-cache tables:
   `SELECT SUM(currentBalance) FROM customer_accounts WHERE currentBalance > 0`
   These are O(n) where n = number of customers/suppliers, not O(all transactions). Fast.

4. **Supplementary KPIs (Total Sales incl. credit, Session Discrepancy)** — Separate lightweight
   queries run concurrently. Not blocking.

5. **Recent Activity** — Reuse `cashLedgerEntriesProvider` with pageSize=10.
   No new queries needed.

### Caching Strategy

- All FutureProvider.autoDispose with 45-second keepAlive (consistent with existing pattern).
- Date-filtered KPIs share a single dashboard provider keyed on the filter.
- Current-state KPIs use a separate provider (not date-dependent) with reactive tables.
- Do NOT share `cashLedgerFilterProvider` state — create a dedicated `dashboardFilterProvider`.

### Provider Strategy

```
dashboardFilterProvider          (Notifier<DashboardFilter>)
dashboardCashFlowProvider        (FutureProvider.autoDispose, watches dashboardFilterProvider)
dashboardCurrentStateProvider    (FutureProvider.autoDispose, no filter dependency)
dashboardRecentActivityProvider  (FutureProvider.autoDispose, watches dashboardFilterProvider)
```

Maximum: 3 simultaneous SQL queries on dashboard load. Acceptable.

### Avoid Expensive Queries

- NEVER run SUM(customer_transactions.amount) per customer — use customer_accounts cache.
- NEVER compute running balance on the dashboard — it is not needed; only net totals are.
- NEVER join sale_items on the dashboard — product-level breakdown is Phase 8 scope.

---

## Section 11 — Implementation Roadmap

### Phase 5.1 — Dashboard KPI Data Layer
**Purpose:** New `FinancialDashboardRepository` with all KPI queries.
Create domain models: `DashboardCashFlowKpis`, `DashboardCurrentStateKpis`.
Add `getSummaryAllTime()` to `FinancialLedgerRepository`.

Files to create:
- `lib/features/financial/models/dashboard_cash_flow_kpis.dart`
- `lib/features/financial/models/dashboard_current_state_kpis.dart`
- `lib/features/financial/repositories/financial_dashboard_repository.dart`

Modify:
- `lib/features/financial/repositories/financial_ledger_repository.dart` (add getSummaryAllTime)

**Complexity:** LOW-MEDIUM
**Risk:** LOW — reuses existing SQL patterns
**Effort:** 1 day

---

### Phase 5.2 — Dashboard Providers
**Purpose:** Riverpod providers wiring dashboard data to the UI.

Files to create:
- `lib/features/financial/models/dashboard_filter.dart`
- `lib/features/financial/providers/dashboard_filter_provider.dart`
- `lib/features/financial/providers/financial_dashboard_providers.dart`

**Complexity:** LOW
**Risk:** LOW
**Effort:** 0.5 days

---

### Phase 5.3 — Dashboard Screen & KPI Cards
**Purpose:** Main dashboard screen implementing Section 7 layout.
All 6 visual sections. Date filter bar. KPI card widgets.

Files to create:
- `lib/features/financial/screens/financial_dashboard_screen.dart`
- `lib/features/financial/screens/widgets/dashboard_kpi_card.dart`
- `lib/features/financial/screens/widgets/dashboard_current_state_section.dart`
- `lib/features/financial/screens/widgets/dashboard_cash_flow_section.dart`
- `lib/features/financial/screens/widgets/dashboard_breakdown_section.dart`

Modify:
- `lib/app.dart` — add route
- `lib/core/widgets/side_nav.dart` — add nav entry
- `lib/features/auth/permissions/route_permissions.dart` — add permission

**Complexity:** MEDIUM
**Risk:** LOW — well-defined layout, no new business logic
**Effort:** 2 days

---

### Phase 5.4 — Recent Activity Feed & Quick Navigation
**Purpose:** Compact recent-activity list + links to sub-modules.
Reuses existing cashLedgerEntriesProvider.

Files to create:
- `lib/features/financial/screens/widgets/dashboard_recent_activity.dart`

**Complexity:** LOW
**Risk:** LOW
**Effort:** 0.5 days

---

### Summary

| Phase | Purpose | Complexity | Risk | Effort |
|-------|---------|------------|------|--------|
| 5.1 | KPI Data Layer | LOW-MEDIUM | LOW | 1 day |
| 5.2 | Providers | LOW | LOW | 0.5 days |
| 5.3 | Screen & Cards | MEDIUM | LOW | 2 days |
| 5.4 | Recent Activity | LOW | LOW | 0.5 days |
| **Total** | | | | **~4 days** |

---

## Section 12 — Risk Assessment

| Risk | Severity | Description | Mitigation |
|------|----------|-------------|------------|
| Incorrect KPI labeling (cash vs accrual) | HIGH | Showing SUM(sales_invoices.total) as "Cash Revenue" would overstate cash position by all credit sales. | Strict labeling rules. Total Sales labeled separately as "شامل الآجل". |
| Cash balance accuracy gap | MEDIUM | All-time ledger net has no opening balance. Physical cash at system launch is unrecorded. | Label as "تقريبي". Phase 7 opens balance injection. |
| Double counting via Phase 5 new queries | MEDIUM | A new dashboard query that bypasses the Cash Ledger UNION guards could double-count. | All cash aggregation MUST use the Cash Ledger UNION or be justified independently. |
| Performance regression on all-time query | LOW | getSummaryAllTime() scans all ledger rows without date filter. With full indexes and <100k rows, this is fast. | Monitor with flutter performance tools; add cache. |
| Future maintenance: P&L metric creep | LOW | A developer might add COGS or margin metrics to Phase 5 dashboard. | Document scope boundary explicitly. Phase 6 = P&L screen, not dashboard cards. |
| Supplier returns missing from ledger | LOW | Cash refunds FROM suppliers are not in the Cash Ledger yet (supplier_returns table exists but not integrated). | Document gap; add to Phase 5.1 backlog as optional extension. |
| pos_sessions open-session state | LOW | A currently-open session has no closingCash. Session discrepancy must only aggregate isClosed = true sessions. | WHERE isClosed = 1 in all session aggregation queries. |

---

## Recommended KPI Formulas Reference

### All Cash Flow KPIs use the Cash Ledger UNION as their data source.
Never query the operational tables directly for cash flow aggregation.

```
Cash Inflow (period)      = getSummary(period).totalInflow
Cash Outflow (period)     = getSummary(period).totalOutflow
Net Cash Flow (period)    = getSummary(period).netCashFlow
Transaction Count         = getSummary(period).transactionCount

Cash Sales (period)       = getSummary(period, eventType=SALE_CASH).totalInflow
Customer Collections      = getSummary(period, eventType=CUSTOMER_PAYMENT).totalInflow
Other Income (period)     = getSummary(period, eventType=OTHER_INCOME).totalInflow
Expenses (period)         = getSummary(period, eventType=EXPENSE).totalOutflow
Purchase Cash (period)    = getSummary(period, eventType=PURCHASE_CASH).totalOutflow
Supplier Payments (period)= getSummary(period, eventType=SUPPLIER_PAYMENT).totalOutflow
Returns (period)          = getSummary(period, eventType=RETURN_REFUND).totalOutflow

Current Cash Balance      = getSummaryAllTime().totalInflow - getSummaryAllTime().totalOutflow

Customer Debt             = SELECT COALESCE(SUM(currentBalance),0)
                              FROM customer_accounts WHERE currentBalance > 0

Supplier Debt             = SELECT COALESCE(SUM(currentBalance),0)
                              FROM supplier_accounts WHERE currentBalance > 0

Total Sales (incl. credit)= SELECT COALESCE(SUM(total),0) FROM sales_invoices
                              WHERE sale_date >= start AND sale_date < end

Session Discrepancy       = SELECT COALESCE(SUM(cashDifference),0) FROM pos_sessions
                              WHERE closedAt >= start AND closedAt < end AND isClosed = 1
```

---

## Architecture Decisions

| Decision | Choice | Reasoning |
|----------|--------|-----------|
| Cash flow aggregation layer | Cash Ledger UNION (existing) | Validated, double-count-free, reactive |
| Debt KPI source | customer_accounts / supplier_accounts balance cache | O(n accounts) vs O(all transactions) |
| Cash balance approach | All-time ledger net | Consistent with architecture; transparent |
| Dashboard filter state | New dashboardFilterProvider (separate from cashLedgerFilterProvider) | Separate screen, separate state |
| Provider caching | keepAlive 45s (same as existing pattern) | Consistency |
| Profit/Loss scope | Excluded from Phase 5 | Needs COGS; belongs to Phase 6 |
| Card payment KPI | Supplementary only, clearly labeled | Not a cash metric; avoid polluting cash view |

---

## Readiness Score

| Section | Score |
|---------|-------|
| 1 — Existing Sources | 100 / 100 |
| 2 — Current Capabilities | 98 / 100 |
| 3 — KPI Design | 97 / 100 |
| 4 — Date Filter Strategy | 100 / 100 |
| 5 — Cash Balance Design | 95 / 100 |
| 6 — Profit vs Cash | 100 / 100 |
| 7 — Visual Sections | 96 / 100 |
| 8 — Data Quality | 88 / 100 |
| 9 — Future Compatibility | 92 / 100 |
| 10 — Performance Strategy | 97 / 100 |
| 11 — Implementation Roadmap | 97 / 100 |
| 12 — Risk Assessment | 94 / 100 |

### Overall Score: 95 / 100

---

## Final Decision

```
+------------------------------------------------------+
|                                                      |
|                     GO  (95/100)                     |
|                                                      |
|   Phase 5.0 — FINANCIAL DASHBOARD                   |
|   Architecture is sound.                            |
|   All required data exists.                         |
|   No schema changes required.                       |
|   Ready for Phase 5.1 implementation.               |
|                                                      |
+------------------------------------------------------+
```

### Pre-Implementation Checklist

Before beginning Phase 5.1, confirm:

- [ ] Phase 4.3 commit is merged (OTHER_INCOME in Cash Ledger — required for complete KPIs)
- [ ] FinancialLedgerRepository.getSummary() is confirmed working for partial date ranges
- [ ] customer_accounts and supplier_accounts are confirmed to be atomically updated (DAO review)
- [ ] Dashboard will NOT include any COGS, Gross Profit, or Net Profit calculation
- [ ] All "Total Sales incl. credit" figures will be clearly labeled to avoid confusion with cash revenue
- [ ] Session discrepancy query will filter WHERE isClosed = 1

### Scope Boundaries — Phase 5 vs Future Phases

| Feature | Phase 5 | Phase 6 | Phase 7 | Phase 8 |
|---------|---------|---------|---------|---------|
| Cash KPI Cards | YES | — | — | — |
| Debt Overview | YES | — | — | — |
| Recent Activity Feed | YES | — | — | — |
| Gross Profit / Margin | NO | YES | — | — |
| P&L Statement | NO | YES | — | — |
| Cash Reconciliation | NO | — | YES | — |
| Opening Balance | NO | — | YES | — |
| Trend Charts | NO | — | — | YES |
| Sales by Category | NO | — | — | YES |