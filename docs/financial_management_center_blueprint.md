# Financial Management Center (Accounting Lite)

## Phase 0 - Architecture and Integration Blueprint

| Field | Value |
|-------|-------|
| **Project** | Lez POS |
| **Database** | SQLite via Drift (lib/core/database/app_database.dart, schema v28) |
| **Date** | June 8, 2026 |
| **Status** | Analysis only - no implementation, schema changes, or migrations |

---

## Executive Summary

Lez POS already tracks money across operational modules, but **financial data is fragmented** across invoice headers, account ledgers, session reconciliation fields, and audit logs. There is **no unified cash ledger**, **no expenses module**, and **no single payments table**.

The Financial Management Center should **integrate with existing modules as the source of truth** rather than duplicate transactional data. The recommended architecture is a **hybrid model**: operational tables remain authoritative for business documents; a **derived + supplemental ledger** unifies cash movements for reporting, reconciliation, and future P and L.

---

## Module Inventory (Existing System)

| # | Module | Primary Tables | DAO(s) | Service(s) / Repository |
|---|--------|----------------|--------|-------------------------|
| 1 | POS Sales | sales_invoices, sale_items, stock_ledger | SalesDao | PosSaleService, PosRepository, CartNotifier |
| 2 | POS Sessions | pos_sessions | SalesDao | PosSessionNotifier, PosRepository |
| 3 | Cash Drawer / Close | pos_sessions, sales_invoices | SalesDao | PosSessionNotifier, session_dialog.dart |
| 4 | Customer Debts | customer_accounts, customer_transactions | CustomerAccountsDao | CustomerAccountService, PosRepository.settleDebt() |
| 5 | Supplier Debts | supplier_accounts, supplier_transactions | SupplierAccountsDao | SupplierAccountService |
| 6 | Payments | distributed - no unified table | - | See Task 1 |
| 7 | Purchases | purchase_invoices, purchase_items, stock_ledger | PurchasesDao | PurchasesRepository, PurchaseService (unused by UI) |
| 8 | Customer Returns | customer_returns, return_audit_logs, sale_item_returns | ReturnsDao, ReturnAuditLogsDao | PosSaleService, PartialReturnService |
| 9 | Supplier Returns | supplier_returns, supplier_return_items | ReturnsDao | UI placeholder only |
| 10 | Activity Logs | activity_logs, logs | ActivityLogsDao, LogsDao | ActivityLoggerService |
| 11 | Reports | read-only queries | - | ReportsRepository, AdvancedAnalyticsRepository |
| 12 | Dashboard KPIs | sales_invoices, sale_items | SalesDao | reportDailySalesProvider, dashboard_screen.dart |

---
## Task 1 - Money Flow Map

### Money In (Inflows)

| Flow | Source Module | Table(s) | DAO | Service / Entry Point | Business Logic |
|------|---------------|----------|-----|----------------------|----------------|
| Cash sales | POS Sales | sales_invoices | SalesDao | PosSaleService.processSale() | cash_paid; session_id; excluded when returned |
| Card sales | POS Sales | sales_invoices | SalesDao | Same | card_paid; in cash-flow but not drawer expected cash |
| Mixed payment | POS Sales | sales_invoices | SalesDao | PaymentInfo in cart_item.dart | payment_method = MIXED |
| Debt collections | Customer Debts | customer_transactions | CustomerAccountsDao | CustomerAccountService, settleDebt() | Type PAYMENT; logged CUSTOMER_PAYMENT |
| Opening float | POS Sessions | pos_sessions | SalesDao | PosSessionNotifier.openSession() | opening_cash at shift start |
| Credit sales | POS / Customer Debts | sales_invoices, customer_transactions | CustomerAccountsDao | PosSaleService debt_amount > 0 | Type SALE; not cash until collected |
| Other income | - | - | - | - | Does not exist |

### Money Out (Outflows)

| Flow | Source Module | Table(s) | DAO | Service / Entry Point | Business Logic |
|------|---------------|----------|-----|----------------------|----------------|
| Purchase payments (at invoice) | Purchases | purchase_invoices | PurchasesDao | savePurchaseInvoice() | paid_amount on header; not supplier PAYMENT row |
| Supplier payments | Supplier Debts | supplier_transactions | SupplierAccountsDao | SupplierAccountService | Type PAYMENT negative |
| Purchase debt accrual | Purchases | supplier_transactions | PurchasesDao | savePurchaseInvoice() | debt_amount as PURCHASE |
| Customer refunds (cash) | Customer Returns | return_audit_logs | ReturnsDao | returnFullSaleInvoice() | returned_amount; not in session expected cash |
| Customer refunds (credit) | Customer Returns | customer_transactions | CustomerAccountsDao | returnFullSaleInvoice() | debt_amount reversed only |
| Supplier returns | Supplier Returns | supplier_returns | ReturnsDao | saveSupplierReturn() | Stock only; no payable credit |
| Expenses | - | - | - | - | Does not exist (expenses = 0 in getCashFlow) |

### Current Cash-Flow Formula

From AdvancedAnalyticsRepository.getCashFlow():

    Inflow  = SUM(cash_paid) + SUM(card_paid) + ABS(customer PAYMENT)
    Outflow = ABS(supplier PAYMENT) + 0
    Net     = Inflow - Outflow

Gaps: purchase paid_amount missing; return refunds not subtracted; expenses zero.

### Module Notes

**POS Sales:** CartNotifier.checkout -> PosSaleService.processSale -> SalesDao.saveSaleInvoice. Methods CASH, CARD, MIXED, DEBT.

**POS Sessions:** expectedCash = opening_cash + SUM(cash_paid); cash_difference = closing_cash - expectedCash.

**Customer ledger:** SALE (+), PAYMENT (-), RETURN (-), ADJUSTMENT (+/-). Balance from immutable sum.

**Supplier ledger:** PURCHASE (+), PAYMENT (-), ADJUSTMENT (+/-). PurchasesDao posts debt_amount only.

**Payments (distributed):** sales_invoices (cash/card), customer_transactions (collections), supplier_transactions (payments), purchase_invoices.paid_amount.

**Returns:** Full return reverses debt only. Partial = stock + audit. Supplier returns = stock only.

**Reports:** ReportsRepository + AdvancedAnalyticsRepository (cashFlow, profitAnalysis, executiveDashboard).

**Dashboard:** SalesDao.getDailyTotals() for sales, count, profit today.

---
## Task 2 - Cash Ledger Readiness

### Can a Cash Ledger Be Built Without Duplicating Transactions?

Partially yes. Most events can be derived via SQL UNION. Gaps: payment metadata, purchase paid on header only, refunds without cash/card split, no expenses/other income.

### Financial Event Readiness Matrix

| Event | Source | Amount | Timestamp | User | Session | Reference | Ready? |
|-------|--------|--------|-----------|------|---------|-----------|--------|
| Cash sale | sales_invoices.cash_paid | Yes | sale_date | Yes | Yes | invoice | Strong |
| Card sale | sales_invoices.card_paid | Yes | Yes | Yes | Yes | invoice | Strong |
| Customer payment | customer_transactions PAYMENT | Yes | created_at | No | No | No | Weak |
| Supplier payment | supplier_transactions PAYMENT | Yes | Yes | No | No | Optional | Weak |
| Purchase cash paid | purchase_invoices.paid_amount | Yes | purchase_date | Yes | No | invoice | Partial |
| Full return | return_audit_logs | Yes | Yes | Yes | Yes | invoice | Partial |
| Session open/close | pos_sessions | Yes | Yes | Yes | self | session | Strong |

**Recommendation:** Virtual ledger (UNION) + supplemental table for expenses, other income, and native adjustments.

---

## Task 3 - Gap Analysis

| Future Module | What Exists | What Is Missing | Integration Risks |
|---------------|-------------|-----------------|-------------------|
| Cash Ledger | Invoice splits, getCashFlow() | Unified model; user/session on payments | Double-counting |
| Expenses | UI placeholder | Categories, records | Incomplete outflow |
| Other Income | - | Full module | Separate from POS revenue |
| Financial Dashboard | KPIs, executive panel | Cash hub, AR/AP snapshot | Ledger accuracy |
| Profit and Loss | getProfitAnalysis() gross | Expenses, net P and L | Partial returns |
| Cash Reconciliation | pos_sessions.cash_difference | Formula gaps; period runs | cash_returns UI/DAO mismatch |

### Critical Gaps

1. No unified payments table (six patterns)
2. PurchaseService vs PurchasesDao divergence
3. Returns do not reverse cash/card
4. Partial returns: no financial reversal
5. Supplier returns: no payable credit
6. Payments lack user_id and session_id
7. Session close ignores collections and refunds

---

## Task 4 - Source of Truth Design

### Option A: Read Existing Transactions Directly

Pros: No new tables, always current. Cons: Complex queries, metadata gaps, hard to add expenses.

### Option B: Materialized Financial Ledger

Pros: Single query surface. Cons: Duplication, sync drift, backfill required.

### Option C: Hybrid (Recommended)

| Layer | Source of Truth |
|-------|-----------------|
| Operational documents | sales_invoices, purchase_invoices, returns |
| Receivables / payables | customer_transactions, supplier_transactions |
| Cash movements | Read-only views + supplemental ledger |
| Reconciliation | pos_sessions + cash_reconciliation_runs (future) |

Pattern: Derived UNION for historical data; native writes for expenses, other income, adjustments.

---
## Task 5 - Database Impact Analysis (Future Only)

Do NOT create in Phase 0. Planning only.

| Table | Purpose | Relationships |
|-------|---------|---------------|
| financial_categories | Expense/income classification | Self-ref parent optional |
| expense_records | Operating cash outflows | categories, users, optional sessions |
| other_income_records | Non-POS cash inflows | categories, users, optional sessions |
| cash_ledger_entries | Native cash log | users, sessions; polymorphic source ref |
| cash_reconciliation_runs | Reconciliation header | sessions optional, users |
| cash_reconciliation_lines | Expected vs actual | reconciliation runs |

Optional columns: user_id, session_id, payment_method on customer_transactions and supplier_transactions.

Proposed views: v_cash_in_sales, v_cash_in_collections, v_cash_out_supplier_payments, v_cash_out_purchase_paid, v_cash_out_returns.

---

## Task 6 - Permission Model

### Recommended Permissions

| Permission | Usage |
|------------|-------|
| financial.view | Read ledger, dashboard, P and L, reconciliation history |
| financial.manage | Categories, settings, fiscal periods, export |
| expenses.manage | Create/edit/void expense records |
| income.manage | Create/edit/void other income records |
| cash_reconciliation.manage | Run and finalize reconciliations |

Integrates with existing analytics.financial, reports.view, PermissionRouteGuard in route_permissions.dart.

Hierarchy: financial.manage includes financial.view; write permissions require financial.view.

---

## Task 7 - Implementation Roadmap

### Phase 1 - Cash Ledger

- **Complexity:** Medium (3-4 weeks)
- **Dependencies:** None
- **Integration:** SalesDao, CustomerAccountsDao, SupplierAccountsDao, PurchasesDao, ReturnAuditLogsDao, AdvancedAnalyticsRepository
- **Pre-work:** Fix getSessionSummary cash_returns; document double-count rules

### Phase 2 - Expense Management

- **Complexity:** Medium (2-3 weeks)
- **Dependencies:** Phase 1, financial_categories
- **Integration:** getCashFlow(), ActivityLoggerService

### Phase 3 - Other Income

- **Complexity:** Low-Medium (1-2 weeks)
- **Dependencies:** Phase 2 categories
- **Integration:** Cash ledger, P and L

### Phase 4 - Financial Dashboard

- **Complexity:** Medium (2-3 weeks)
- **Dependencies:** Phases 1-3
- **Integration:** DailyClosingService, account balances

### Phase 5 - Profit and Loss

- **Complexity:** Medium-High (3-4 weeks)
- **Dependencies:** Phases 1-4
- **Integration:** getProfitAnalysis(), getReturnImpact()

### Phase 6 - Cash Reconciliation

- **Complexity:** High (3-4 weeks)
- **Dependencies:** Phases 1-2, sessions
- **Integration:** pos_sessions, PosSessionNotifier, operations alerts
- **Pre-work:** user_id/session_id on payment transactions

---

## Target Formulas

Session expected cash (target):
    opening_cash + cash_sales + collections - refunds - expenses (session-linked)

Net cash flow (target):
    inflow = cash_sales + card_sales + collections + other_income
    outflow = supplier_payments + purchase_paid + refunds + expenses

Net profit (target):
    gross_profit - operating_expenses + other_income

---

## Appendix - Key Files

| Area | Path |
|------|------|
| Database schema | lib/core/database/app_database.dart |
| Sales and sessions | lib/core/database/daos/sales_dao.dart |
| Sale orchestration | lib/core/services/pos_sale_service.dart |
| Session close | lib/features/pos/providers/pos_provider.dart |
| Customer ledger | lib/core/database/daos/customer_accounts_dao.dart |
| Supplier ledger | lib/core/database/daos/supplier_accounts_dao.dart |
| Purchases | lib/core/database/daos/purchases_dao.dart |
| Returns | lib/core/database/daos/returns_dao.dart |
| Cash flow | lib/features/reports/repositories/advanced_analytics_repository.dart |
| Permissions | lib/features/auth/permissions/permission_keys.dart |

---

## Document Control

| Version | Date | Notes |
|---------|------|-------|
| 1.0 | 2026-06-08 | Phase 0 blueprint - no code changes |

Next step: Review and approve before Phase 1 implementation.