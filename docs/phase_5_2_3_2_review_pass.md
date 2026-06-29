# Phase 5.2.3.2 — Financial Dashboard UI
# Review Pass — Recent Activity Drill-Down
# Date: 2026-06-26

---

## Executive Summary

Phase 5.2.3.2 adds read-only drill-down to Recent Activity rows by extracting
Cash Ledger routing into a shared dispatcher (`CashLedgerEventDrillDown`) and
wiring Dashboard rows through it. Cash Ledger was refactored to call the same
helper, eliminating duplicated switch/permission/dialog logic.

The implementation is architecturally correct, financially neutral (no new
calculations or SQL), reusable, and maintainable. Provider boundaries from
Phase 5.2.3.1 are preserved. No data-layer files were touched.

**Readiness Score: 98 / 100**
**Final Decision: GO**

**Phase 5.2.3.2 is ready for Hardening Pass.**

---

## Validation Results

| Check | Result |
|---|---|
| `flutter analyze` (4 phase files) | **No issues found** |
| `flutter analyze` (project) | 102 pre-existing warnings/info — **0 errors in phase files** |
| `flutter build windows --debug` | **PASS** — `build\windows\x64\runner\Debug\lez_pos.exe` |

---

## Section 1 — File Boundary Review

### Files created (1)

| File | Status |
|---|---|
| `lib/features/financial/widgets/cash_ledger_event_drill_down.dart` | EXPECTED — shared dispatcher |

### Files modified (3)

| File | Change | Status |
|---|---|---|
| `lib/features/financial/screens/widgets/dashboard_recent_activity_row.dart` | Added `Material` + `InkWell`, `onTap`, click cursor | EXPECTED |
| `lib/features/financial/screens/widgets/dashboard_recent_activity_section.dart` | `_RecentActivityList` -> `ConsumerWidget`; dispatches drill-down | EXPECTED |
| `lib/features/financial/screens/cash_ledger_screen.dart` | Removed private `_openDrillDown`; delegates to shared helper | EXPECTED (DRY) |

### Accidental modifications

**None detected** under `lib/features/financial/` for Phase 5.2.3.2 scope.

Confirmed **unchanged**:

- `financial_dashboard_screen.dart` (section wired in 5.2.3.1 only)
- `dashboard_providers.dart`
- `FinancialDashboardRepository`
- `FinancialLedgerRepository`
- Database / migrations / SQL
- Reports modules (consumed, not modified)

### Hidden dependencies

| Import in phase files | Verdict |
|---|---|
| `CashLedgerEventDrillDown` | PASS — presentation routing only |
| `ReportDrillDownService` | PASS — existing reports drill-down (dispatcher only) |
| `OtherIncomeDetailsDialog` | PASS — existing read-only dialog |
| `dashboardRecentActivityProvider` | PASS — section only |
| `FinancialLedgerRepository` | **ABSENT** |
| `FinancialDashboardRepository` | **ABSENT** |
| Direct SQL / DAO imports | **ABSENT** |

### Dispatcher isolation

`CashLedgerEventDrillDown` lives in its own file under
`lib/features/financial/widgets/`. Single public entry point:
`CashLedgerEventDrillDown.open(context, ref, event)`.

---

## Section 2 — Dispatcher Architecture Review

### CashLedgerEventDrillDown

| Criterion | Verdict | Evidence |
|---|---|---|
| Single responsibility | PASS | Routes event type to existing dialog/navigation only |
| No business logic | PASS | No amount/direction/balance computation |
| No SQL | PASS | No database imports |
| No repository access | PASS | Delegates to ReportDrillDownService / showDialog |
| No duplicated financial logic | PASS | Uses pre-built CashLedgerEvent fields only |
| Minimal switch | PASS | 71 lines; 7 enum cases; localized in one file |

### Switch structure

- saleCash / returnRefund -> ReportDrillDownService (invoice)
- customerPayment -> ReportDrillDownService (customer, guarded)
- purchaseCash / supplierPayment -> ReportDrillDownService (supplier, guarded)
- expense -> break (no-op)
- otherIncome -> permission check + OtherIncomeDetailsDialog

Dart 3 switch semantics prevent fall-through. Each branch is independent and
maintainable. No financial aggregation or ledger math appears in the dispatcher.

---

## Section 3 — Reuse Review

### Shared entry point

| Consumer | Call site | Verdict |
|---|---|---|
| Cash Ledger | cash_ledger_screen.dart L340 — DataRow.onSelectChanged | PASS |
| Dashboard Recent Activity | dashboard_recent_activity_section.dart L79 — row onTap | PASS |

### Duplication eliminated

| Previously duplicated | Status |
|---|---|
| _openDrillDown switch in cash_ledger_screen.dart | **REMOVED** |
| Permission check for other income | **Single copy** in dispatcher |
| Dialog selection per event type | **Single copy** in dispatcher |

Grep confirms _openDrillDown no longer exists. Only CashLedgerEventDrillDown.open
remains for cash-ledger-event drill-down routing.

### Incidental improvement (non-regression)

The extracted dispatcher adds await on supplier/purchase ReportDrillDownService.open
calls. The prior Cash Ledger inline code omitted await on supplier payment.
Behavior is unchanged functionally; async hygiene is slightly improved.

---

## Section 4 — Dialog Mapping Review

| Event type | Enum | Target | Permission | Read-only | Verdict |
|---|---|---|---|---|---|
| SALE | saleCash | ReportDrillDownService -> InvoiceDetailsDialog | canViewReportsProvider (via service) | View + pre-existing return/reprint in dialog | PASS — Cash Ledger parity |
| RETURN | returnRefund | Same as sale (invoice id) | Same | Same | PASS |
| CUSTOMER PAYMENT | customerPayment | ReportDrillDownService -> /customers/profile/:id | canViewReportsProvider; skipped if customerId null or <= 1 | Profile view (navigation) | PASS |
| PURCHASE | purchaseCash | ReportDrillDownService -> /suppliers/profile/:id | PermissionKeys.purchasesView | Profile view (navigation) | PASS |
| SUPPLIER PAYMENT | supplierPayment | Same as purchase | Same | Same | PASS |
| OTHER INCOME | otherIncome | OtherIncomeDetailsDialog | PermissionKeys.financialIncomeView | View-only — close button only | PASS |
| EXPENSE | expense | No-op (break) | N/A | N/A | PASS — Cash Ledger parity |

### Duplicate dialogs

**None created.** All targets are pre-existing shared components.

### Editable dialogs from Dashboard

**None opened.** ExpenseDialog (edit/create) is not referenced.

### Expense note

No read-only expense details dialog exists. Implementation preserves Cash Ledger
behavior rather than opening the editable ExpenseDialog.

---

## Section 5 — Provider Review

| Requirement | Verdict | Evidence |
|---|---|---|
| Section watches dashboardRecentActivityProvider only | PASS | dashboard_recent_activity_section.dart L29 |
| Rows receive CashLedgerEvent + callback | PASS | DashboardRecentActivityRow(event, onTap) |
| No repository access in rows | PASS | Row imports: theme, formatters, models only |
| No provider misuse | PASS | _RecentActivityList uses ref only for drill-down at tap time |
| Provider file unchanged | PASS | dashboard_providers.dart unmodified |

---

## Section 6 — UI Review

| Criterion | Verdict |
|---|---|
| Desktop click behavior | PASS — InkWell.onTap, click only |
| Mouse cursor | PASS — SystemMouseCursors.click |
| Click feedback | PASS — Material + InkWell ripple |
| RTL | PASS — row layout unchanged from 5.2.3.1 |
| Spacing | PASS — padding preserved |
| Layout regressions | PASS |
| Overflow | PASS — maxLines + ellipsis |
| Nested scrolling | PASS — Column(mainAxisSize: min) |

Expense rows show click cursor but perform no action — inherited Cash Ledger behavior.

---

## Section 7 — Async Review

| Path | Verdict |
|---|---|
| Invoice / customer / supplier via ReportDrillDownService | PASS — service checks context.mounted |
| Other income: permission -> mounted -> showDialog | PASS |
| Expense no-op | PASS |

No duplicated showDialog blocks remain outside the shared helper and
ReportDrillDownService._openInvoice.

---

## Section 8 — Regression Review

| Area | Modified? | Regression risk |
|---|---|---|
| Cash Ledger drill-down | Refactored to shared helper | **NONE** — logic extracted verbatim |
| Financial Dashboard providers/repos | No | **NONE** |
| Reports / ReportDrillDownService | No | **NONE** |
| Database / SQL / business logic | No | **NONE** |

---

## Section 9 — Performance Review

| Factor | Classification |
|---|---|
| Dispatcher overhead | **LOW** — runs only on click |
| Widget rebuilds | **LOW** — no new ref.watch in rows |
| Object allocation | **LOW** — max 10 rows |
| Routing cost | **LOW** — same as prior Cash Ledger |
| Maintainability improvement | **HIGH** — single source of truth |

Overall performance impact: **LOW**.

---

## Remaining Risks

| Risk | Severity | Notes |
|---|---|---|
| Expense rows clickable but no-op | Low | Inherited Cash Ledger behavior |
| Customer/supplier drill-down navigates away via go_router | Low | Inherited ReportDrillDownService behavior |
| InvoiceDetailsDialog exposes return/reprint | Low | Pre-existing dialog |
| Walk-in customer payments (customerId <= 1) silently no-op | Low | Pre-existing guard |

None block Hardening Pass.

---

## Readiness Score Breakdown

| Category | Score |
|---|---|
| Architecture / boundaries | 20/20 |
| Reuse / DRY | 20/20 |
| Financial correctness | 20/20 |
| Provider / data isolation | 19/20 |
| UI / desktop interaction | 19/20 |
| Validation | 20/20 |

**Total: 98 / 100**

---

## Final Decision

### GO

**Phase 5.2.3.2 is ready for Hardening Pass.**

---

## Explicit Confirmations

| Statement | Confirmed |
|---|---|
| No business logic duplicated | YES |
| No financial calculations introduced | YES |
| No repository logic duplicated | YES |
| Phase 5.2.3.2 scope only | YES |