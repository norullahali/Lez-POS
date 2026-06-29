# PHASE 5.0 — FINANCIAL DASHBOARD
## FINAL ARCHITECTURE REVIEW
**Reviewer:** Principal ERP Architect
**Date:** 2026-06-24
**Source Document:** docs/financial_dashboard_architecture_audit.md
**Mode:** Read-only review — no code modifications, no file changes

---

## Executive Summary

The architecture audit is well-structured and architecturally sound in its major decisions.
The Cash Ledger as the primary aggregation layer is correct.
The debt KPI source choice (balance-cache tables) is correct.
The Cash/Profit separation rule is correct.

However, the review identifies **four findings** that must be resolved before Phase 5.1 begins:

| ID | Severity | Category | Status |
|----|----------|----------|--------|
| F1 | MEDIUM | Formula Inconsistency | REQUIRED CORRECTION |
| F2 | MEDIUM | Provider/Data Coupling Conflict | REQUIRED CORRECTION |
| F3 | MEDIUM | Visual Section Arithmetic Gap | REQUIRED CORRECTION |
| F4 | LOW | KPI Name Inconsistency | REQUIRED CORRECTION |
| O1 | LOW | Repository Dependency Boundary | OPTIONAL IMPROVEMENT |
| O2 | LOW | Cash Balance Label | OPTIONAL IMPROVEMENT |

All four required corrections are in the **planning/specification layer**, not in code.
They can be resolved by updating the architecture document before Phase 5.1 starts.
No code, no schema, and no migrations are affected.

**Final Verdict: CONDITIONAL GO (91/100)**
Corrections F1–F4 must be resolved before implementation begins.

---

## Section 1 — Cash vs Profit Audit

Every proposed KPI was individually classified against the rule:
**"A Phase 5 KPI must be either a cash movement metric or a balance-sheet state metric.
It must never include accrual revenue, COGS, or accounting profit."**

### KPI Classification

| KPI | Label | Formula Source | Classification | Verdict |
|-----|-------|---------------|----------------|---------|
| Cash Balance | الرصيد النقدي الحالي / التقريبي | getSummaryAllTime() | CASH STATE | SAFE |
| Cash Inflow | إجمالي الوارد | getSummary.totalInflow | CASH MOVEMENT | SAFE |
| Cash Outflow | إجمالي الصادر | getSummary.totalOutflow | CASH MOVEMENT | SAFE |
| Net Cash Flow | صافي التدفق النقدي | totalInflow - totalOutflow | CASH MOVEMENT | SAFE |
| Total Sales incl. credit | إجمالي المبيعات شامل الآجل | SUM(sales_invoices.total) | ACCRUAL REVENUE | RISK — see detail |
| Cash Sales | المبيعات النقدية | SALE_CASH events | CASH MOVEMENT | SAFE |
| Other Income | إيرادات أخرى | OTHER_INCOME events | CASH MOVEMENT | SAFE |
| Expenses | المصروفات | EXPENSE events | CASH MOVEMENT | SAFE |
| Purchase Cash | المشتريات النقدية | PURCHASE_CASH + SUPPLIER_PAYMENT | CASH MOVEMENT | SAFE |
| Returns | المرتجعات | RETURN_REFUND events | CASH MOVEMENT | SAFE |
| Customer Debt | ديون العملاء | customer_accounts.currentBalance | BALANCE SHEET STATE | SAFE |
| Supplier Debt | مستحقات الموردين | supplier_accounts.currentBalance | BALANCE SHEET STATE | SAFE |
| Session Discrepancy | فارق النقدية | pos_sessions.cashDifference | CASH MANAGEMENT | SAFE |
| Card Revenue | مبيعات البطاقة | sales_invoices.card_paid | NON-CASH PAYMENT | SAFE if labeled |

### Detail: "Total Sales incl. credit" — RISK, MANAGED

Status: **RISK — MANAGED** (the audit correctly identifies and controls this risk)

SUM(sales_invoices.total) includes:
- cash_paid (cash movement — already counted in SALE_CASH events)
- card_paid (card collection — NOT in Cash Ledger)
- debt_amount (deferred cash/آجل — NOT cash movement)

If a developer feeds SUM(sales_invoices.total) into any cash formula (e.g., Net Cash Flow),
the result will double-count cash sales AND include non-cash accrual amounts.

The audit handles this by:
1. Placing this KPI in Tier 2 / Section E (clearly separated from cash-flow section)
2. Requiring the label "(شامل الآجل)" on all occurrences
3. Adding an explicit rule: "NOT mixed into any cash formula"

The risk is REAL but CONTROLLED by the labeling and layout rules in the audit.
Implementation must enforce these rules strictly. If the developer removes the label or
places this card near the net cash flow display, the risk becomes HIGH immediately.

**Recommendation:** The implementation phase should include an explicit code comment in the
dashboard screen widget noting that this card must never contribute to any cash formula.

### Finding: T2.1 Formula — Cash Inflow Inconsistency (→ F1)

T2.1 is labeled "إجمالي الإيرادات النقدية" and its formula in Section 3 KPI table reads:
`SUM(SALE_CASH.amount) + SUM(CUSTOMER_PAYMENT.amount) period`

BUT the Formulas Reference section (bottom of document) states:
`Cash Inflow (period) = getSummary(period).totalInflow`

`getSummary(period).totalInflow` covers ALL inflow event types:
SALE_CASH + CUSTOMER_PAYMENT + **OTHER_INCOME**

These two formulas produce DIFFERENT numbers. If OTHER_INCOME events exist in the period,
Section 3's formula will undercount Cash Inflow vs what totalInflow returns.

Furthermore: Section C (Visual) shows "إجمالي الوارد" = totalInflow (all 3 inflow types)
while Section D shows "المبيعات النقدية" + "إيرادات أخرى" as two separate breakdown cards.
This structure implies:
- Section C total = SALE_CASH + CUSTOMER_PAYMENT + OTHER_INCOME
- Section D shows: SALE_CASH (separately), OTHER_INCOME (separately)
- Missing from Section D: CUSTOMER_PAYMENT (تحصيل العملاء)

This inconsistency is documented as **Finding F1** and **Finding F3** below.

---

## Section 2 — KPI Label Audit

### Label Classification

| Label | Arabic | Risk Level | Verdict |
|-------|--------|------------|---------|
| الرصيد النقدي الحالي (Section 3) | "Current Cash Balance" | MEDIUM — implies real-time accuracy not guaranteed | MISLEADING — see F4 |
| الرصيد النقدي التقريبي (Section 5/7) | "Estimated Cash Balance" | LOW | SAFE but imprecise |
| إجمالي الإيرادات النقدية (T2.1) | "Total Cash Revenues" | HIGH if it excludes OTHER_INCOME | NEEDS RESOLUTION (F1) |
| إجمالي المبيعات (شامل الآجل) | "Total Sales (incl. credit)" | MEDIUM — parenthetical may be overlooked | CONDITIONALLY SAFE |
| المبيعات النقدية | "Cash Sales" | LOW | SAFE |
| إجمالي المصروفات | "Total Expenses" | LOW | SAFE |
| إجمالي إيرادات أخرى | "Total Other Income" | LOW | SAFE |
| إجمالي المشتريات النقدية | "Total Cash Purchases" | LOW | SAFE |
| إجمالي الوارد | "Total Inflow" | LOW — neutral, accurate | SAFE |
| إجمالي الصادر | "Total Outflow" | LOW | SAFE |
| صافي التدفق النقدي | "Net Cash Flow" | LOW | SAFE |
| ديون العملاء | "Customer Debts" | LOW | SAFE |
| مستحقات الموردين | "Supplier Payables" | LOW | SAFE |
| فارق النقدية (الجلسات) | "Session Cash Discrepancy" | LOW | SAFE |
| مبيعات البطاقة | "Card Sales" | LOW if sub-labeled as non-cash | CONDITIONALLY SAFE |

### Required Label Corrections

**"الرصيد النقدي الحالي" → MISLEADING**
Section 3 (T1.1) calls the all-time ledger net "الرصيد النقدي الحالي" (Current Cash Balance).
This phrase implies real-time, reconciled accuracy that this KPI cannot provide:
it excludes pre-system cash, unrecorded transactions, and physical counting discrepancies.
A store owner reading "الرصيد النقدي الحالي" will trust it as the exact cash in the drawer.

**Section 5 and Section 7 correctly rename this to "الرصيد النقدي التقريبي"** (Estimated).
But "التقريبي" (approximate) may alarm some owners ("Why is my balance just an estimate?").

**Recommended label: "الرصيد النقدي المحسوب"** (Calculated Cash Balance)
- "محسوب" (calculated) is professional, accurate, and explains the method without alarm
- It sets the correct expectation: "the system calculated this from all recorded transactions"
- It distinguishes it from a physically counted balance without using "approximate"
- A tooltip: "محسوب من جميع المعاملات المسجلة في النظام — للمطابقة الدقيقة راجع الكشف النقدي"

**"إجمالي المبيعات (شامل الآجل)" → CONDITIONALLY SAFE**
The parenthetical "(شامل الآجل)" must always be displayed in full, never truncated.
In a card design with limited space, the full label including the parenthetical must fit.
If UI space forces truncation, it should become two lines:
Line 1: "إجمالي المبيعات"
Line 2 (small, secondary text): "نقدي وآجل"

---

## Section 3 — Cash Balance Audit

### Recommendation Evaluation

The audit recommends Candidate A: All-Time Cash Ledger Net.
This reviewer **agrees** with Candidate A as the correct architectural choice for Phase 5.

Rationale:
1. Consistent with the derived ledger architecture established in Phases 3–4.
2. Automatically reactive via _readSet() — no manual refresh required.
3. Includes all 7 event types — no partial coverage.
4. Simple to implement: getSummaryAllTime() with no date WHERE clause.

### Label Decision

| Candidate Label | Assessment |
|----------------|------------|
| الرصيد النقدي الحالي | REJECTED — implies exact real-time count |
| الرصيد النقدي التقريبي | ACCEPTABLE — honest but may alarm owners |
| الرصيد النقدي المحسوب | RECOMMENDED — professional, accurate, expected |
| صافي النقدية المسجلة | ACCEPTABLE — "Recorded Net Cash" is transparent |

**Final recommendation: الرصيد النقدي المحسوب**
With a consistent tooltip everywhere this KPI appears explaining its source.

### Future Phase Compatibility

| Phase | Compatibility |
|-------|---------------|
| Phase 7 Reconciliation | COMPATIBLE — getSummaryAllTime() becomes the "system balance" in the reconciliation screen |
| Phase 7 Opening Balance | COMPATIBLE — an opening balance offset can be added to getSummaryAllTime() result without changing the method signature |
| POS Session Compatibility | COMPATIBLE — the Candidate A balance naturally includes all non-session transactions (other_income, expense) that Candidate B misses |

---

## Section 4 — Debt KPI Audit

### Source Verification: customer_accounts and supplier_accounts

The audit recommends reading debt from the balance-cache tables directly.
This reviewer **confirms** this is the correct approach.

Evidence from schema:
- `customer_accounts` comment: *"Balance is always re-derived from CustomerTransactions for
  accuracy; this row is updated atomically inside every DAO transaction."*
- `supplier_accounts`: same pattern.

This means:
1. The cache is atomically maintained — no read-write race condition possible via Drift transactions.
2. The balance in `currentBalance` is always equal to SUM(customer_transactions.amount) for that customer.
3. Reading SUM(customer_accounts.currentBalance WHERE > 0) is correct, O(n accounts), and safe.

### Verification: Formula Correctness

```
Customer Debt = SELECT COALESCE(SUM(currentBalance),0)
                FROM customer_accounts WHERE currentBalance > 0
```

Correct: `WHERE currentBalance > 0` excludes:
- Zero-balance customers (no debt) — ✅
- Negative-balance customers (customer has credit/overpayment) — ✅ correctly excluded from "debt"

```
Supplier Debt = SELECT COALESCE(SUM(currentBalance),0)
                FROM supplier_accounts WHERE currentBalance > 0
```

Correct: positive balance = we owe the supplier (confirmed by schema comment).
`WHERE currentBalance > 0` correctly includes only outstanding payables.

### Potential Drift Risk

The audit flags "customer_accounts balance drift risk" as LOW.
This reviewer agrees: LOW but real. The drift would only occur if a DAO write to
`customer_transactions` fails atomically — which Drift's transaction() prevents.
No additional action required for Phase 5.

### Reactivity Gap (not identified in audit)

The `dashboardCurrentStateProvider` must register `customer_accounts` and `supplier_accounts`
in a Drift `readsFrom` set for reactive invalidation. The audit does not explicitly specify
which tables `dashboardCurrentStateProvider` registers. This must be specified in Phase 5.1.

---

## Section 5 — Repository Boundary Audit

### Proposed: FinancialDashboardRepository

The audit states the dashboard repository must remain "aggregation-only" and must not duplicate
logic from `FinancialLedgerRepository`.

A dependency ambiguity exists in the audit that must be resolved:

**Ambiguity:** Does `FinancialDashboardRepository` call `FinancialLedgerRepository`?

The audit proposes that `getSummaryAllTime()` lives in `FinancialLedgerRepository` (correct)
and that `FinancialDashboardRepository` handles "non-ledger queries" (debt, total sales,
session discrepancy). This implies the dashboard PROVIDERS independently call both repositories.

**Correct architecture (not repository-to-repository, but provider-to-repository):**

```
dashboardCashFlowProvider
  → ref.read(financialLedgerRepositoryProvider).getSummary(filter)
  → ref.read(financialLedgerRepositoryProvider).getSummaryAllTime()
  → ref.read(financialDashboardRepositoryProvider).getSupplementaryKpis(filter)

dashboardCurrentStateProvider
  → ref.read(financialDashboardRepositoryProvider).getCurrentStateKpis()

dashboardRecentActivityProvider
  → ref.read(financialLedgerRepositoryProvider).getEntries(filter, pageSize=10)
```

`FinancialDashboardRepository` contains ONLY:
- `getCurrentStateKpis()` → debt aggregation from customer/supplier accounts
- `getSupplementaryKpis(filter)` → total sales (sales_invoices), session discrepancy (pos_sessions)

This boundary ensures:
- `FinancialLedgerRepository` owns all Cash Ledger UNION logic (no duplication)
- `FinancialDashboardRepository` owns only non-ledger aggregations
- No repository calls another repository
- Providers orchestrate the two repositories

This clarification is documented as **Optional Improvement O1** (not a blocking gap, but
the implementation phase will benefit from it being explicit).

---

## Section 6 — Provider Architecture Audit

### Review of Provider Specification

```
dashboardFilterProvider          (Notifier<DashboardFilter>)       — SAFE
dashboardCashFlowProvider        (FutureProvider.autoDispose)       — SAFE
dashboardCurrentStateProvider    (FutureProvider.autoDispose)       — SAFE
dashboardRecentActivityProvider  (FutureProvider.autoDispose)       — CONFLICT — see F2
```

### Finding F2: dashboardRecentActivityProvider Coupling Conflict

The audit contains conflicting statements about `dashboardRecentActivityProvider`:

**Statement A** (Section 10, Provider Strategy):
"dashboardRecentActivityProvider (FutureProvider.autoDispose, watches dashboardFilterProvider)"

**Statement B** (Section 10, Performance Strategy):
"Recent Activity — **Reuse cashLedgerEntriesProvider** with pageSize=10. No new queries needed."

These are mutually exclusive:
- `cashLedgerEntriesProvider` watches `cashLedgerFilterProvider` (the Cash Ledger screen filter)
- `dashboardRecentActivityProvider` is described as watching `dashboardFilterProvider`

If Statement B is followed (reusing `cashLedgerEntriesProvider`), the dashboard's recent
activity section will respond to the Cash Ledger screen's date filter, NOT the dashboard's
own date filter. This violates the stated "No coupling with cashLedgerFilterProvider" rule.

**Resolution required before Phase 5.1:**
`dashboardRecentActivityProvider` must call `financialLedgerRepositoryProvider.getEntries()`
with the `dashboardFilterProvider` date range and `pageSize=10`.
It must NOT reuse `cashLedgerEntriesProvider`.
Statement B must be removed from the audit document.

### No Dependency Cycles

Confirmed: the proposed provider graph is acyclic.

```
dashboardFilterProvider
       ↓
dashboardCashFlowProvider → financialLedgerRepositoryProvider
       ↓                  → financialDashboardRepositoryProvider
dashboardRecentActivityProvider → financialLedgerRepositoryProvider

dashboardCurrentStateProvider → financialDashboardRepositoryProvider
```

No cycles. No shared mutable state between providers. ✅

### Isolation from Cash Ledger Filter

The audit correctly mandates a separate `dashboardFilterProvider`.
`CashLedgerFilterNotifier` manages the Cash Ledger screen's filter state.
`DashboardFilterNotifier` manages the Dashboard's filter state.
These are independent — confirmed safe.

---

## Section 7 — Performance Audit

### getSummaryAllTime() Analysis

Formula: `SELECT SUM(inflow), SUM(outflow), COUNT(*) FROM (7-block UNION)` — no date WHERE clause.

This is a full-table scan across all 7 source tables simultaneously.

| Scale | Expected Duration | Risk |
|-------|------------------|------|
| 10,000 total ledger rows | < 5 ms | LOW |
| 50,000 total ledger rows | < 25 ms | LOW |
| 100,000 total ledger rows | 50–150 ms | MEDIUM (without date filter, index cannot bound scan) |
| 500,000 total ledger rows | 500 ms+ | HIGH — 45s cache becomes critical |

**Classification: LOW at typical POS scale (<50k records), MEDIUM at scale.**

The 45-second cache is essential for this KPI. Without it, every screen load would trigger
a full ledger scan. The cache is correctly specified in the audit.

**Index coverage for getSummaryAllTime():**
Without a date filter, the WHERE clauses per UNION block are:
- `si.cash_paid > 0` → no index on cash_paid → sequential scan of sales_invoices
- `ct.type = 'PAYMENT'` → ct_type_idx exists → ✅ index-assisted
- `pi.paid_amount > 0` → no index → sequential scan of purchase_invoices
- `st.type = 'PAYMENT' AND NOT EXISTS (...)` → supp_tx_supplier_time_idx partial → moderate
- `er.is_voided = 0 AND er.amount > 0` → expense_records_voided_idx exists → ✅ index-assisted
- `oir.is_voided = 0 AND oir.amount > 0` → other_income_records_voided_idx exists → ✅

For a typical POS store with <20,000 sales invoices, this remains fast even without index coverage.
The 45s cache prevents repeated scans.

### Customer/Supplier Debt Aggregation

```sql
SELECT COALESCE(SUM(currentBalance),0) FROM customer_accounts WHERE currentBalance > 0
```

| Scale | Expected Duration | Risk |
|-------|------------------|------|
| 100 customers | < 1 ms | LOW |
| 1,000 customers | < 2 ms | LOW |
| 10,000 customers | < 10 ms | LOW |

ca_customer_idx exists. This is an indexed aggregate scan. Consistently LOW risk at all scales.

### Recent Activity Feed (top 10)

Reuses `getEntries()` with pageSize=10 and date filter.
Includes running balance window function (present in existing code).
At any date-filtered page, this is consistently fast — LOW risk.

### Overall Performance Risk: LOW for Phase 5 scope.

The getSummaryAllTime() full-scan with 45s caching is the only performance concern,
and only above 50,000 total records. Acceptable for a single-store POS system.

---

## Section 8 — Future Phase Compatibility

### Phase 6 — Profit & Loss

No blocking dependency. The audit correctly excludes COGS and margin from Phase 5.

One note for Phase 6 architects: `sale_items` table (referenced in schema) contains
`unitCost` data which will be critical for COGS. The cost-at-time-of-sale question
mentioned in the audit ("sale_items table exists but cost-at-time-of-sale needs verification")
should be verified BEFORE Phase 6 begins, not during.

Phase 5 decisions that may affect Phase 6:
- None identified. Phase 5 dashboard is additive, not restructuring.

### Phase 7 — Cash Reconciliation

`getSummaryAllTime()` becomes the "system-calculated balance" in the reconciliation screen.
The opening balance injection needed for Phase 7 does NOT require modifying `getSummaryAllTime()`.
It can be implemented as: displayed_balance = getSummaryAllTime().netCashFlow + openingBalance
where openingBalance is stored in app_settings or a future opening_balance table.

Phase 5 decisions that may affect Phase 7:
- **The label "الرصيد النقدي المحسوب" (Calculated Cash Balance)** sets the correct user expectation
  for Phase 7 reconciliation. Users who already understand the balance is "calculated" will not
  be surprised when Phase 7 introduces a reconciliation adjustment.
- Conversely, if Phase 5 uses "الرصيد النقدي الحالي" (Current Balance), Phase 7 will need to
  re-educate users about why the "current" balance changed after adding an opening balance.

### Phase 8 — Advanced Analytics

Phase 5 architecture does not block Phase 8. However:
- Time-series aggregation for charts will require extending `getSummary()` with a GROUP BY date
  bucket. This is an additive extension to `FinancialLedgerRepository`, not a breaking change.
- The `dashboardFilterProvider` → `DashboardFilter` model should be designed with a `granularity`
  field in mind (day/week/month) for future Phase 8 chart support, even if unused in Phase 5.

---

## Section 9 — Architecture Gaps

Only real gaps are reported here. No hypothetical issues.

---

### F1 — MEDIUM — Formula Inconsistency: T2.1 Cash Inflow

**Location:** Section 3 KPI table (T2.1) vs Section 10 Formulas Reference

**Section 3 T2.1 formula:**
`SUM(SALE_CASH.amount) + SUM(CUSTOMER_PAYMENT.amount)` ← excludes OTHER_INCOME

**Formulas Reference:**
`Cash Inflow (period) = getSummary(period).totalInflow` ← includes OTHER_INCOME

**Impact:** If a developer reads Section 3 to implement T2.1, the KPI will show a different
number than totalInflow. When Section C shows "إجمالي الوارد = totalInflow" and Section D
shows "إجمالي الإيرادات النقدية = SALE_CASH + CUSTOMER_PAYMENT", the store owner will see:

```
Total Inflow:    10,000
Cash Revenues:    8,500    ← excludes 1,500 of Other Income
Other Income:     1,500
```

At this point the owner sees 8,500 + 1,500 = 10,000 = Total Inflow — OK, that's consistent.

BUT the T2.1 label "إجمالي الإيرادات النقدية" means "Total Cash Revenues" which Arabic
speakers would interpret as ALL cash revenues, including Other Income. The naming conflicts
with the formula.

**Required resolution (choose one):**
Option A: Rename T2.1 to "إيرادات المبيعات والتحصيل" (Sales & Collection Revenue)
and keep formula as SALE_CASH + CUSTOMER_PAYMENT. Treat it as a breakdown card, not a total.

Option B: Change T2.1 formula to `getSummary(period).totalInflow` (all inflows)
and rename to "إجمالي الإيرادات النقدية" to match. Remove T2.3 (OTHER_INCOME) from Section D
since it would already be inside T2.1. Then add a sub-breakdown card for OTHER_INCOME separately.

**Reviewer recommendation: Option A** — More transparent breakdown for store owner.

---

### F2 — MEDIUM — Provider/Data Coupling Conflict

**Location:** Section 10 Provider Strategy vs Section 10 Performance Strategy

**Conflict:** Provider strategy says `dashboardRecentActivityProvider` watches
`dashboardFilterProvider`. Performance section says "Reuse cashLedgerEntriesProvider".
`cashLedgerEntriesProvider` is coupled to `cashLedgerFilterProvider`, not
`dashboardFilterProvider`.

**Impact:** If "reuse cashLedgerEntriesProvider" is implemented literally, the dashboard's
recent activity section will display entries filtered by the CASH LEDGER screen's date
filter — even when the user changes the DASHBOARD's date filter, the recent activity would
not update to match.

**Required resolution:**
Remove the "Reuse cashLedgerEntriesProvider" statement from the performance section.
`dashboardRecentActivityProvider` must call `financialLedgerRepositoryProvider.getEntries()`
directly with the dashboard filter. This is one extra provider and one extra query, not an
expensive operation.

---

### F3 — MEDIUM — Visual Section D Arithmetic Gap

**Location:** Section 7 Visual Sections, Section D

**Section D shows three breakdown cards:**
- المبيعات النقدية (SALE_CASH only)
- المصروفات (EXPENSE only)
- إيرادات أخرى (OTHER_INCOME only)

**Section C shows:**
- إجمالي الوارد (totalInflow = SALE_CASH + CUSTOMER_PAYMENT + OTHER_INCOME)
- إجمالي الصادر (totalOutflow = EXPENSE + PURCHASE_CASH + SUPPLIER_PAYMENT + RETURN_REFUND)

A store owner will compute Section D mentally and compare to Section C:

Inflow check:
Total Inflow = Cash Sales + Other Income + ??? (Customer Payments are invisible)

Outflow check:
Total Outflow = Expenses + ??? (Purchase Cash, Supplier Payments, Returns are invisible)

The missing event types in Section D create unexplained gaps in the arithmetic. A curious
owner will ask: "My inflow is 100,000 but Cash Sales + Other Income = 70,000. Where is 30,000?"

**Required resolution:**
Either:
Option A: Add missing breakdown cards to Section D:
  - Add "تحصيل العملاء" (CUSTOMER_PAYMENT) to the inflow breakdown
  - Add "مشتريات نقدية" (PURCHASE_CASH) and "دفع مورد" (SUPPLIER_PAYMENT) to outflow breakdown

Option B: Remove Section D completely. Show only the totals in Section C plus the
supplementary cards in Section E. Store owner sees totals and can drill into the Cash Ledger
for the full breakdown.

**Reviewer recommendation: Option A** — Adds "تحصيل العملاء" to inflow breakdown and
"مشتريات نقدية" to outflow breakdown. Section D becomes a 5-card row or two sub-rows.

---

### F4 — LOW — KPI Name Inconsistency: Cash Balance Label

**Location:** Section 3 (T1.1) vs Section 5 and Section 7

| Location | Label Used |
|----------|-----------|
| Section 3, T1.1 | الرصيد النقدي الحالي |
| Section 5, Cash Balance Design | الرصيد النقدي التقريبي |
| Section 7, Section A | الرصيد النقدي التقريبي |
| Section 12, Risk table | labels as "تقريبي" |

The document uses TWO different labels for the same KPI.

**Required resolution:**
Choose one label and apply it consistently across all sections.
Reviewer recommendation: **الرصيد النقدي المحسوب** (see Section 3 of this review).

---

### O1 — LOW — Repository Dependency Boundary (Optional Improvement)

The audit does not explicitly state whether dashboard providers call `FinancialLedgerRepository`
directly or whether `FinancialDashboardRepository` wraps it.

The correct pattern (consistent with this codebase) is:
- Providers call repositories directly (never repo-to-repo)
- `dashboardCashFlowProvider` calls BOTH `financialLedgerRepositoryProvider` (for UNION-based KPIs)
  AND `financialDashboardRepositoryProvider` (for sales_invoices and pos_sessions KPIs)
- `dashboardCurrentStateProvider` calls only `financialDashboardRepositoryProvider`

This should be documented in the Phase 5.1 implementation spec, not changed in the audit document.

---

### O2 — LOW — Phase 8 DashboardFilter Granularity Field

The `DashboardFilter` model should include a `granularity` field (day/week/month) with a
default of `month`, even if unused in Phase 5. This avoids a breaking model change in Phase 8
when time-series charts are introduced. The field would be a no-op in Phase 5 queries.

---

## Required Corrections Summary

### F1 — Resolve T2.1 Formula Ambiguity
**Action:** Update Section 3 T2.1 label to "إيرادات المبيعات والتحصيل" to make clear it is
SALE_CASH + CUSTOMER_PAYMENT only. Remove ambiguity with the Formulas Reference.
OR update T2.1 formula to use totalInflow and clarify that OTHER_INCOME is a subset.

### F2 — Remove "Reuse cashLedgerEntriesProvider" Statement
**Action:** Remove the statement from Section 10 Performance Strategy.
Replace with: "dashboardRecentActivityProvider calls financialLedgerRepositoryProvider
.getEntries() directly with DashboardFilter date range and pageSize=10."

### F3 — Complete the Section D Breakdown
**Action:** Add "تحصيل العملاء" (CUSTOMER_PAYMENT events) to the inflow breakdown row.
Add "مشتريات نقدية" (PURCHASE_CASH events) to the outflow breakdown row.
The breakdown cards in Section D must fully account for Section C totals.

### F4 — Standardise Cash Balance Label
**Action:** Replace "الرصيد النقدي الحالي" in Section 3 T1.1 with the chosen label.
Recommended: "الرصيد النقدي المحسوب"
Apply consistently across Sections 3, 4, 5, 7, and 12.

---

## Final Score

| Section | Score |
|---------|-------|
| 1 — Cash vs Profit | 94 / 100 |
| 2 — KPI Label Audit | 87 / 100 |
| 3 — Cash Balance Audit | 91 / 100 |
| 4 — Debt KPI Audit | 98 / 100 |
| 5 — Repository Boundary | 90 / 100 |
| 6 — Provider Architecture | 86 / 100 |
| 7 — Performance | 93 / 100 |
| 8 — Future Compatibility | 95 / 100 |
| 9 — Architecture Gaps | 91 / 100 |

### Overall Architecture Score: 91 / 100

---

## Final Decision

```
+------------------------------------------------------+
|                                                      |
|             CONDITIONAL GO  (91/100)                 |
|                                                      |
|   The architecture is fundamentally sound.          |
|   Four corrections are required before Phase 5.1.   |
|                                                      |
|   F1: Resolve T2.1 formula ambiguity                |
|   F2: Remove cashLedgerEntriesProvider coupling     |
|   F3: Complete Section D breakdown arithmetic       |
|   F4: Standardise cash balance KPI label            |
|                                                      |
|   All corrections are specification-layer only.     |
|   No code changes required.                         |
|                                                      |
|   After corrections: GO for Phase 5.1.              |
|                                                      |
+------------------------------------------------------+
```

---

## Corrections Checklist

Before Phase 5.1 implementation begins, confirm:

- [ ] F1: T2.1 label updated. Developer formula reference is unambiguous.
- [ ] F2: "Reuse cashLedgerEntriesProvider" statement removed. dashboardRecentActivityProvider spec is clear.
- [ ] F3: Section D breakdown cards include تحصيل العملاء and مشتريات نقدية.
- [ ] F4: Cash balance label standardised to "الرصيد النقدي المحسوب" across all sections.
- [ ] Optional O1: Provider orchestration pattern documented in Phase 5.1 spec.
- [ ] Optional O2: DashboardFilter includes granularity field (no-op for Phase 5).