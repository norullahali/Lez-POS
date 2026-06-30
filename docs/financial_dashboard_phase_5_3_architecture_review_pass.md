# Phase 5.3 — Financial Dashboard
# Architecture Review Pass — Analytics & Charts Foundation
# Date: 2026-06-26

---

## Executive Summary

The proposed Phase 5.3 architecture was reviewed against layer separation,
Cash Ledger ownership, provider boundaries, financial correctness, filter
compatibility, extensibility, and the implementation roadmap.

The design is **architecturally sound**, **financially correct** for mandatory
scope (cash-ledger-derived charts only), **scalable** via bucket caps and
section-isolated providers, and **reusable** through the existing Reports chart
stack without new framework dependencies.

No measurable architectural flaw requiring redesign was found. Minor
pre-implementation clarifications are documented below; none block coding.

**Architecture Readiness Score: 96 / 100**
**Final Decision: READY WITH MINOR ADJUSTMENTS**

**Phase 5.3 architecture is approved for implementation.**

Begin with Phase 5.3.1 (data foundation) as specified.

---

## Section 1 — Architecture Review

| Rule | Verdict | Evidence |
|---|---|---|
| UI -> Provider -> Repository -> Database | **PASS** | Audit diagram; matches Phase 5.1–5.2 pattern |
| No repository access from widgets | **PASS** | Section watches provider only; mapper is pure presentation |
| No SQL outside repositories | **PASS** | New SQL confined to `FinancialLedgerRepository` extension |
| No layer violations | **PASS** | `FinancialDashboardRepository` unchanged |
| Compatible with Phases 5.1–5.2.4 | **PASS** | Additive extension only |

**Verdict:** Layering is preserved. No violations identified.

---

## Section 2 — Cash Ledger Ownership Review

### Decision under review

All mandatory chart data originates from `FinancialLedgerRepository` wrapping
the existing `_unionSql` constant.

| Criterion | Verdict |
|---|---|
| Single source of truth for cash movement | **PASS** |
| No duplicated UNION definition | **PASS** — extend subquery, do not copy |
| No duplicated financial calculations in UI/provider | **PASS** |
| Consistency with `getSummary()` / Cash Ledger screen | **PASS** — same UNION semantics |

### Alternative architectures considered

| Alternative | Assessment |
|---|---|
| Query operational tables directly for trend | **REJECTED** — bypasses double-count guards; HIGH correctness risk |
| Use `FinancialDashboardRepository` | **REJECTED** — accrual/session SQL; wrong semantics for cash charts |
| Use `AdvancedAnalyticsRepository` | **REJECTED** — cross-module coupling; inventory/sales domain |
| Split UNION into shared SQL file | **NOT REQUIRED** — `_unionSql` already centralized; moving it adds churn without benefit |

**Conclusion:** `FinancialLedgerRepository` + `_unionSql` is the **correct and
optimal** ownership decision. No alternative improves correctness.

### Pre-implementation clarification (minor)

New aggregation methods **must reuse** `_buildWhereClause(filter, start, end)`
already used by `getSummary()` and `getEntries()` so chart data and KPI scalars
apply identical date/filter predicates.

---

## Section 3 — Provider Review

### Proposal: `dashboardCashAnalyticsProvider`

| Criterion | Verdict |
|---|---|
| Single provider ownership for analytics section | **PASS** |
| One `ref.watch` in section | **PASS** |
| One analytics section | **PASS** |
| No unnecessary fragmentation | **PASS** |

### Is one provider sufficient?

**YES.** Justification:

- Trend and breakdown share the same filter and repository domain
- Parallel fetch via `Future.wait` matches `dashboardCurrentStateProvider`
  (debt + supplementary under one watch)
- Splitting into `dashboardCashFlowTrendProvider` + `dashboardCashFlowBreakdownProvider`
  would create two watches for one visual section or require a parent aggregator —
  adds complexity without measurable benefit

### Provider isolation

| Rule | Verdict |
|---|---|
| Does not `ref.watch` other dashboard data providers | **PASS** |
| Does not cascade-rebuild cash flow / supplementary sections | **PASS** |
| Screen remains invalidate-only | **PASS** |

**Do not split** the analytics provider unless partial-loading UX becomes a
hard requirement (not in Phase 5.3 scope).

---

## Section 4 — Model Review

### Proposed: `FinancialDashboardCashAnalytics`

Recommended structure (design approval):

```
FinancialDashboardCashAnalytics          (composite, immutable)
  +-- FinancialDashboardCashFlowTimeSeries
  |     +-- List<FinancialDashboardTimeSeriesBucket>  (label, inflow, outflow)
  +-- FinancialDashboardCashFlowBreakdown
        +-- List<FinancialDashboardBreakdownSlice>    (eventType, amount, direction)
```

| Rule | Verdict |
|---|---|
| Immutable data classes | **PASS** — follow `FinancialDashboardCashFlow` pattern |
| Read-only / pure data | **PASS** |
| No helper methods with business logic | **PASS** — `copyWith`, `==`, `hashCode` only |
| No formatting | **PASS** — formatting belongs in `financial_dashboard_chart_mapper.dart` |
| No calculations in model | **PASS** — net per bucket computed in **repository**, not model |

### Separation recommendation

| Concern | Location |
|---|---|
| SQL aggregation | `FinancialLedgerRepository` |
| Immutable transport models | `models/financial_dashboard_cash_analytics.dart` |
| `ReportChartConfig` mapping | `financial_dashboard_chart_mapper.dart` (UI layer) |
| Axis/tooltip formatting | Mapper uses `AnalyticsFormatters` |

**No model split beyond composite + sub-types is required.**

---

## Section 5 — Chart Architecture Review

### Responsibilities (architectural only)

| Chart | Responsibility | KPI relationship |
|---|---|---|
| **Trend** | Temporal distribution of inflow/outflow | **Visualizes** period totals from `dashboardCashFlowProvider`; sum(buckets) must equal scalars |
| **Composition** | Structural split by `CashLedgerEventType` | **Decomposes** inflow/outflow into event categories; does not replace scalar KPI cards |

| Anti-duplication rule | Verdict |
|---|---|
| Does not re-display `totalInflow`/`totalOutflow`/`netCashFlow` as numbers | **PASS** — chart only |
| Does not chart `totalSales` (accrual) in mandatory scope | **PASS** |
| Does not chart `cashBalance` (all-time) | **PASS** |
| Read-only; no drill-down in 5.3 | **PASS** |

### Minor clarification for 5.3.2

Document whether composition chart presents:

- **Option A (recommended):** one chart with slices per event type, amount always positive, color/icon by inflow vs outflow direction; or
- **Option B:** separate inflow/outflow composition views

This is a **presentation responsibility** decision for the mapper, not a
data-layer change. Default: Option A using `CashLedgerEventType.isInflow`.

---

## Section 6 — Filter Review

| Mechanism | Verdict |
|---|---|
| `dashboardFilterProvider` as single filter source | **PASS** |
| No new filter provider | **PASS** |
| Presets + custom dates via `ReportFilterModel` | **PASS** |
| Auto bucket strategy from range duration | **PASS** for 5.3 foundation |
| `DashboardGranularity` enum reuse | **PASS** |

### Phase 8 / 5.3.3 compatibility

| Topic | Verdict |
|---|---|
| User-selectable granularity later | **COMPATIBLE** — field exists on `DashboardFilter` |
| Auto-resolve in 5.3 | **PASS** — compute in provider when `granularity` UI is inactive |
| Future conflict | **NONE** — 5.3.3 should switch provider to `filter.granularity` when user override is set, falling back to auto-resolve when default |

Update stale "Phase 8 no-op" comment on `DashboardFilter.granularity` during 5.3.1
(as audit Section 12 specifies).

---

## Section 7 — Repository Review

| Repository | Phase 5.3 action | Verdict |
|---|---|---|
| `FinancialLedgerRepository` | Extend with 2 read-only methods | **PASS** — correct owner |
| `FinancialDashboardRepository` | No change | **PASS** |
| `AdvancedAnalyticsRepository` | Not used | **PASS** |

### Boundary cleanliness

- Cash movement analytics -> `FinancialLedgerRepository`
- Accrual/debt/session scalars -> `FinancialDashboardRepository` (unchanged)
- No repository-to-repository calls introduced

**Verdict:** Repository boundaries remain clean.

---

## Section 8 — Extensibility Review

| Future capability | Supported without redesign? | Notes |
|---|---|---|
| Executive Dashboard | **YES** | Reuse section + provider + chart mapper pattern |
| Inventory Analytics | **YES** | Own repo/provider; same `ReportChartCard` |
| Sales Analytics | **YES** | Separate from ledger charts; own data owner |
| Purchase Analytics | **YES** | Same pattern |
| Branch Analytics | **PARTIAL** | Requires branch dimension on filter model later; chart pattern unchanged |

### Possible future bottlenecks (not blockers)

| Bottleneck | Severity | When |
|---|---|---|
| `FinancialLedgerRepository` file size growth | LOW | Many more aggregation methods — extract private query helpers if needed |
| Triple ledger SQL on filter change (summary + trend + breakdown) | MEDIUM | Acceptable in 5.3; optional combined query only if profiling demands |
| Single scroll column length with two charts | LOW | Desktop scroll already used |

No redesign required for extensibility.

---

## Section 9 — Risk Review

| Risk (from audit) | Severity | Mitigation sufficient? | Review notes |
|---|---|---|---|
| UNION SQL duplication | **HIGH** | **YES** | Code review + grep gate on `_unionSql` |
| Chart totals != KPI scalars | **MEDIUM** | **YES** | Repository test: sum(buckets) == `getSummary()` |
| Accrual sales chart confusion | **MEDIUM** | **YES** | Excluded from mandatory scope |
| Provider proliferation | **LOW** | **YES** | Single composite provider |
| Repository leakage to UI | **LOW** | **YES** | Section pattern enforced |
| UI complexity | **LOW** | **YES** | One section, two charts |
| Wide date range performance | **MEDIUM** | **YES** | Auto granularity + bucket caps |
| Stale granularity comment | **LOW** | **YES** | Doc update in 5.3.1 |

### Additional risks identified in review

| Risk | Severity | Mitigation |
|---|---|---|
| Filter predicate drift (new SQL omits `_buildWhereClause`) | **MEDIUM** | Mandate reuse in 5.3.1 implementation spec |
| Composition chart direction semantics | **LOW** | Map colors from `CashLedgerEventType.isInflow` in mapper |
| Parallel ledger load on filter change | **LOW** | Acceptable; same pattern as multiple dashboard sections today |

No **HIGH** unmitigated risks remain.

---

## Section 10 — Implementation Roadmap Review

### Proposed sequence

```
5.3.1 Data foundation (models, repo, provider)
   |
   v
5.3.2 Analytics section UI (mapper, section, screen wiring)
   |
   v
5.3.3 Granularity UI (optional, deferred)
```

| Phase | Dependencies correct? | Reorder needed? |
|---|---|---|
| 5.3.1 | **YES** — requires Phase 5.1 UNION only | **NO** |
| 5.3.2 | **YES** — requires 5.3.1 provider + models | **NO** |
| 5.3.3 | **YES** — requires 5.3.1 provider granularity hook | **NO** |

**Verdict:** Roadmap order is correct. Do not implement UI before provider/repository validation.

### Review / hardening / audit gates (approved)

| Sub-phase | Gate |
|---|---|
| 5.3.1 | Review: SQL wraps `_unionSql`; test bucket-sum == summary |
| 5.3.1 | Hardening: bucket cap helper extraction if needed |
| 5.3.1 | Audit: provider returns empty series safely |
| 5.3.2 | Review: one watch, no drill-down, ReportAsyncBody |
| 5.3.2 | Final audit: zero regression on 5.2 sections |

---

## Minor Adjustments Before Coding (Not Redesign)

| ID | Adjustment | Phase |
|---|---|---|
| A1 | Reuse `_buildWhereClause` in all new ledger aggregations | 5.3.1 |
| A2 | Update `DashboardFilter.granularity` comment | 5.3.1 |
| A3 | Add repository test: trend buckets sum == `getSummary()` | 5.3.1 |
| A4 | Document composition chart inflow/outflow presentation rule in mapper | 5.3.2 |
| A5 | Confirm Arabic section/chart titles with product owner | 5.3.2 |

---

## Architecture Readiness Score Breakdown

| Category | Score | Notes |
|---|---|---|
| Layer separation | 20/20 | |
| Cash Ledger ownership | 20/20 | |
| Provider architecture | 19/20 | Triple parallel ledger query acceptable |
| Model purity | 20/20 | |
| Chart/KPI anti-duplication | 19/20 | Mandatory scope correctly bounded |
| Filter / extensibility | 18/20 | Granularity comment stale until 5.3.1 |
| Risk mitigation | 20/20 | |
| Roadmap | 20/20 | |

**Total: 96 / 100**

---

## Final Decision

### READY WITH MINOR ADJUSTMENTS

The proposed architecture requires **no redesign**. Pre-implementation
clarifications (A1–A5) are documentation, test, and mapping rules — not
structural changes.

**Phase 5.3 architecture is approved for implementation.**

---

## Explicit Confirmations

| Statement | Confirmed |
|---|---|
| UI -> Provider -> Repository -> Database preserved | YES |
| `_unionSql` remains single source of truth | YES |
| One `dashboardCashAnalyticsProvider` is sufficient | YES |
| Models remain pure immutable data | YES |
| Charts visualize KPIs, do not duplicate scalar cards | YES |
| `FinancialDashboardRepository` unchanged | YES |
| No provider split recommended | YES |
| No `_unionSql` duplication recommended | YES |
| Implementation may begin with 5.3.1 | YES |