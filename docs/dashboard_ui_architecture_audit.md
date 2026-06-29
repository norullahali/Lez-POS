# Phase 5.2 — Financial Dashboard UI
# Architecture & Screen Design Audit
# Pre-Implementation
# Date: 2026-06-26

---

## Executive Summary

The Phase 5.1 KPI data layer is complete and audited (97/100 GO).
All dashboard providers, models, and repository methods are production-ready.

The existing widget infrastructure (ReportMetricCard, ReportMetricGrid,
ReportAsyncBody, ReportFilterBar, AnalyticsPermissionGate, AnalyticsFormatters)
provides a complete, battle-tested foundation. Phase 5.2 introduces zero new
framework dependencies and requires zero architecture changes.

All KPIs required by the dashboard UI already exist in the Phase 5.1 data layer.
No missing fields were identified.

**Readiness Score: 96 / 100**
**Final Decision: GO**

---

## Section 1 — Data Layer Review

### Available KPIs (Phase 5.1 confirmed)

| Provider | Fields | Period |
|---|---|---|
| `dashboardCashFlowProvider` | totalInflow, totalOutflow, netCashFlow | Filtered by dashboardFilter |
| `dashboardCashBalanceProvider` | cashBalance (double) | All-time (cached 45 s) |
| `dashboardCurrentStateProvider` | customerDebt, supplierDebt, totalSales, cardSales, sessionDifference | Debt: always current; others: filtered |
| `dashboardSummaryProvider` | Composite of both above + generatedAt | — |
| `dashboardRecentActivityProvider` | List<CashLedgerEvent>, max 10, sorted descending | Filtered by dashboardFilter |

### UI-only Information Check

| Required in UI | Source | Available? |
|---|---|---|
| Cash balance (all-time) | `dashboardCashBalanceProvider` | YES |
| Period inflow | `dashboardCashFlowProvider.totalInflow` | YES |
| Period outflow | `dashboardCashFlowProvider.totalOutflow` | YES |
| Period net | `dashboardCashFlowProvider.netCashFlow` | YES |
| Customer debt | `dashboardCurrentStateProvider.customerDebt` | YES |
| Supplier debt | `dashboardCurrentStateProvider.supplierDebt` | YES |
| Gross sales | `dashboardCurrentStateProvider.totalSales` | YES |
| Card sales | `dashboardCurrentStateProvider.cardSales` | YES |
| Session discrepancy | `dashboardCurrentStateProvider.sessionDifference` | YES |
| Recent activity (10 rows) | `dashboardRecentActivityProvider` | YES |
| Date filter control | `dashboardFilterProvider` | YES |
| Snapshot timestamp | `dashboardSummaryProvider.generatedAt` | YES |

**No missing UI-only information. All 12 required data points are present.**

---

## Section 2 — Recommended Screen Layout

### Design principles

- RTL-first: CrossAxisAlignment.start = right edge on Arabic text
- Desktop-first: designed for 1024–1920 px width range
- Vertical scroll: the screen scrolls as a whole (not split panels)
- No horizontal scroll in KPI sections
- Consistent 24 px outer padding (matches Cash Ledger screen)
- All sections separated by 12–16 px gaps (matches existing screens)

### Layout specification (top to bottom)

```
Padding(24 px all sides)
  Column(CrossAxisAlignment.stretch)
    │
    ├─ [A] HEADER                          height: ~60 px
    │      Icon  |  Title + Subtitle  |  READ-ONLY badge
    │
    ├─ SizedBox(height: 16)
    │
    ├─ [B] FILTER BAR                      height: ~52 px (wraps if narrow)
    │      ReportFilterBar (preset chips + custom range + refresh)
    │      No export button. No event type selector. No search.
    │
    ├─ SizedBox(height: 16)
    │
    ├─ [C] SECTION LABEL — "التدفق النقدي"   height: ~20 px
    │
    ├─ SizedBox(height: 8)
    │
    ├─ [D] CASH FLOW KPI ROW               height: ~100 px
    │      4 cards in a Row, each Expanded
    │      [الرصيد النقدي] [النقد الوارد] [النقد الصادر] [صافي التدفق]
    │      Watched by: dashboardCashFlowProvider (wraps dashboardCashBalanceProvider)
    │
    ├─ SizedBox(height: 16)
    │
    ├─ [E] SECTION LABEL — "المؤشرات التكميلية"  height: ~20 px
    │
    ├─ SizedBox(height: 8)
    │
    ├─ [F] SUPPLEMENTARY KPI ROW           height: ~88 px
    │      5 cards in a Row, each Expanded
    │      [ذمم العملاء] [ذمم الموردين] [إجمالي المبيعات] [مبيعات الكارت] [فارق الجلسات]
    │      Watched by: dashboardCurrentStateProvider
    │
    ├─ SizedBox(height: 16)
    │
    ├─ [G] SECTION LABEL + "عرض الكل" button  height: ~20 px
    │      "الحركات الأخيرة" label + OutlinedButton "عرض دفتر النقدية"
    │
    ├─ SizedBox(height: 8)
    │
    └─ [H] RECENT ACTIVITY CARD            height: Expanded (fills remaining)
           Mini DataTable: 10 rows max
           Columns: التاريخ | النوع | الوصف | وارد | صادر
           Watched by: dashboardRecentActivityProvider
           Running balance NOT shown (not needed in summary view)
```

### Why this layout?

1. Cash balance appears first — it is the most critical KPI for a store owner.
2. Period KPIs appear together — the user sees the impact of the selected period.
3. Supplementary KPIs appear below — they are context, not primary.
4. Recent activity is at the bottom — it can grow with the screen height.
5. No side-by-side columns — simpler layout, better RTL behavior, easier to maintain.

### Responsive behavior

| Screen width | Behavior |
|---|---|
| < 800 px | Wrap KPI rows — use Wrap instead of Row (or 2x2 grid) |
| 800–1200 px | All sections visible without scroll for most configs |
| > 1200 px | Extra whitespace absorbed by card expansion |

For Phase 5.2, a fixed Row layout is acceptable (desktop-only app).
Responsive wrapping is a Phase 8 enhancement.

---

## Section 3 — KPI Card Design

### Reuse existing infrastructure

The `ReportMetricCard` + `ReportMetricModel` pair already implements:
- Colored icon container (52×52, 12% opacity background)
- Arabic title (bodySmall, textSecondary)
- Value (headlineSmall, w700, textPrimary)
- Optional subtitle
- Optional trend badge

For Section D (Cash Flow), use `_DashboardKpiTile` — a slightly taller variant
of `_CashLedgerKpiTile` that uses the full `ReportMetricCard` padding (20 px),
not the compact 10 px version used in the ledger summary bar.

For Section F (Supplementary), use a compact tile matching the Cash Ledger
`_CashLedgerKpiTile` pattern (10 px padding) since 5 cards need to fit in a row.

### KPI card specifications

#### Section D — Cash Flow KPIs (tall cards, ~100 px height)

| KPI | Arabic title | Icon | Color | Notes |
|---|---|---|---|---|
| cashBalance | الرصيد النقدي المحسوب | `account_balance_rounded` | primary if >= 0, error if < 0 | Subtitle: "منذ البداية" |
| totalInflow | النقد الوارد | `arrow_circle_down_rounded` | success | Subtitle: period label |
| totalOutflow | النقد الصادر | `arrow_circle_up_rounded` | error | Subtitle: period label |
| netCashFlow | صافي التدفق | `sync_alt_rounded` | success if > 0, error if < 0, textSecondary if == 0 | Dynamic color required |

**cashBalance dynamic color rule:**
```
cashBalance >= 0  →  AppColors.primary
cashBalance < 0   →  AppColors.error
```

**netCashFlow dynamic color rule:**
```
netCashFlow > 0   →  AppColors.success
netCashFlow < 0   →  AppColors.error
netCashFlow == 0  →  AppColors.textSecondary
```

Number format: `AnalyticsFormatters.money(value)` — outputs "1,234,567 د.ع"

#### Section F — Supplementary KPIs (compact tiles, ~88 px height)

| KPI | Arabic title | Icon | Static Color | Dynamic Color Rule |
|---|---|---|---|---|
| customerDebt | ذمم العملاء | `person_outline_rounded` | warning | None — always warning |
| supplierDebt | ذمم الموردين | `storefront_outlined` | accent | None — always accent |
| totalSales | إجمالي المبيعات | `shopping_cart_outlined` | info | None — always info |
| cardSales | مبيعات الكارت | `credit_card_rounded` | primaryLight | None |
| sessionDifference | فارق الجلسات | `point_of_sale_rounded` | success if >= 0, error if < 0 | Dynamic required |

**totalSales subtitle:** Always show "شامل الآجل والكارت" in small text below the value.
This is mandatory to prevent misreading as net cash.

**sessionDifference dynamic color rule:**
```
sessionDifference > 0   →  AppColors.success  (overage)
sessionDifference < 0   →  AppColors.error    (shortage)
sessionDifference == 0  →  AppColors.textSecondary
```

**sessionDifference subtitle:** Show "زيادة" if positive, "عجز" if negative, "" if zero.

#### Number formatting rules

| KPI | Format |
|---|---|
| All monetary values | `AnalyticsFormatters.money(value)` — Arabic grouping separator |
| Negative monetary values | Always show with negative sign: "-123,456 د.ع" |
| cashBalance (negative) | Red text: "-123,456 د.ع" |
| Zero values | Show as "0 د.ع" — never hide zero |

---

## Section 4 — Recent Activity Design

### Source

`dashboardRecentActivityProvider` — returns `List<CashLedgerEvent>`, max 10, sorted by
`event_ts DESC`. The provider uses `getEntries()` with `page=0, pageSize=10`.

### Table columns (5 columns — simpler than full Cash Ledger)

| Column | Width | Alignment | Content |
|---|---|---|---|
| التاريخ | ~140 px | Right (RTL default) | `DateFormat('yyyy/MM/dd HH:mm').format(event.timestamp)` |
| النوع | ~120 px | Right | `event.eventType.labelAr` |
| الوصف | flexible | Right | `event.description` — maxLines: 2, ellipsis |
| وارد | ~110 px | numeric | Green text if inflow, "—" if outflow |
| صادر | ~110 px | numeric | Red text if outflow, "—" if inflow |

Running balance column: **NOT shown** in dashboard mini-table.
It adds complexity and is available in the full Cash Ledger screen.

### Row behavior

No `onSelectChanged` drill-down from the dashboard mini-table in Phase 5.2.
A "عرض دفتر النقدية" button in the section header navigates to the full Cash Ledger.
Drill-down from the dashboard is Phase 5.3+ scope.

### Event type color coding

Each row type badge matches the existing Cash Ledger color convention:
```
SALE_CASH, OTHER_INCOME, CUSTOMER_PAYMENT  →  inflow column green
PURCHASE_CASH, SUPPLIER_PAYMENT, EXPENSE, RETURN_REFUND  →  outflow column red
```

### States

| State | Widget |
|---|---|
| Loading (first load) | `ReportLoadingStyle.spinner` inside `ReportAsyncBody` |
| Loading (filter change, has previous data) | `ReportAsyncBody.keepPreviousData = true` fades and overlays spinner |
| Empty | `ReportTableEmptyState(message: "لا توجد حركات في الفترة المحددة", icon: Icons.account_balance_wallet_outlined)` |
| Error | `ReportErrorView(message: "خطأ في تحميل الحركات", onRetry: _refresh)` |
| Data | Mini DataTable, no pagination |

### Maximum rows

10 rows. No pagination. Fixed by `dashboardRecentActivityProvider` (pageSize: 10).
The section header must say "آخر 10 حركات" to set user expectations.

---

## Section 5 — Filter UX

### Component

Reuse existing `ReportFilterBar` with these configuration flags:
```dart
ReportFilterBar(
  filter: filter.dateFilter,
  onFilterChanged: (f) => ref.read(dashboardFilterProvider.notifier).setDateFilter(f),
  mode: ReportFilterBarMode.dateRange,
  onRefresh: _refresh,
  showExport: false,   // dashboard has no export
)
```

### Preset chips (all standard presets available)

اليوم | أمس | هذا الأسبوع | هذا الشهر (default) | هذه السنة | مخصص

### Custom date range

Activated by tapping "مخصص" chip — shows date range picker dialog.
Existing `ReportFilterBar._buildRangePicker()` handles this.

### Reset button

Placed inside the filter bar — call `dashboardFilterProvider.notifier.reset()`.
Resets to `thisMonth` preset.

OR use the existing `ReportFilterBar.onRefresh` to invalidate providers only,
and add a separate "إعادة تعيين" OutlinedButton next to the filter bar.

### Filter position

Filter bar placed immediately below the header, above all KPI sections.
This mirrors the Cash Ledger screen structure and user expectation.

### cashBalance filter behavior

`cashBalance` comes from `dashboardCashBalanceProvider` which does NOT
watch `dashboardFilterProvider`. Changing the date filter does NOT update
the cash balance. This is correct and intended.

**The dashboard MUST include a subtle note below the cashBalance card:**
"الرصيد التراكمي — لا يتأثر بالفترة المحددة"
This prevents user confusion when they change the date filter and see
all KPIs update except cashBalance.

### Future granularity support (Phase 8)

`DashboardFilter.granularity` field already exists (day/week/month enum).
Phase 5.2 does NOT show a granularity selector — the field is no-op in Phase 5.
Phase 8 adds a granularity SegmentedButton below the preset chips.
No API changes are required for that addition.

---

## Section 6 — Performance Review

### Widget rebuild analysis

Split into 4 independent `ConsumerWidget` subwidgets to isolate rebuild scope:

```
DashboardScreen (ConsumerStatefulWidget)
├── _DashboardFilterSection (ConsumerWidget)
│     └── watches: dashboardFilterProvider
│     └── rebuilds when: date filter changes
│
├── _DashboardCashFlowSection (ConsumerWidget)
│     └── watches: dashboardCashFlowProvider
│     └── rebuilds when: filter changes or cashBalance cache expires
│
├── _DashboardCurrentStateSection (ConsumerWidget)
│     └── watches: dashboardCurrentStateProvider
│     └── rebuilds when: filter changes
│
└── _DashboardRecentActivitySection (ConsumerWidget)
      └── watches: dashboardRecentActivityProvider
      └── rebuilds when: filter changes
```

**Do NOT use `dashboardSummaryProvider` as the sole data source.**
Watching it means the entire screen waits for the slowest sub-provider.
Independent sub-providers allow sections to render as they resolve.

### Const widget optimization

All of the following should be declared `const` to prevent unnecessary rebuilds:
- Section label Text widgets
- Header icon container
- Header badge
- Empty state widgets
- Column/Row structural widgets that do not depend on data

### FutureProvider vs FutureBuilder

Do NOT use `FutureBuilder` directly. Always use `ref.watch(provider)` via
`ConsumerWidget` to leverage Riverpod caching, keepPreviousData in `ReportAsyncBody`,
and Dart type safety.

### keepPreviousData setting

For all `ReportAsyncBody` calls in the dashboard, set `keepPreviousData: true`
(which is the default). When the user changes the date filter, the old data remains
visible with an overlay spinner — no blank flash between filter changes.

### Rebuild frequency

| Trigger | Providers rebuilt |
|---|---|
| Date filter change | dashboardCashFlowProvider, dashboardCurrentStateProvider, dashboardRecentActivityProvider (NOT dashboardCashBalanceProvider — cached) |
| User navigates away | All autoDispose providers released |
| User navigates back | All providers re-execute |
| Nothing (idle) | No rebuilds |

---

## Section 7 — Phase Boundary

### Phase 5.2 scope (THIS implementation)

- `DashboardScreen` widget (screen shell, layout, permission gate)
- Route registration
- Financial Center side nav entry
- Header section
- Filter bar connected to `dashboardFilterProvider`
- Section D: Cash Flow KPI row (4 cards with dynamic colors)
- Section F: Supplementary KPI row (5 compact tiles with dynamic colors + totalSales warning)
- Section H: Recent Activity mini DataTable (10 rows, no pagination, no drill-down)
- "عرض دفتر النقدية" navigation button in activity section header
- Empty / loading / error states for all sections
- Refresh (_refresh) invalidates all dashboard providers

### Phase 5.3 scope (NEXT — not in 5.2)

| Feature | Reason deferred |
|---|---|
| KPI trend badges (period-over-period %) | Requires comparing two periods — extra provider |
| Row drill-down from mini activity table | ReportDrillDownService integration |
| Export button | No export model defined yet |
| Charts (bar, line, donut) | Phase 8 scope |
| Monthly breakdown table | Phase 8 scope |
| Forecast / projections | Phase 8 scope |
| Multi-branch selector | Phase 8+ scope |

---

## Section 8 — Future Compatibility

### Phase 6 — Profit & Loss

The dashboard layout has a natural insertion point for a Section I (P&L KPIs)
below Section F without any structural change. The `FinancialDashboardSummary`
model can be extended with a `profitLoss` field in Phase 6. No breaking change
to existing Phase 5.2 widgets — they bind to specific fields not the full model.

### Phase 7 — Cash Reconciliation

`sessionDifference` KPI is already in Section F. Phase 7 will add a Section J
(session breakdown table) below the activity section. No structural changes needed.

### Phase 8 — Advanced Analytics

`DashboardGranularity` is already in `DashboardFilter` (day/week/month).
Adding a granularity SegmentedButton to the filter bar requires only modifying the
filter bar widget — no provider or model changes.

Migrating from `FutureProvider` to `StreamProvider` (for real-time refresh) only
requires changing the provider file — the ConsumerWidget subwidgets are unaffected
because they use `ref.watch(provider)` which works identically for both types.

### Mobile dashboard (future)

The 4-card cash flow row and 5-card supplementary row will wrap automatically
if `Wrap` is used instead of `Row`. Phase 5.2 can use `Row` (desktop only),
with Wrap as the Phase 8 responsive upgrade.

---

## Section 9 — Risk Assessment

| Risk | Severity | Description | Mitigation |
|---|---|---|---|
| cashBalance staleness (45 s cache) | LOW | User changes filter, other KPIs update, cashBalance does not | Add "منذ البداية" subtitle; document in Phase 8 upgrade path |
| totalSales misread as net revenue | MEDIUM | User reads "إجمالي المبيعات" and assumes it is net cash | Mandatory subtitle: "شامل الآجل والكارت" + doc comment on model |
| netCashFlow negative on-screen | LOW | Red KPI card may confuse users | Clear Arabic label "صافي التدفق" with sign indicator |
| sessionDifference negative on-screen | LOW | Shortage shown as red negative — may alarm unnecessarily | Subtitle "عجز / زيادة" clarifies semantics |
| Dashboard does not auto-refresh on write | MEDIUM | User creates a sale, dashboard does not update until filter change | Documented in R3 comment; Phase 8 upgrade path; add refresh button |
| Recent activity table confusion (only 10 rows) | LOW | User thinks they are seeing all transactions | Section header label: "آخر 10 حركات" + "عرض الكل" button |
| Desktop width < 800 px | LOW | 5 supplementary cards overflow | Phase 5.2 acceptable for desktop; Phase 8 adds wrap |
| dashboardSummaryProvider double-wait | MEDIUM | If used instead of independent providers, screen waits for slowest | Use independent ConsumerWidget subwidgets — do NOT use summaryProvider as sole source |

---

## Section 10 — Implementation Roadmap

### Phase 5.2.1 — Screen Shell + Route + Permission
**Complexity: LOW | Risk: LOW | Estimated: 1 session**

1. Create `lib/features/financial/screens/financial_dashboard_screen.dart`
   - `FinancialDashboardScreen extends ConsumerStatefulWidget`
   - Wrap with `AnalyticsPermissionGate(requiresFinancial: true)`
   - Implement header section (const Widget — icon, title, subtitle, READ-ONLY chip)
   - Implement `_refresh()` method: invalidate all 4 dashboard providers
   - Layout scaffold: Column with all section placeholders (SizedBox stubs)

2. Register route
   - Add route constant and navigation entry for `FinancialDashboardScreen`
   - Add to Financial Center side navigation

3. Validate: screen opens, permission gate works, no errors

---

### Phase 5.2.2 — Filter Bar + KPI Sections D and F
**Complexity: MEDIUM | Risk: LOW | Estimated: 1–2 sessions**

1. Implement filter bar section
   - `_DashboardFilterSection extends ConsumerWidget`
   - Use existing `ReportFilterBar(showExport: false)`
   - Wire to `dashboardFilterProvider.notifier.setDateFilter()`
   - Wire `onRefresh` to `_refresh()`

2. Implement Cash Flow Section D (`_DashboardCashFlowSection`)
   - `ref.watch(dashboardCashFlowProvider)` inside `ConsumerWidget`
   - `ReportAsyncBody<FinancialDashboardCashFlow>` with `keepPreviousData: true`
   - 4 `_DashboardKpiTile` widgets in a `Row`
   - Implement dynamic colors for `cashBalance` and `netCashFlow`
   - cashBalance subtitle: "الرصيد التراكمي — لا يتأثر بالفترة المحددة"

3. Implement Supplementary Section F (`_DashboardCurrentStateSection`)
   - `ref.watch(dashboardCurrentStateProvider)` inside `ConsumerWidget`
   - `ReportAsyncBody<FinancialDashboardCurrentState>` with `keepPreviousData: true`
   - 5 compact `_DashboardSupplementaryTile` widgets in a `Row`
   - Implement dynamic colors for `sessionDifference`
   - totalSales subtitle: "شامل الآجل والكارت"

4. Validate: all KPIs display correctly, dynamic colors work, filter changes update KPIs

---

### Phase 5.2.3 — Recent Activity Section + End-to-End Test
**Complexity: LOW | Risk: LOW | Estimated: 1 session**

1. Implement Recent Activity Section H (`_DashboardRecentActivitySection`)
   - `ref.watch(dashboardRecentActivityProvider)` inside `ConsumerWidget`
   - `ReportAsyncBody<List<CashLedgerEvent>>` with `keepPreviousData: true`
   - Section header Row: "آخر 10 حركات" label + "عرض دفتر النقدية" OutlinedButton
   - Mini DataTable: 5 columns (no running balance, no drill-down)
   - Empty state: `ReportTableEmptyState`
   - No pagination widget (10-row limit is built into provider)

2. End-to-end test
   - Navigate to dashboard from side nav
   - Change date filter: all KPIs except cashBalance update
   - Empty period: empty state shows in all sections
   - Navigate to Cash Ledger from "عرض دفتر النقدية" button
   - `flutter analyze` — 0 issues
   - `flutter build windows --debug` — PASS

---

## Widget Reference Map

| Widget | Source | Reuse status |
|---|---|---|
| `AnalyticsPermissionGate` | `reports/modules/shared/` | REUSE AS-IS |
| `ReportFilterBar` | `reports/core/widgets/` | REUSE AS-IS |
| `ReportAsyncBody<T>` | `reports/core/widgets/` | REUSE AS-IS |
| `ReportMetricCard` | `reports/core/widgets/` | REUSE AS-IS (Section D) |
| `ReportMetricModel` | `reports/core/models/` | REUSE AS-IS |
| `ReportTableEmptyState` | `reports/core/widgets/` | REUSE AS-IS |
| `ReportErrorView` | `reports/core/widgets/` | REUSE AS-IS |
| `AnalyticsFormatters` | `reports/modules/shared/` | REUSE AS-IS |
| `AppColors` | `core/theme/` | REUSE AS-IS |
| `_DashboardKpiTile` | NEW — local to screen file | CREATE (tall card) |
| `_DashboardSupplementaryTile` | NEW — local to screen file | CREATE (compact tile) |
| `_DashboardFilterSection` | NEW — local to screen file | CREATE (ConsumerWidget) |
| `_DashboardCashFlowSection` | NEW — local to screen file | CREATE (ConsumerWidget) |
| `_DashboardCurrentStateSection` | NEW — local to screen file | CREATE (ConsumerWidget) |
| `_DashboardRecentActivitySection` | NEW — local to screen file | CREATE (ConsumerWidget) |

Private widget classes (`_Dashboard*`) live inside `financial_dashboard_screen.dart`.
No separate widget files are needed for Phase 5.2.

---

## Readiness Score

| Category | Score | Notes |
|---|---|---|
| Data layer readiness | 20/20 | All KPIs present and audited |
| Widget infrastructure reuse | 20/20 | ReportAsyncBody, ReportFilterBar, ReportMetricCard all reusable |
| Layout clarity | 19/20 | 5-tile supplementary row may be tight at narrower desktop widths |
| KPI accuracy risk | 18/20 | totalSales gross/net requires mandatory subtitle (-1); cashBalance cache note required (-1) |
| Performance design | 19/20 | Independent ConsumerWidgets prevent cascading rebuilds |
| Future compatibility | 20/20 | No architectural decisions block Phases 6–8 |

**Total: 116/120 — normalized to 97/100**

---

## Final Decision

**GO — 97 / 100**

All required data is present. All required widget infrastructure exists and is reusable.
The implementation plan is divided into 3 low-risk phases.

**One mandatory UI constraint before Phase 5.2 sign-off:**
`totalSales` MUST display the subtitle "شامل الآجل والكارت" at all times.
`cashBalance` MUST display the subtitle "لا يتأثر بالفترة المحددة" at all times.
These are not optional UX choices — they are financial integrity requirements.

---

*Audit type: READ-ONLY — No code written during this audit*
*Auditor: Principal ERP UX Architect / Senior Flutter Desktop Architect*