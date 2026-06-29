# Expense Management — Architecture & Integration Audit

| Field | Value |
|-------|-------|
| **Project** | Lez POS |
| **Document** | Expense Management Architecture Audit |
| **Date** | June 2026 |
| **Scope** | Analysis and design only — no code, migrations, or implementation |
| **Prerequisite** | Cash Ledger v1 (read-only derived), Financial Center blueprint, Phase 1.5 audit |
| **Author role** | Senior ERP Architect / Financial Systems Analyst |

---

## Executive Summary

Lez POS records **operational cash outflows** today through purchases (`purchase_invoices.paid_amount`), supplier payments (`supplier_transactions` type `PAYMENT`), and customer refunds (`return_audit_logs.returned_amount`), all unified in **Cash Ledger v1** via SQL UNION. There is **no expense module**, **no operating-expense table**, and **`AdvancedAnalyticsRepository.getCashFlow()` hardcodes `expenses = 0`**.

Introducing Expense Management requires a **supplemental operational table** (`expense_records`) as the **single source of truth** for non-COGS, non-AP operating cash outflows, with **one derived Cash Ledger arm** (`EXPENSE`) and **strict dedup by primary key**. Expenses must **not** be modeled as supplier payments or purchase invoices.

**Readiness score: 58 / 100** — architecture direction is clear; blockers are session formula policy, KPI harmonization, permission seeding, and schema migration planning.

**Recommended next phase:** Phase 4 — Expense Management (after Cash Ledger v1 stabilization and session reconciliation policy sign-off for Phase 3).

---

# Step 1 — Existing Financial Flow Analysis

## 1.1 Current money outflows (cash-affecting)

| Source | Table(s) | Service / DAO | Current financial effect | Cash Ledger integration |
|--------|----------|---------------|--------------------------|-------------------------|
| **Purchase cash (at invoice)** | `purchase_invoices` (`paid_amount`, `debt_amount`) | `PurchasesDao.savePurchaseInvoice()` | Cash leaves drawer/bank at purchase; credit portion posts `supplier_transactions` type `PURCHASE` (accrual, not cash) | **Yes** — `PURCHASE_CASH` when `paid_amount > 0` |
| **Supplier payment (standalone)** | `supplier_transactions` | `SupplierAccountsDao.addTransaction(PAYMENT)`, `SupplierPaymentsScreen`, `SupplierAccountService` | Reduces AP balance; cash out | **Yes** — `SUPPLIER_PAYMENT` with dedup guard vs purchase invoice reference |
| **Customer refund (cash)** | `return_audit_logs` | `ReturnsDao`, `PartialReturnService`, `ReturnAuditLogsDao.insertAuditLog()` | Cash refund to customer; stock restored; credit returns also post `customer_transactions` RETURN | **Yes** — `RETURN_REFUND` with dedup vs `customer_transactions RETURN` on same invoice |
| **Customer credit reversal (non-cash)** | `customer_transactions` (`RETURN`) | `CustomerAccountsDao.recordReturn()` | Reduces AR; not a drawer cash event | **No** (correct) — excluded from cash ledger |
| **POS change given** | `sales_invoices.change_amount` | `PosRepository.saveSale()` | Cash returned to customer as change; already netted in `cash_paid` collection | **No separate event** — embedded in sale cash handling |
| **Session opening float** | `pos_sessions.opening_cash` | `PosRepository.openSession()` | Starting drawer cash; not an expense | **No** — balance sheet / reconciliation baseline |
| **Session close variance** | `pos_sessions` (`closing_cash`, `expected_cash_amount`, `cash_difference`) | `PosSessionNotifier.closeSession()` | Records over/short; **not** an automatic expense posting | **No** — should become reconciliation adjustment, not expense |
| **Stock adjustment (loss/damage)** | `stock_adjustments`, `stock_movements` | Inventory UI, `StockMovementsDao` | Inventory quantity/value change; **no cash posting** | **No** — future link to expense (write-off) optional |
| **Supplier returns** | `supplier_returns`, `supplier_return_items` | `ReturnsDao.saveSupplierReturn()` | Stock out; **no cash/AP posting** | **No** |
| **Operating expenses** | — | — | **Does not exist** | **No** |
| **Payroll / salaries** | — | — | **Does not exist** | **No** |
| **Manual ledger adjustment** | — | — | **Does not exist** | **No** |

## 1.2 Non-cash outflows (accrual — not Cash Ledger)

| Source | Table | Effect |
|--------|-------|--------|
| Credit purchase (debt) | `purchase_invoices.debt_amount` + `supplier_transactions PURCHASE` | Increases AP; cash when paid later |
| Credit sale (debt) | `sales_invoices.debt_amount` + `customer_transactions SALE` | Increases AR; cash when collected |

## 1.3 Parallel reporting outflows (not authoritative)

| Source | Location | Issue |
|--------|----------|-------|
| `getCashFlow()` supplier payments | `AdvancedAnalyticsRepository` | Counts `supplier_transactions PAYMENT` only; **omits** purchase `paid_amount` and refunds |
| `getCashFlow()` expenses | Same | `const expenses = 0.0` — placeholder |

**Integration rule:** Expenses must feed **Cash Ledger UNION** first; Reports/Dashboard must **read the same repository**, not duplicate SQL.

---

# Step 2 — Expense Classification Design

Retail/POS expense categories (recommended seed set):

| Category | Operational purpose | Financial impact | Reporting importance |
|----------|---------------------|------------------|---------------------|
| **Rent** | Store/warehouse lease | Fixed OpEx; recurring | High — largest fixed cost benchmark |
| **Electricity** | Utilities | Variable OpEx | Medium — seasonal trend |
| **Internet** | Connectivity, POS cloud | Fixed OpEx | Medium |
| **Salaries** | Staff wages | Fixed/variable OpEx | **Critical** — often largest OpEx |
| **Transportation** | Delivery, logistics | Variable OpEx | Medium |
| **Fuel** | Vehicle/delivery fuel | Variable OpEx | Medium — fraud audit |
| **Maintenance** | Equipment/store repairs | Variable OpEx | Medium |
| **Cleaning** | Hygiene services | Recurring OpEx | Low–medium |
| **Office Supplies** | Non-inventory consumables | Small OpEx | Low |
| **Marketing** | Ads, promotions (non-COGS) | Discretionary OpEx | High — ROI vs sales |
| **Bank / Payment fees** | Card processing, transfers | Financial OpEx | Medium — ties to card sales |
| **Taxes & licenses** | Government fees (non-VAT input) | Compliance OpEx | High — fiscal |
| **Insurance** | Business insurance | Fixed OpEx | Medium |
| **Other** | Catch-all with mandatory note | Misc OpEx | Required fallback |

### Classification rules

1. **Inventory purchases are NOT expenses** — they flow through Purchases → COGS at sale.
2. **Supplier invoice payments are NOT expenses** — AP settlement (already in ledger).
3. **Customer refunds are NOT expenses** — contra-revenue / refund outflow (already in ledger).
4. **Stock shrinkage** may optionally create an expense via linked write-off workflow (Phase 2+); default: separate module.
5. Each `expense_record` maps to **exactly one** `expense_category_id`; `Other` requires `notes` min length.

---

# Step 3 — Database Architecture (Design Only)

## 3.1 `expense_categories`

| Column | Type | Purpose | Required | Index |
|--------|------|---------|----------|-------|
| `id` | INTEGER PK AI | Surrogate key | Yes | PK |
| `code` | TEXT UNIQUE | Stable machine key (e.g. `RENT`, `SALARIES`) | Yes | UNIQUE |
| `name_ar` | TEXT | Display label (Arabic) | Yes | — |
| `name_en` | TEXT | Optional English | No | — |
| `parent_id` | INTEGER FK → self | Subcategory support (optional v2) | No | FK |
| `is_active` | BOOLEAN | Soft-disable without deleting history | Yes (default true) | Partial index on active |
| `sort_order` | INTEGER | UI ordering | Yes (default 0) | — |
| `is_system` | BOOLEAN | Seed categories protected from delete | Yes (default false) | — |
| `created_at` | DATETIME | Audit | Yes | — |
| `updated_at` | DATETIME | Audit | No | — |

**Notes:** Seed categories on migration; allow admin to add custom categories with `is_system = false`.

## 3.2 `expense_records`

| Column | Type | Purpose | Required | Index |
|--------|------|---------|----------|-------|
| `id` | INTEGER PK AI | Surrogate key; ledger `reference_id` | Yes | PK |
| `expense_number` | TEXT UNIQUE | Human-readable doc no. (EXP-2026-0001) | Yes | UNIQUE |
| `category_id` | INTEGER FK | Classification | Yes | FK + composite |
| `amount` | REAL | **Positive** cash out amount | Yes | — |
| `expense_date` | DATETIME | Economic date (accrual reporting) | Yes | **INDEX** `(expense_date)` |
| `paid_at` | DATETIME | When cash actually left (ledger timestamp) | Yes | INDEX `(paid_at)` |
| `payment_method` | TEXT | `CASH`, `BANK`, `CARD` (extend later) | Yes (default CASH) | — |
| `vendor_name` | TEXT | Payee description (not supplier FK required) | No | — |
| `supplier_id` | INTEGER FK nullable | Link if paid to registered supplier **without** AP invoice | No | FK |
| `session_id` | INTEGER FK nullable | POS session if paid from drawer | No | **INDEX** `(session_id)` |
| `user_id` | INTEGER FK | Who recorded | Yes | FK |
| `approved_by_user_id` | INTEGER FK nullable | Optional approval workflow | No | — |
| `status` | TEXT | `DRAFT`, `POSTED`, `VOID` | Yes (default POSTED) | INDEX `(status)` |
| `notes` | TEXT | Description / memo | No (required if category=Other) | — |
| `reference_type` | TEXT nullable | External ref (e.g. `stock_adjustment`) | No | — |
| `reference_id` | INTEGER nullable | Polymorphic link | No | Composite `(reference_type, reference_id)` UNIQUE when not null |
| `voided_at` | DATETIME nullable | Void timestamp | No | — |
| `voided_by_user_id` | INTEGER nullable | Who voided | No | — |
| `void_reason` | TEXT nullable | Audit | No | — |
| `created_at` | DATETIME | Insert audit | Yes | — |
| `updated_at` | DATETIME | Update audit | No | — |

**Design decisions:**
- **`amount` always positive**; direction implied as outflow in ledger.
- **`status = VOID`** excludes from ledger UNION (soft delete pattern — immutable audit).
- **`reference_type/id` UNIQUE** prevents duplicate expense from same source document (stock write-off link).
- **Do NOT duplicate** into `supplier_transactions` when recording expense.

## 3.3 `expense_attachments` (recommended)

| Column | Type | Purpose | Required | Index |
|--------|------|---------|----------|-------|
| `id` | INTEGER PK AI | Attachment id | Yes | PK |
| `expense_id` | INTEGER FK | Parent expense | Yes | FK `(expense_id)` |
| `file_name` | TEXT | Original filename | Yes | — |
| `file_path` | TEXT | Local storage path | Yes | — |
| `mime_type` | TEXT | Content type | No | — |
| `file_size_bytes` | INTEGER | Size audit | No | — |
| `uploaded_by_user_id` | INTEGER FK | Uploader | Yes | — |
| `uploaded_at` | DATETIME | Upload time | Yes | — |

**Purpose:** Receipt photos for audit; optional in v1 UI but schema-ready.

---

# Step 4 — Cash Ledger Integration

## 4.1 Event definition

| Property | Value |
|----------|-------|
| **Event type code** | `EXPENSE` |
| **Arabic label** | `مصروف تشغيلي` |
| **Direction** | `outflow` |
| **ledger_id format** | `EXPENSE:{expense_records.id}` |
| **event_ts source** | `expense_records.paid_at` (fallback `expense_date` if policy allows accrual mode — **recommend paid_at only for cash ledger**) |
| **amount** | `expense_records.amount` |
| **reference_type** | `expense_record` |
| **reference_id** | `expense_records.id` |
| **user_id** | `expense_records.user_id` |
| **session_id** | `expense_records.session_id` (expose in ledger model when column added) |
| **description** | `{category.name_ar} — {notes or vendor_name}` |

## 4.2 Running balance effect

Cash Ledger v1 computes running balance as cumulative `inflow − outflow` ordered by timestamp. **EXPENSE rows decrease running balance** identically to `PURCHASE_CASH` and `RETURN_REFUND`.

## 4.3 Dedup rules (mandatory safeguards)

| Rule | Description |
|------|-------------|
| **E1 — Single source** | Expenses appear **only** via `expense_records` UNION arm. Never also post as `supplier_transactions PAYMENT`. |
| **E2 — Primary key idempotency** | `ledger_id = 'EXPENSE:' \|\| id` guarantees one ledger row per expense. |
| **E3 — Status filter** | UNION includes `WHERE status = 'POSTED'` only. `DRAFT` and `VOID` excluded. |
| **E4 — Reference uniqueness** | If `reference_type/id` set (e.g. stock write-off), application layer rejects second POSTED expense for same reference. |
| **E5 — No purchase overlap** | Expenses must not reference `purchase_invoices.id` as payment substitute. Purchases stay on `PURCHASE_CASH` / `SUPPLIER_PAYMENT`. |
| **E6 — Amount sign** | Store positive; SQL uses amount as outflow (never negative amounts in table). |
| **E7 — Void handling** | Voiding expense removes from UNION; optional future `EXPENSE_VOID` inflow adjustment event **not needed** if void excludes row (simpler). |
| **E8 — Export parity** | CSV export uses same UNION as screen — no second query path. |

## 4.4 UNION SQL sketch (design reference — not implemented)

```sql
UNION ALL
SELECT
  'EXPENSE:' || er.id AS ledger_id,
  er.paid_at AS event_ts,
  'EXPENSE' AS event_type,
  er.amount,
  'outflow' AS direction,
  'expense_record' AS reference_type,
  er.id AS reference_id,
  er.user_id,
  NULL AS customer_id,
  er.supplier_id,
  NULL AS invoice_id,
  (ec.name_ar || ' — ' || COALESCE(er.notes, er.vendor_name, '')) AS description
FROM expense_records er
INNER JOIN expense_categories ec ON ec.id = er.category_id
WHERE er.status = 'POSTED' AND er.amount > 0
```

Extend `CashLedgerEventType` enum with `expense` when implementing.

---

# Step 5 — Session Reconciliation Impact

## 5.1 Current session formula (baseline)

```
expected_cash = opening_cash + SUM(cash_paid for session invoices, non-returned)
cash_difference = closing_cash - expected_cash
```

**Gaps:** No collections, refunds, purchases, or expenses in session expected cash.

## 5.2 Recommended session formula (with expenses)

For session `S` with time window `[opened_at, closed_at]`:

```
expected_drawer(S) =
    opening_cash(S)
  + cash_sales(S)
  + cash_collections(S)          -- customer PAYMENT in window (optional session_id link)
  - cash_refunds(S)              -- return_audit_logs in session
  - purchase_cash(S)             -- purchase paid_amount in window (if drawer-funded)
  - cash_expenses(S)             -- expense_records WHERE session_id = S AND status = POSTED AND payment_method = CASH
  +/- session_adjustments(S)     -- future controlled adjustments
```

Where:
- `cash_expenses(S) = SUM(expense_records.amount WHERE session_id = S AND payment_method = 'CASH' AND status = 'POSTED')`

## 5.3 Field impact

| Field | Expense impact |
|-------|----------------|
| **Opening cash** | Unchanged — float is not expense |
| **Expected cash** | **Decrease** by session-attributed cash expenses |
| **Closing cash** | User-entered physical count — unchanged |
| **Cash difference** | `closing - expected` — expenses reduce expected, improving accuracy |

## 5.4 Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Expense without `session_id` | Medium | Default prompt when open session exists; reconciliation uses only linked rows |
| Bank-paid expense during session | Low | `payment_method != CASH` excluded from drawer formula but included in Cash Ledger |
| Double hit (expense + supplier payment) | **High** | E1 rule — never mirror in supplier_transactions |
| Retroactive expense edit | Medium | Immutable POSTED; void + re-create pattern |

---

# Step 6 — Profit & Loss Integration

## 6.1 Recommended P&L structure

```
REVENUE
  Gross Sales (cash + card + credit, net of returns)
  Less: Sales Returns (contra revenue)

COST OF GOODS SOLD
  COGS (from sale_items.unit_cost × qty, adjusted for returns)

GROSS PROFIT = Revenue - COGS

OPERATING EXPENSES (from expense_records by category)
  Rent, Salaries, Utilities, Marketing, ...
  TOTAL OPERATING EXPENSES

OPERATING PROFIT (EBIT) = Gross Profit - Operating Expenses

OTHER INCOME / NON-OPERATING (future module)
  ...

NET PROFIT = Operating Profit + Other Income - Non-operating expenses
```

## 6.2 Expense placement

| Type | Source | P&L section |
|------|--------|-------------|
| **COGS** | `sale_items` cost | **Not expenses** — separate line |
| **Inventory purchase** | `purchase_invoices` | **Not OpEx** — inventory asset → COGS |
| **Operating expenses** | `expense_records` | **OpEx** by category |
| **Customer refunds** | Returns | **Contra revenue**, not OpEx |
| **Supplier payments** | AP settlement | **Not OpEx** (balance sheet) |
| **Depreciation** | Future | Non-cash OpEx (v2+) |

## 6.3 Net profit impact

Each POSTED expense **reduces net profit** in the period of `expense_date` (accrual view) or `paid_at` (cash view — recommend supporting both report modes).

**Cash Ledger uses `paid_at`; P&L default uses `expense_date`** with toggle for cash-basis P&L.

---

# Step 7 — Financial Dashboard Integration

## 7.1 Recommended KPIs

| KPI | Calculation | Source |
|-----|-------------|--------|
| **Expenses Today** | SUM amount WHERE paid_at = today, POSTED | `expense_records` |
| **Expenses This Month** | SUM in month | Same |
| **Largest Category (MTD)** | GROUP BY category ORDER BY SUM DESC LIMIT 1 | Join categories |
| **Expense Trend** | Daily/weekly SUM over 30/90 days | Chart time series |
| **Expense Ratio vs Sales** | OpEx MTD / Net Sales MTD × 100 | Expenses + `sales_invoices` |
| **Net Cash After Expenses** | Ledger net flow (includes EXPENSE arm) | Cash Ledger summary |

## 7.2 Dashboard cards (Financial Center)

1. **Row 1 (existing):** Inflow | Outflow | Net | Transaction count — from Cash Ledger (outflow grows with expenses).
2. **Row 2 (new):** Expenses Today | Expenses MTD | Expense/Sales % | Top category.
3. **Chart:** Stacked bar — sales vs expenses by week (reuse `ReportChartCard`).
4. **Chart:** Donut — expense breakdown by category MTD.

**Conflict prevention:** Dashboard expense KPIs must use **`ExpenseRepository` aggregations** that match Cash Ledger UNION totals for the same date range (single query or shared SQL view).

---

# Step 8 — Permissions & Security

## 8.1 Current architecture

- Permissions stored in `permissions` table, synced via `PermissionSyncService`.
- Keys defined in `PermissionKeys` (`analytics.financial` gates `/financial`).
- Route guard: `route_permissions.dart` maps `/financial` → `analyticsFinancial`.
- Pattern: `permissionProvider(key)` + `PermissionRouteGuard`.

## 8.2 Recommended expense permissions

| Key | Purpose | Suggested roles |
|-----|---------|-----------------|
| `financial.expenses.view` | List, details, analytics | Manager, Accountant, Owner |
| `financial.expenses.create` | Create/post expenses | Manager, Cashier (session-linked) |
| `financial.expenses.edit` | Edit DRAFT only | Manager |
| `financial.expenses.delete` | Void expense (soft) | Manager, Owner |
| `financial.expenses.export` | CSV/PDF export | Accountant, Owner |

## 8.3 Integration approach

1. Add constants to `PermissionKeys` + `descriptions` + `all` list.
2. Extend `PermissionSyncService` seed list (migration adds rows on startup).
3. Gate routes: `/financial/expenses`, `/financial/expenses/new`.
4. **Hierarchy:** `financial.expenses.view` required for any expense UI; create/edit/delete are granular.
5. **Cash Ledger:** Existing `analytics.financial` sufficient for viewing EXPENSE lines; creating expenses uses `financial.expenses.create`.
6. **Activity logs:** Log create/void via `ActivityLoggerService` (category: financial).
7. **Audit:** POSTED records immutable; void requires `financial.expenses.delete` + reason.

**Alternative (simpler v1):** Map all expense CRUD to `analytics.financial` + `reports.export` for export — acceptable for small deployments but not recommended for segregation of duties.

---

# Step 9 — UI Architecture (Design Only)

Reuse from Reports / Financial modules:

| Component | Reuse |
|-----------|-------|
| `ReportFilterBar` | Date presets (today, month, year, custom) |
| `ReportAsyncBody` | Loading/error/data states |
| `ReportMetricGrid` / KPI tiles | Summary cards |
| `ReportTableHeader`, `ReportTableCard` | Expense list |
| `ReportExportService` | CSV export |
| `AnalyticsPermissionGate` | Financial permission gate |
| `ReportDrillDownService` | Link to expense detail |

## 9.1 Screens

### Expense List Screen (`/financial/expenses`)

- Filter bar: date range, category, payment method, session, status.
- KPI strip: total, count, avg, top category.
- Data table: date, number, category, vendor, amount, method, user, status.
- Actions: New expense, export, refresh.
- Pagination (match Cash Ledger pattern).

### Expense Create Dialog / Screen

- Fields: category, amount, paid_at, payment_method, vendor, notes, session (auto if open), attachment upload.
- Validation: amount > 0; Other → notes required.
- Save as POSTED (v1) or DRAFT (v2 approval).
- Success → invalidate expense providers + cash ledger providers.

### Expense Details Screen

- Read-only header + line metadata.
- Void action (permission-gated) with reason dialog.
- Link to Cash Ledger row (filter by reference).
- Attachment viewer.

### Expense Analytics Section (tab or `/financial/expenses/analytics`)

- Category breakdown chart.
- Trend line.
- Expense vs sales ratio.
- Reuse `advanced_analytics_tabs` patterns.

## 9.2 Navigation

```
Financial Center
├── Dashboard
├── Cash Ledger        (shows EXPENSE events)
├── Expenses           ← new
│   ├── List
│   ├── Create
│   └── Analytics
├── (future modules)
```

---

# Step 10 — Risks & Migration Strategy

| Risk | Severity | Cause | Mitigation |
|------|----------|-------|------------|
| **Double counting in Cash Ledger** | **Critical** | Expense also recorded as supplier PAYMENT | E1: ban dual posting; UI warnings; separate workflows |
| **Double counting purchase vs expense** | **Critical** | Recording inventory buy as expense | Training + category rules; purchases module only for stock |
| **Session reconciliation mismatch** | **High** | Expense paid from drawer without session_id | Prompt for open session; reconciliation report lists unlinked cash expenses |
| **Dashboard KPI conflict** | **High** | Separate SQL for expenses vs ledger | Single `ExpenseRepository` + ledger UNION share totals |
| **Reports cash flow drift** | **High** | `getCashFlow()` still uses `expenses=0` | Phase 4b: wire expenses into analytics or delegate to ledger |
| **P&L double COGS+OpEx** | **Medium** | Treating purchases as expenses | Clear COGS vs OpEx separation in docs and UI |
| **Voided expense in reports** | **Medium** | Cached aggregates | Filter `status = POSTED`; invalidate providers on void |
| **Retroactive date edits** | **Medium** | Changing paid_at after close | Immutable POSTED; void + recreate |
| **Permission sprawl** | **Low** | Too many keys | Start with view/create/void/export |
| **Migration data loss** | **Low** | No historical expenses | Accept greenfield; optional opening balance expense entry |

## Migration strategy (when approved)

1. **Schema migration** (v29+): create tables + seed categories.
2. **Permission seed**: add five expense keys.
3. **Cash Ledger v1.1**: extend UNION + enum (read path only).
4. **Expense CRUD**: write to `expense_records` only.
5. **Dashboard**: add KPI provider reading same totals.
6. **Session v2 formula**: add expense term after policy sign-off.
7. **No backfill** from purchases/refunds — those stay in existing arms.

---

# Step 11 — Readiness Assessment

| Criterion | Score (0–10) | Notes |
|-----------|--------------|-------|
| Cash Ledger extensibility | 8 | UNION pattern proven; add one arm |
| Permission framework | 7 | Sync service exists; need new keys |
| UI component reuse | 8 | Reports widgets mature |
| Session integration | 4 | Formula incomplete today |
| P&L foundation | 5 | Gross profit exists; OpEx missing |
| Analytics harmonization | 4 | Parallel cash flow SQL |
| Data model clarity | 9 | Clean supplemental table design |
| Policy documentation | 6 | Phase 1.5 covers returns/purchases; expenses new |

### **Readiness Score: 58 / 100**

### Missing dependencies

1. Cash Ledger v1 layout/stabilization complete.
2. Session reconciliation policy approved (Phase 3).
3. Decision: accrual vs cash date for P&L vs ledger.
4. Decision: require `session_id` for CASH expenses during open session?
5. Permission keys seeded and assigned to roles.
6. Harmonize `getCashFlow()` with Cash Ledger or deprecate duplicate metrics.

### Required decisions (product sign-off)

| # | Decision | Options |
|---|----------|---------|
| D1 | Ledger timestamp | `paid_at` only (recommended) vs `expense_date` |
| D2 | Session linkage | Mandatory for drawer cash vs optional |
| D3 | Approval workflow | POSTED immediately vs DRAFT→approve |
| D4 | Supplier link | Allow `supplier_id` on expense without AP invoice? (Yes for petty cash to supplier) |
| D5 | Stock write-off link | Phase 4 or defer to Phase 7 |
| D6 | Permission granularity | Full 5 keys vs `analytics.financial` only |

### Recommended implementation order

1. **Schema + seed categories** (migration)
2. **Permission keys + route stubs**
3. **ExpenseRepository** (CRUD + aggregates)
4. **Cash Ledger UNION extension** (`EXPENSE`)
5. **Expense List + Create UI**
6. **Dashboard KPI wiring**
7. **Session formula update** (after D2)
8. **P&L OpEx section**
9. **Analytics harmonization** (`getCashFlow` alignment)
10. **Attachments + approval workflow** (optional v1.1)

---

# Architecture Proposal Summary

```
                    ┌─────────────────────┐
                    │  expense_records    │  ← Single source of truth (NEW)
                    │  expense_categories │
                    └──────────┬──────────┘
                               │
           ┌───────────────────┼───────────────────┐
           ▼                   ▼                   ▼
   ┌───────────────┐   ┌───────────────┐   ┌───────────────┐
   │ Cash Ledger   │   │ Session       │   │ P&L / Dashboard│
   │ UNION EXPENSE │   │ expected cash │   │ OpEx by category│
   └───────────────┘   └───────────────┘   └───────────────┘

   EXISTING (unchanged arms):
   sales_invoices.cash_paid | customer PAYMENT | purchase paid_amount
   supplier PAYMENT | return_audit_logs
```

**Golden rule:** One economic event → one operational document → one ledger arm. Expenses never duplicate purchase or supplier payment paths.

---

# Recommended Next Phase

**Phase 4 — Expense Management (MVP)**

- **Goal:** Record operating cash expenses; visible in Cash Ledger as `EXPENSE`; basic list/create/void; dashboard MTD total.
- **Out of scope MVP:** Attachments, approval workflow, bank reconciliation, stock write-off link.
- **Duration estimate:** 3–4 weeks.
- **Prerequisite:** Cash Ledger v1 stable; D1/D2 decisions signed off.
- **Success criteria:** Expense total in dashboard equals EXPENSE sum in Cash Ledger for same date range; zero double-count with purchases/supplier payments in UAT scenarios.

---

## Appendix A — File references (integration touchpoints)

| Area | Path |
|------|------|
| Cash Ledger UNION | `lib/features/financial/repositories/financial_ledger_repository.dart` |
| Event types | `lib/features/financial/models/cash_ledger_event_type.dart` |
| Session close | `lib/features/pos/providers/pos_provider.dart` |
| Cash flow (placeholder) | `lib/features/reports/repositories/advanced_analytics_repository.dart` |
| Permissions | `lib/features/auth/permissions/permission_keys.dart` |
| Financial route | `lib/app.dart`, `route_permissions.dart` |
| Report UI reuse | `lib/features/reports/core/widgets/` |

---

| Version | Date | Notes |
|---------|------|-------|
| 1.0 | June 2026 | Initial expense management architecture audit — analysis only |