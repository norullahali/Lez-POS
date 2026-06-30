# Phase 5.3 — Financial Dashboard
# Architecture Audit — Analytics & Charts Foundation
# Date: 2026-06-26

---

## Executive Summary

Phase 5.3 introduces **read-only analytical visualization** into the Financial
Dashboard without altering the completed Phase 5.1 data layer contracts or the
Phase 5.2 UI section boundaries.

The recommended architecture adds **two mandatory cash-ledger-derived charts**
that complement — but do not duplicate — existing scalar KPIs:

1. **Cash Flow Trend** — inflow vs outflow over time (temporal view)
2. **Cash Flow Composition** — breakdown by ledger event type (structural view)

Both charts consume **new time-series / breakdown queries on the existing Cash
Ledger UNION** via `FinancialLedgerRepository`, exposed through **one new
dashboard provider** and **one new analytics section widget** that reuses the
Reports chart stack (`ReportChartCard`, `ReportChartConfig`, `ReportAsyncBody`).

Accrual sales trends, drill-down, granularity UI controls, and cross-module
analytics (Inventory, Executive, Branch) are explicitly **out of scope** for
Phase 5.3 foundation.

**Architecture Readiness Score: 95 / 100**
**Final Recommendation: READY FOR IMPLEMENTATION**

Minor pre-coding revisions required (documented in Section 12). No fundamental
redesign needed.

---

## Architecture Overview

```
FinancialDashboardScreen (no ref.watch)
  |
  +-- DashboardFilterSection          -> dashboardFilterProvider
  +-- DashboardCashFlowSection        -> dashboardCashFlowProvider
  +-- DashboardAnalyticsSection [NEW] -> dashboardCashAnalyticsProvider [NEW]
  +-- DashboardSupplementaryKpiSection -> dashboardCurrentStateProvider
  +-- DashboardRecentActivitySection  -> dashboardRecentActivityProvider

dashboardCashAnalyticsProvider
  | watches: dashboardFilterProvider
  | reads:   financialLedgerRepositoryProvider
  | returns: FinancialDashboardCashAnalytics (immutable model)
  |
  v
FinancialLedgerRepository [EXTEND — read-only]
  +-- getCashFlowTimeSeries(filter, granularity)
  +-- getCashFlowBreakdownByEventType(filter)

FinancialDashboardRepository — UNCHANGED (no chart SQL here)

Presentation mapping (UI layer only):
  FinancialDashboardCashAnalytics -> ReportChartConfig (x2)
  ReportChartCard + ReportAsyncBody (reuse Reports module)
```

**Layer rule preserved:** UI -> Provider -> Repository -> Database. No SQL in
widgets. No repository access from widgets.

---

## Section 1 — Functional Scope

### Mandatory (Phase 5.3)

| ID | Feature | Rationale |
|---|---|---|
| M1 | Cash Flow Trend chart (inflow + outflow series over time) | KPIs show period totals only; chart shows **when** cash moved |
| M2 | Cash Flow Composition chart (ledger event-type breakdown) | KPIs show aggregates; chart shows **composition** by event type |
| M3 | Data models for chart-ready series | Decouple SQL from presentation |
| M4 | Repository methods on `FinancialLedgerRepository` | Single source of truth — Cash Ledger UNION |
| M5 | `dashboardCashAnalyticsProvider` | Isolated provider ownership for analytics section |
| M6 | `DashboardAnalyticsSection` widget | One section, one watch, read-only |
| M7 | Screen invalidation wiring in `_refresh()` | Consistent with 5.2 sections |
| M8 | Reuse `ReportChartCard` / `ReportAsyncBody` | No new chart framework |

### Optional (Phase 5.3.x follow-ups — not blocking foundation)

| ID | Feature | Defer reason |
|---|---|---|
| O1 | Auto granularity SegmentedButton in filter bar | UX addition; foundation uses auto-bucket resolution |
| O2 | Accrual sales trend (from `sales_invoices`) | Overlaps `totalSales` KPI semantics; needs distinct labeling |
| O3 | Chart point tooltips with Arabic date formatting polish | Cosmetic |
| O4 | Export chart data to CSV | Phase 8 / reports scope |

### Future phases (explicitly NOT Phase 5.3)

| Feature | Target phase |
|---|---|
| Chart drill-down / navigation | Phase 5.4+ or Reports integration |
| Period-over-period KPI trend badges | Separate provider; not charts foundation |
| P&L / margin charts | Phase 6 |
| Session breakdown table | Phase 7 |
| Real-time StreamProvider refresh | Phase 8 |
| Executive / Inventory / Purchase / Branch dashboards | Separate feature modules reusing chart **pattern** |
| Multi-branch filter dimension | Phase 8+ |

### Scope boundary statement

Phase 5.3 adds **visualization of existing cash-ledger semantics**. It does **not**
add new KPIs, new scalar calculations, filter UI redesign, or drill-down behavior.

---

## Section 2 — Chart Architecture

### Chart count: **2 mandatory**

| Chart | Type | Title (proposed AR) | Answers |
|---|---|---|---|
| **C1 — Cash Flow Trend** | `ReportChartType.trend` or `line` | اتجاه التدفق النقدي | How did inflow/outflow vary across the selected period? |
| **C2 — Cash Flow Composition** | `ReportChartType.pie` or `bar` | تركيب الحركات النقدية | Which ledger event types drove inflows/outflows? |

### Relationship to existing KPIs (anti-duplication)

| Existing KPI (scalar) | Chart relationship | Duplication risk |
|---|---|---|
| `totalInflow` / `totalOutflow` / `netCashFlow` | Trend chart **sums to** these totals per period | **LOW** — scalar vs temporal |
| `cashBalance` (all-time) | **Not charted** in 5.3 | None — all-time balance is not period-series |
| `totalSales` (accrual) | **Not charted** in mandatory scope | **HIGH if added** — defer to optional |
| `cardSales`, debts, `sessionDifference` | **Not charted** in 5.3 | None — different data sources |

**Rule:** Phase 5.3 charts use **Cash Ledger UNION only**. Supplementary KPI
fields from `FinancialDashboardRepository` remain scalar-only until a future
phase justifies accrual time-series with explicit labeling.

### Chart presentation rules

- Read-only: `onPointTap: null` (no drill-down in 5.3)
- Y-axis: `AnalyticsFormatters.money` via `yAxisFormatter`
- Empty buckets: show zero, not omit (consistent totals)
- Legend: Arabic labels from `CashLedgerEventType.labelAr` for composition chart

---

## Section 3 — Data Ownership

### Chart C1 — Cash Flow Trend

| Layer | Owner | Artifact |
|---|---|---|
| Provider | `dashboardCashAnalyticsProvider` | orchestrates fetch |
| Repository | `FinancialLedgerRepository` | `getCashFlowTimeSeries(...)` |
| Model | `FinancialDashboardCashFlowTimeSeries` | bucketed inflow/outflow points |
| SQL | Inside ledger repo only | `GROUP BY` date bucket on `_unionSql` |

### Chart C2 — Cash Flow Composition

| Layer | Owner | Artifact |
|---|---|---|
| Provider | same provider (combined fetch) | parallel repo calls |
| Repository | `FinancialLedgerRepository` | `getCashFlowBreakdownByEventType(...)` |
| Model | `FinancialDashboardCashFlowBreakdown` | slices per `CashLedgerEventType` |
| SQL | Inside ledger repo only | `GROUP BY event_type` on `_unionSql` |

### Existing providers — sufficiency assessment

| Provider | Sufficient for charts? | Verdict |
|---|---|---|
| `dashboardCashFlowProvider` | No — returns scalar summary only | **Do not extend** for charts |
| `dashboardCurrentStateProvider` | No — supplementary/debt scalars | **Do not reuse** |
| `dashboardRecentActivityProvider` | No — paginated raw events | **Do not reuse** |
| `dashboardSummaryProvider` | No — composite scalars | **Do not reuse** |

### New provider justification

**One new provider is justified:** `dashboardCashAnalyticsProvider`

- Returns composite `FinancialDashboardCashAnalytics` (time series + breakdown)
- Mirrors Phase 5.1 pattern: `dashboardCurrentStateProvider` combines two repo
  calls under one watch boundary
- Avoids two sections watching overlapping filter/repo state
- Keeps section rule: **one section -> one provider watch**

### Repository strategy

| Repository | Phase 5.3 action |
|---|---|
| `FinancialLedgerRepository` | **EXTEND** — add read-only aggregation methods |
| `FinancialDashboardRepository` | **NO CHANGE** |
| `AdvancedAnalyticsRepository` | **DO NOT USE** — wrong module boundary |

**Critical rule:** New SQL wraps the existing `_unionSql` subquery. Do not
duplicate UNION definitions. Do not query operational tables directly for
cash movement charts.

---

## Section 4 — Filter Architecture

### Existing filter — sufficient for Phase 5.3

| Mechanism | Status |
|---|---|
| `dashboardFilterProvider` | PASS — all dashboard sections already watch indirectly |
| `ReportFilterModel` presets | PASS — today/week/month/custom |
| Custom date range | PASS — via `dateFilter.resolveRange()` |
| `DashboardFilter.granularity` | **EXISTS but UI no-op** — activate in provider logic only |

### Granularity strategy (Phase 5.3 — no new filter UI)

Auto-resolve bucket granularity from selected range **duration** inside
`dashboardCashAnalyticsProvider` (or a pure helper):

| Range length | Bucket |
|---|---|
| <= 31 days | `DashboardGranularity.day` |
| <= 120 days | `DashboardGranularity.week` |
| > 120 days | `DashboardGranularity.month` |

Cap bucket count (recommend max **31 daily / 26 weekly / 12 monthly** points).
Truncate or merge overflow buckets server-side in repository.

**Do not** add granularity SegmentedButton in Phase 5.3 foundation — optional
follow-up only.

### Filter reactivity

When `dashboardFilterProvider` changes:

- `dashboardCashAnalyticsProvider` auto-refetches (watches filter)
- Analytics section rebuilds independently
- `dashboardCashBalanceProvider` remains uncoupled (45 s cache, all-time)

---

## Section 5 — Provider Architecture

### Ownership matrix (target state after 5.3)

| Widget | Provider watched | Invalidated by screen refresh |
|---|---|---|
| `FinancialDashboardScreen` | **NONE** | orchestrates only |
| `DashboardFilterSection` | `dashboardFilterProvider` | N/A |
| `DashboardCashFlowSection` | `dashboardCashFlowProvider` | YES |
| `DashboardAnalyticsSection` | `dashboardCashAnalyticsProvider` | YES (add) |
| `DashboardSupplementaryKpiSection` | `dashboardCurrentStateProvider` | YES |
| `DashboardRecentActivitySection` | `dashboardRecentActivityProvider` | YES |

### Provider implementation sketch (design only)

```dart
final dashboardCashAnalyticsProvider =
    FutureProvider.autoDispose<FinancialDashboardCashAnalytics>((ref) async {
  final filter = ref.watch(dashboardFilterProvider);
  final ledger = ref.read(financialLedgerRepositoryProvider);
  final cashFilter = CashLedgerFilter(dateFilter: filter.dateFilter);
  final granularity = _resolveGranularity(filter.resolvedRange);

  final trendFuture = ledger.getCashFlowTimeSeries(cashFilter, granularity);
  final breakdownFuture = ledger.getCashFlowBreakdownByEventType(cashFilter);

  final results = await Future.wait([trendFuture, breakdownFuture]);
  return FinancialDashboardCashAnalytics(
    timeSeries: results[0] as FinancialDashboardCashFlowTimeSeries,
    breakdown: results[1] as FinancialDashboardCashFlowBreakdown,
  );
});
```

No `ref.watch` on other dashboard data providers — prevents cascade rebuilds.

---

## Section 6 — Performance Strategy

| Concern | Strategy | Classification |
|---|---|---|
| Chart rebuild scope | Single section watch | **LOW** impact |
| SQL cost | Bucket aggregation on filtered UNION | **MEDIUM** for long ranges — mitigate with caps |
| Caching | None in 5.3 (match other period providers) | Acceptable |
| Refresh | Manual invalidate + filter change | Consistent with 5.2 |
| Desktop rendering | `RepaintBoundary` in `ReportChartCard` (existing) | **LOW** |
| Large datasets | Bucket cap + auto granularity | **MEDIUM** mitigated |

**Do not** add keepAlive cache in 5.3. **Do not** migrate to StreamProvider.

### Refresh wiring

Extend `FinancialDashboardScreen._refresh()`:

```dart
ref.invalidate(dashboardCashAnalyticsProvider); // add
```

---

## Section 7 — UI Architecture

### Section placement

Insert **after Cash Flow KPIs, before Supplementary KPIs**:

```
Header
Filter
Cash Flow KPIs          (scalar — period cash)
Analytics Charts [NEW]  (temporal + compositional — period cash)
Supplementary KPIs      (accrual/debt/session — mixed semantics)
Recent Activity         (row-level detail)
```

**Rationale:** Charts explain the cash-flow KPI block immediately above.
Supplementary KPIs use different semantics (accrual sales, current debt) and
should not sit between KPIs and their explanatory charts.

### Section structure (design)

`DashboardAnalyticsSection` (ConsumerWidget):

- Section title: `التحليلات المالية` or `تحليل التدفق النقدي`
- Single `ReportAsyncBody<FinancialDashboardCashAnalytics>`
- `loadingStyle: ReportLoadingStyle.skeletonChart`
- Child: column of two fixed-height chart cards (~320 px each, matching Reports)
- Desktop-first, RTL via existing chart widgets
- No nested scroll beyond parent `SingleChildScrollView`

### Reuse checklist

| Component | Reuse? |
|---|---|
| `ReportChartCard` | YES |
| `ReportChartConfig` / `ReportChartPoint` | YES |
| `ReportAsyncBody` | YES |
| `AnalyticsFormatters` | YES |
| `DashboardKpiTile` | NO — charts, not KPI cards |
| `ReportDrillDownService` | NO — read-only |

---

## Section 8 — Extensibility Plan

### Pattern for future dashboards

Extract a **mapping convention** (not necessarily a shared base class):

```
Repository model  ->  ReportChartConfig  ->  ReportChartCard
```

Financial feature owns domain models + mappers. Reports module owns rendering.

### Future modules (no Phase 5.3 work)

| Module | Reuses from 5.3 |
|---|---|
| Executive Dashboard | Section + provider + chart card pattern |
| Sales Analytics | `ReportChartCard`; own repo/provider |
| Inventory Analytics | Same pattern; inventory repositories |
| Purchase Analytics | Same pattern |
| Branch Analytics | Adds branch dimension to filter model later |

### Phase 8 upgrades (compatible)

- User-selectable `DashboardFilter.granularity` — field already exists
- StreamProvider migration — provider file only
- Chart drill-down via `CashLedgerEventDrillDown` — optional `onPointTap` later

---

## Section 9 — Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| UNION SQL duplication in new queries | **HIGH** | Only extend `_unionSql` in `FinancialLedgerRepository`; code review gate |
| Chart totals diverge from KPI scalars | **MEDIUM** | Unit-test: sum(buckets) == `getSummary()` for same filter |
| Accrual sales chart vs `totalSales` KPI confusion | **MEDIUM** | Exclude from mandatory scope; mandatory charts = ledger only |
| Provider proliferation | **LOW** | One composite provider per analytics section |
| Repository leakage into UI | **LOW** | Enforce import lint / review checklist |
| UI complexity (screen length) | **LOW** | Two charts in one section; fixed heights |
| Performance on wide date ranges | **MEDIUM** | Auto granularity + bucket caps |
| `DashboardGranularity` comment says "Phase 8" | **LOW** | Update comment when implementing 5.3 |

---

## Section 10 — Implementation Roadmap

### Phase 5.3.1 — Data Foundation (no UI)

| Item | Detail |
|---|---|
| **Goal** | Chart-ready models, repository methods, provider |
| **Files create** | `financial_dashboard_cash_analytics.dart` (model), extend `financial_ledger_repository.dart`, extend `dashboard_providers.dart` |
| **Dependencies** | Phase 5.1 ledger UNION, `DashboardFilter`, `CashLedgerFilter` |
| **Review** | SQL wraps `_unionSql`; bucket sum equals summary |
| **Hardening** | Bucket cap helper; parallel fetch |
| **Final audit** | No UI; provider returns valid empty series |

### Phase 5.3.2 — Analytics Section UI

| Item | Detail |
|---|---|
| **Goal** | Read-only chart section on dashboard |
| **Files create** | `dashboard_analytics_section.dart`, `financial_dashboard_chart_mapper.dart` (pure mapping) |
| **Files modify** | `financial_dashboard_screen.dart` (insert section + invalidate) |
| **Dependencies** | 5.3.1 provider, Reports chart widgets |
| **Review** | One watch; no drill-down; RTL; skeleton loading |
| **Hardening** | Verify rebuild isolation; no ConsumerWidget in mapper |
| **Final audit** | GO certification; zero regression on 5.2 sections |

### Optional Phase 5.3.3 — Granularity UI (defer)

| Item | Detail |
|---|---|
| **Goal** | User-controlled day/week/month in filter bar |
| **Risk** | Filter UI change — separate review |

---

## Section 11 — Compatibility with Completed Phases

| Phase | Compatibility |
|---|---|
| 5.1 Data layer | **EXTEND ledger repo only** — no breaking model changes |
| 5.2.1 Shell | Screen invalidate-only pattern preserved |
| 5.2.2 Cash Flow KPIs | Unchanged; charts placed adjacent |
| 5.2.3.1 Recent Activity | Unchanged |
| 5.2.3.2 Drill-down | Independent; charts remain non-interactive |
| 5.2.4 Supplementary KPIs | Unchanged |

No modifications required to completed phase files except:

- `financial_dashboard_screen.dart` — add section + invalidate (5.3.2)
- `dashboard_providers.dart` — add provider (5.3.1)
- `financial_ledger_repository.dart` — add methods (5.3.1)

---

## Section 12 — Pre-Implementation Revisions (Minor)

Before coding begins, confirm:

1. **Update `DashboardFilter.granularity` doc comment** from "Phase 8 no-op" to
   "auto-resolved in Phase 5.3 analytics provider; UI control deferred."
2. **Confirm Arabic section/chart titles** with product owner (architecture
   proposes labels only).
3. **Add repository-level test** asserting trend bucket sums match `getSummary()`.

These are documentation / test gates — not architecture redesign.

---

## Final Recommendation

### READY FOR IMPLEMENTATION

The proposed Phase 5.3 architecture:

- Respects UI -> Provider -> Repository -> Database layering
- Preserves Phase 5.2 section ownership rules
- Reuses Reports chart infrastructure (no new chart library)
- Avoids duplicating scalar KPI information
- Extends the Cash Ledger UNION as the single cash-movement source of truth
- Supports future executive/module dashboards via pattern reuse

**Start with Phase 5.3.1 (data foundation) before any widget work.**

No fundamental revision required before coding begins.

---

## Explicit Reuse Summary

| Existing asset | Phase 5.3 use |
|---|---|
| `FinancialLedgerRepository._unionSql` | Wrap for GROUP BY queries |
| `dashboardFilterProvider` | Watch for period + auto granularity |
| `ReportChartCard` / `ReportChartConfig` | Render charts |
| `ReportAsyncBody` | Async boundary |
| `AnalyticsFormatters` | Money formatting on axes |
| `CashLedgerEventType` | Composition chart labels/colors |
| `DashboardGranularity` enum | Bucket selection (provider-side) |

**Do not create:** new chart rendering library, new filter provider, new
dashboard repository, or coupling to `AdvancedAnalyticsRepository`.