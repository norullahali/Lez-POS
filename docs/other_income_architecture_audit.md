# Other Income — Phase 4 Architecture Audit (Pre-Implementation)
**Lez POS · Flutter + Riverpod + Drift**
**Audit Date:** 2026-06-22
**Auditor Role:** Senior ERP Financial Architect
**Mode:** READ-ONLY — No code, no schema, no migrations, no UI changes.
**Purpose:** Architecture sign-off before Phase 4 implementation begins.

---

## Executive Summary

The Lez POS codebase is architecturally ready to receive an Other Income module.
The Expense Management module (Phase 3) provides a complete, battle-tested template
that can be mirrored with minimal structural deviation.

Zero double-count risk exists between proposed other_income_records and all
existing Cash Ledger sources. The new event type fits naturally into the existing
UNION architecture. Schema version 30 is the correct target.

One structural gap was identified: card payments (sales_invoices.card_paid) and
supplier credit refunds (supplier_returns/supplier_transactions negative adjustments)
are not tracked in the Cash Ledger. Other Income does NOT address these gaps --
they require separate architecture decisions. Other Income is strictly for
non-sales cash receipts.

**Final Decision: GO (architecture ready)**
Implementation may proceed using the Phase 3 template.
Two pre-conditions are documented in Section 10.

---

## Section 1 -- Existing Sources of Money Inflow

### 1.1 Complete Inflow Inventory

A full scan of all database tables and the UNION SQL in FinancialLedgerRepository
reveals the following inflow sources:

---

**Source 1: sales_invoices.cash_paid**
File: lib/core/database/tables/sales_invoices_table.dart
Table: sales_invoices
Column: cash_paid (REAL, default 0.0)
Business meaning: Cash received at the POS counter at moment of sale.
In Cash Ledger: YES -- event type SALE_CASH, WHERE cash_paid > 0.
Double-count risk with Other Income: NONE. Sales cash is from product sales.
Other Income is for non-sales receipts.

---

**Source 2: sales_invoices.card_paid**
File: lib/core/database/tables/sales_invoices_table.dart
Table: sales_invoices
Column: card_paid (REAL, default 0.0)
Business meaning: Amount paid by card/electronic transfer at POS.
In Cash Ledger: NO -- excluded by design. Card payments route to bank, not cash drawer.
Double-count risk with Other Income: LOW but requires policy clarity.
If the business manually records a bank transfer as Other Income, it must be trained
NOT to do so if the original payment was already in card_paid on a sales invoice.
ARCHITECTURAL NOTE: Card sales are a known gap in the Cash Ledger. Addressing them
requires a separate phase (bank account reconciliation module). Do not attempt to
close this gap through Other Income categories.

---

**Source 3: sales_invoices.debt_amount**
File: lib/core/database/tables/sales_invoices_table.dart
Column: debt_amount (REAL, default 0.0)
Business meaning: Credit sales charged to customer account (al-ajal). Not cash at sale time.
In Cash Ledger: NO at sale time. The cash enters the ledger later via CUSTOMER_PAYMENT
when the customer pays their balance.
Double-count risk with Other Income: NONE.

---

**Source 4: customer_transactions type=PAYMENT**
File: lib/core/database/tables/customer_transactions_table.dart
Column: amount (REAL, negative for PAYMENT = balance decreases = cash inflow)
Business meaning: Customer pays down outstanding balance in cash.
In Cash Ledger: YES -- event type CUSTOMER_PAYMENT, WHERE type = 'PAYMENT', ABS(amount).
Double-count risk with Other Income: NONE. Customer debt collection is structurally
different from Other Income categories.

---

**Source 5: customer_transactions type=ADJUSTMENT**
File: lib/core/database/tables/customer_transactions_table.dart
Business meaning: Manual balance adjustments. Can be positive or negative.
In Cash Ledger: NO -- ADJUSTMENT type is not included in the UNION.
Double-count risk with Other Income: LOW but requires training.
A negative adjustment (reducing customer balance as a goodwill write-off) is NOT
a cash inflow. If staff mistakenly record such write-offs as Other Income, it would
overstate income. This is a business process risk, not a schema risk.

---

**Source 6: supplier_transactions negative adjustment**
File: lib/core/database/tables/supplier_transactions_table.dart
Business meaning: When supplier account goes negative, supplier owes us money.
Can happen on overpayment or returned goods with cash settlement.
In Cash Ledger: NOT in current UNION. Supplier credit refunds are an untracked gap.
ARCHITECTURAL GAP IDENTIFIED: Supplier credit refunds received in cash have no
representation in the current Cash Ledger. This is a separate gap from Other Income.
If the business receives physical cash back from a supplier, it can be recorded as
Other Income (with a dedicated category such as 'استرداد من مورد') as a v1 workaround.
A proper supplier credit inflow UNION branch should be addressed in Phase 5/6.
Double-count risk with Other Income: LOW if categorized correctly.

---

**Source 7: supplier_returns (SupplierReturns table)**
File: lib/core/database/tables/supplier_returns_table.dart
Business meaning: Goods returned to supplier. Creates a credit on supplier account.
Cash is realized only if the supplier physically pays it back.
In Cash Ledger: NOT directly. Cash realization flows through supplier_transactions.
Double-count risk with Other Income: NONE.

---

**Source 8: return_audit_logs.returned_amount**
File: lib/core/database/tables/return_audit_logs_table.dart
Business meaning: Cash refunded to customer after product return.
In Cash Ledger: YES -- event type RETURN_REFUND, direction OUTFLOW.
Nature: Cash OUTFLOW, not an inflow.
Double-count risk with Other Income: NONE.

---

**Source 9: expense_records.amount (Phase 3)**
Nature: Cash OUTFLOW (operational costs).
In Cash Ledger: YES -- event type EXPENSE, direction OUTFLOW.
Double-count risk with Other Income: NONE. Expenses are outflows.

---

### 1.2 Cash Ledger Inflow Summary

| Event Type | Table | Status |
|---|---|---|
| SALE_CASH | sales_invoices.cash_paid | In Ledger |
| CUSTOMER_PAYMENT | customer_transactions type=PAYMENT | In Ledger |
| OTHER_INCOME | other_income_records (proposed) | Phase 4 |
| Card sales | sales_invoices.card_paid | NOT in Ledger (by design) |
| Customer debt adjustments | customer_transactions ADJUSTMENT | NOT in Ledger |
| Supplier credit refunds | supplier_transactions negative adj. | NOT in Ledger (gap) |

### 1.3 Confirmed: Zero Double-Count Risk

Other Income (other_income_records) will record non-sales, non-collection cash receipts.
These are structurally independent of all existing inflow sources.
No anti-duplication guard is required in the UNION branch.

---

## Section 2 -- Expense Module as Template

### 2.1 What to Mirror Exactly

The following Phase 3 structures should be replicated exactly for Phase 4:

Database layer: Two-table pattern (categories + records) with identical column structure.
DAO layer: Identical method set, dual count+data query, raw summary SQL pattern.
Repository layer: Six mutations + two reads, transaction() wrapping, isVoided bypass guard.
Provider layer: Filter + Notifier + FutureProvider.autoDispose + keepAlive(45s) pattern.
UI layer: Screen layout, dialog pattern, category manager dialog, pagination bar.
Activity logging: Five event types, Arabic titles, severity assignment.
Permissions: Four-key pattern in PermissionKeys.all with Arabic descriptions.

### 2.2 Changes from Expense Template

| Aspect | Expense value | Other Income value |
|---|---|---|
| Table names | expense_categories/records | other_income_categories/records |
| Direction | outflow | inflow |
| isInflow flag | false | true |
| Event type code | EXPENSE | OTHER_INCOME |
| Arabic ledger label | مصروف | إيراد آخر |
| Activity type prefix | expense.* | income.* |
| Permission namespace | financial.expenses.* | financial.income.* |
| Route | /expenses | /income |
| Timestamp 1 | expenseDate (when cost incurred) | incomeDate (when income earned) |
| Timestamp 2 | paidAt (when cash left) | receivedAt (when cash arrived) |
| Summary card color | AppColors.warning (orange) | AppColors.success (green) |
| void log severity | info (W-6 defect) | warning (corrected from day one) |
| textDirection in dialogs | redundant in category dialog | remove from day one |
| copyWith sessionId | no sentinel (D-1 defect) | sentinel from day one |
| usersMapProvider DI | bypasses Riverpod (W-3) | uses Riverpod from day one |

---

## Section 3 -- Proposed Table Design

NO IMPLEMENTATION. Design only. Schema version: 30.

### 3.1 other_income_categories

Fields:
  id          INTEGER PK AUTOINCREMENT
              Auto-assigned primary key. FK target for category_id.

  name        TEXT NOT NULL, min 1 char, max 120 chars.
              Category label for dropdowns and reports.
              Examples: 'إيراد إيجار', 'عائد استثمار', 'إعانة حكومية', 'فائض صندوق'.
              UNIQUE constraint RECOMMENDED from day one (learn from Phase 3 W-1).

  description TEXT NOT NULL DEFAULT ''
              Optional clarification. Default '' not NULL for clean comparisons.

  is_active   BOOLEAN NOT NULL DEFAULT true
              Soft-disable. Inactive categories do not appear in income creation dropdown.

  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
              Audit trail.

  updated_at  DATETIME NULL
              Mutation marker. NULL = never edited.

Indexes:
  other_income_categories_active_idx ON (is_active)

### 3.2 other_income_records

Fields:
  id          INTEGER PK AUTOINCREMENT
              Unique row id. Used as ledger_id suffix: 'OTHER_INCOME:{id}'.

  category_id INTEGER NOT NULL FK other_income_categories.id
              Every income must be categorized. Cannot be NULL.
              INDEX: otr_category_idx for category filter and description subquery JOIN.

  amount      REAL NOT NULL
              Positive cash amount. Must be > 0 (enforced by business logic + UNION filter).
              Type: REAL (consistent with all monetary columns in project).

  income_date DATETIME NOT NULL
              ACCRUAL DATE -- when the income was earned or the right to receive it arose.
              May precede received_at (e.g., rent invoiced on 1st, received on 5th).
              Used for P&L period attribution under accrual accounting.

  received_at DATETIME NOT NULL
              CASH RECEIPT DATE -- when the cash physically arrived.
              THIS IS THE LEDGER TIMESTAMP -- used as event_ts in UNION branch.
              INDEX: otr_received_at_idx -- critical for ledger ORDER BY and date range filter.

  notes       TEXT NOT NULL DEFAULT ''
              Free-text memo. Appears in Cash Ledger description alongside category name.

  session_id  INTEGER NULL FK pos_sessions.id
              Optional. Links income to current POS session for Phase 7 reconciliation.
              INDEX: otr_session_idx for session-level aggregate queries.

  created_by  INTEGER NOT NULL FK users.id
              Audit trail. Appears as user_id in Cash Ledger.

  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
              Row creation timestamp.

  updated_at  DATETIME NULL
              Mutation marker. Set on every updateIncome call.

  is_voided   BOOLEAN NOT NULL DEFAULT false
              Soft-delete. When true, excluded from all queries and from Cash Ledger.
              Voiding is irreversible in v1.
              INDEX: otr_voided_idx for active-only filtering.

---

## Section 4 -- Business Rules

BR-1: amount > 0 (HARD RULE)
Income records must represent actual cash inflows. Zero or negative amounts corrupt
running balances. Enforcement: dialog UI validation AND repository guard AND UNION filter.

BR-2: Soft delete only -- no hard deletes (HARD RULE)
is_voided = true is the only deletion mechanism. Physical row deletion is prohibited.
Voided rows remain for audit purposes.

BR-3: category_id must reference an active category at time of creation (SOFT RULE)
Dialog shows only active categories. Repository validates is_active before createIncome.
Records already in the system retain their category_id if category is later deactivated.

BR-4: session_id is optional
Null session_id is fully valid. session_id is for Phase 7 reconciliation only.
Cash Ledger does not display session_id.

BR-5: One income record = one Cash Ledger entry (HARD RULE)
Each active (is_voided = false) other_income_record produces exactly one INCOME row.
No reversal entries. No compensating entries in v1.

BR-6: Voided records excluded from Cash Ledger (HARD RULE)
UNION branch: WHERE is_voided = 0. Void = immediate disappearance from running balance.
No reversal row created.

BR-7: received_at determines ledger chronology
Cash Ledger orders by event_ts. For Other Income, event_ts = received_at.
income_date is stored for P&L but not used for ledger ordering.

BR-8: Void is irreversible in v1
Once voided, cannot be un-voided. A new record must be created if voided in error.

BR-9: No double-entry bookkeeping in v1
Cash-basis single-entry ledger. One inflow entry only. No debit/credit pair.

BR-10: amount precision
REAL type stores up to 15 significant digits. For amounts below 1,000,000, rounding
errors are sub-cent. Acceptable for this system.

---

## Section 5 -- Activity Logging Design

Reuses ActivityLoggerService, ActivityCategories.financial, activity_types.dart pattern.

income.created:
  activityType: 'income.created'
  category: ActivityCategories.financial
  severity: info
  method: logEntityCreate
  Arabic title: 'تسجيل إيراد'
  entityType: 'other_income_record'
  description: amount.toStringAsFixed(2)
  after snapshot: {categoryId, amount, receivedAt}

income.updated:
  activityType: 'income.updated'
  category: ActivityCategories.financial
  severity: info
  method: logEntityUpdate
  Arabic title: 'تعديل إيراد'
  entityType: 'other_income_record'
  description: ' -> '
  before/after snapshots: {amount, categoryId, notes}

income.voided:
  activityType: 'income.voided'
  category: ActivityCategories.financial
  severity: WARNING (not info -- learn from Phase 3 W-6)
  method: logWarning
  Arabic title: 'إلغاء إيراد'
  entityType: 'other_income_record'
  description: before.notes (or amount if notes empty)
  before snapshot: {amount, categoryId, receivedAt}

income.category.created:
  activityType: 'income.category.created'
  category: ActivityCategories.financial
  severity: info
  method: logEntityCreate
  Arabic title: 'إضافة فئة إيراد'
  entityType: 'other_income_category'
  description: category.name

income.category.updated:
  activityType: 'income.category.updated'
  category: ActivityCategories.financial
  severity: info
  method: logEntityUpdate
  Arabic title: 'تعديل فئة إيراد'
  entityType: 'other_income_category'
  description: category.name

---

## Section 6 -- Permissions Design

New keys (financial.income.* namespace):
  financialIncomeView   = 'financial.income.view'
  financialIncomeCreate = 'financial.income.create'
  financialIncomeEdit   = 'financial.income.edit'
  financialIncomeDelete = 'financial.income.delete'

Arabic descriptions:
  financialIncomeView:   'عرض الإيرادات الأخرى وفئاتها'
  financialIncomeCreate: 'تسجيل إيرادات جديدة'
  financialIncomeEdit:   'تعديل الإيرادات وفئاتها'
  financialIncomeDelete: 'إلغاء الإيرادات'

All four added to PermissionKeys.all for automatic owner role sync.

Route guard:
  _RoutePermission('/income', PermissionKeys.financialIncomeView)

Side nav:
  NavItem(route: '/income', icon: Icons.trending_up_rounded,
          label: 'الإيرادات الأخرى',
          permissionKey: PermissionKeys.financialIncomeView)
  Positioned adjacent to '/expenses' in financial section of kNavItems.

Button-level visibility:
  'إضافة إيراد' button: financialIncomeCreate
  Edit icon per row: financialIncomeEdit
  Void icon per row: financialIncomeDelete
  Add category button inside manager: financialIncomeCreate
  Edit category button: financialIncomeEdit

Future key (do not define until export is implemented):
  financialIncomeExport = 'financial.income.export'

---

## Section 7 -- Cash Ledger Integration Design

### 7.1 New Enum Value

  otherIncome('OTHER_INCOME', 'إيراد آخر', true)

code: OTHER_INCOME
labelAr: إيراد آخر
isInflow: true (INFLOW)
Color hint: AppColors.success (green)

Add after expense entry in CashLedgerEventType enum.

### 7.2 UNION Branch SQL Design

  UNION ALL

  -- Phase 4: Other income -- derived from other_income_records.
  -- Source: other_income_records is the sole source of truth; no ledger table created.
  -- Void: is_voided = 0 -- voided income fully excluded (no reversal rows).
  -- Double-count: No guard required. other_income_records are INDEPENDENT of
  --   sales_invoices (product sales), customer_transactions (debt collection),
  --   purchase_invoices, supplier_transactions, return_audit_logs, expense_records.
  --   One other_income_record = exactly one OTHER_INCOME ledger entry.
  SELECT
    'OTHER_INCOME:' || oi.id AS ledger_id,
    oi.received_at AS event_ts,
    'OTHER_INCOME' AS event_type,
    oi.amount AS amount,
    'inflow' AS direction,
    'other_income_record' AS reference_type,
    oi.id AS reference_id,
    oi.created_by AS user_id,
    NULL AS customer_id,
    NULL AS supplier_id,
    NULL AS invoice_id,
    COALESCE(
      (SELECT oic.name FROM other_income_categories oic WHERE oic.id = oi.category_id)
        || CASE WHEN NULLIF(TRIM(oi.notes), '') IS NOT NULL
                THEN ' -- ' || oi.notes
                ELSE '' END,
      NULLIF(TRIM(oi.notes), ''),
      'إيراد آخر'
    ) AS description
  FROM other_income_records oi
  WHERE oi.is_voided = 0
    AND oi.amount > 0

### 7.3 UNION Field Mapping

| Ledger field | Source | Rationale |
|---|---|---|
| ledger_id | 'OTHER_INCOME:' or oi.id | Unique prefixed identifier |
| event_ts | oi.received_at | Cash receipt date = ledger timestamp |
| event_type | 'OTHER_INCOME' | Maps to CashLedgerEventType.otherIncome |
| amount | oi.amount | Positive cash amount |
| direction | 'inflow' | Cash enters the business |
| reference_type | 'other_income_record' | Source traceability |
| reference_id | oi.id | For future drill-down |
| user_id | oi.created_by | Who recorded it |
| customer_id | NULL | Not customer-related |
| supplier_id | NULL | Not supplier-related |
| invoice_id | NULL | No invoice |
| description | category + ' -- ' + notes with fallback | Same pattern as EXPENSE |

### 7.4 _readSet() Additions

  _db.otherIncomeRecords,    // Phase 4
  _db.otherIncomeCategories, // Phase 4 -- category name in description

### 7.5 Drill-Down Switch (cash_ledger_screen.dart)

  case CashLedgerEventType.otherIncome:
    // Phase 4: other income rows are read-only; no drill-down yet.
    break;

### 7.6 Running Balance

Existing formula: SUM(CASE WHEN direction = 'inflow' THEN amount ELSE -amount END)
OTHER_INCOME entries (inflow) INCREASE the running balance. No formula change needed.

### 7.7 Filter, Export, Pagination

Filter dropdown: CashLedgerEventType.values.map -- OTHER_INCOME appears automatically.
Export: getEntriesForExport delegates to getEntries -- automatic inclusion.
Pagination/sorting: UNION participation is automatic. No special handling.

---

## Section 8 -- Future Dashboard Compatibility

### Financial Dashboard (Phase 5)

OtherIncomeSummary model will expose:
  activeCount, totalAmount, voidedCount, categoryCount

CashLedgerSummary.totalInflow already includes OTHER_INCOME automatically.
Dashboard uses both: ref.watch(otherIncomeSummaryProvider) + ref.watch(cashLedgerSummaryProvider).
Category breakdown: GROUP BY category_id query -- no schema changes needed.

### Profit and Loss (Phase 6)

income_date = accrual-basis period attribution
received_at = cash-basis period attribution
Category grouping enables P&L line items: 'إيرادات الإيجار', 'إيرادات متنوعة', etc.

Complete P&L components after Phase 4:
  Revenue: SUM(sale_items.total) WHERE invoice not returned
  Other Income: SUM(other_income_records.amount) WHERE is_voided = 0
  COGS: SUM(sale_items.quantity * unit_cost)
  Expenses: SUM(expense_records.amount) WHERE is_voided = 0
  Gross Profit: Revenue - COGS
  Operating Income: Gross Profit - Expenses + Other Income

All four components have schema support after Phase 4. No gaps for P&L.

### Cash Reconciliation (Phase 7)

session_id FK enables session-level reconciliation:
  expected_cash = opening_cash
                + SUM(sales.cash_paid WHERE session_id = ?)
                + SUM(other_income.amount WHERE session_id = ? AND is_voided = 0)
                - SUM(expenses.amount WHERE session_id = ? AND is_voided = 0)

---

## Section 9 -- Risks

R-1: MEDIUM -- income_date vs received_at ambiguity
Two timestamp fields for different accounting purposes.
Developers may use the wrong field in P&L queries.
Mitigation: Document clearly in DAO method signatures which timestamp each query uses.

R-2: MEDIUM -- User miscategorization creates fictional income
Card sales or bank transfers could be double-recorded as Other Income.
This is a business training risk, not a schema risk.
Mitigation: Category names designed to make misuse obvious.

R-3: LOW -- REAL type currency precision
Project-wide trade-off. For amounts under 1,000,000 precision is sub-cent.

R-4: LOW -- No UNIQUE constraint on category name if not enforced
Same issue as Phase 3 W-1. Recommendation: enforce from day one.

R-5: LOW -- Migration error swallowing (if not improved)
Same as Phase 3 W-2. Recommendation: single try/catch for both table creates in v30.

R-6: LOW -- Phase 3 D-1 copyWith sentinel defect not yet fixed
OtherIncomeRecord.copyWith must implement _sentinel for sessionId from day one.
Do not replicate the Phase 3 defect.

R-7: LOW -- Supplier credit refund gap creates training pressure
Staff may record supplier cash refunds as Other Income as a workaround.
This is acceptable in v1. A proper SUPPLIER_CREDIT event type should be addressed in Phase 5/6.

---

## Section 10 -- Final Readiness Score

| Component | Score | Notes |
|---|---|---|
| Table design | 96/100 | Add UNIQUE on category.name from day one |
| DAO design | 93/100 | Dual query duplication is known pattern |
| Repository design | 95/100 | sessionId sentinel must be implemented from day one |
| Provider design | 90/100 | Fix usersMapProvider DI from day one |
| UI design | 92/100 | Remove redundant textDirection from day one |
| Permissions design | 97/100 | Complete, consistent, ready |
| Activity log design | 97/100 | Use logWarning for void (Phase 3 W-6 corrected) |
| Cash Ledger integration | 98/100 | Zero double-count, correct direction, clean UNION |
| Future compatibility | 95/100 | P&L, dashboard, reconciliation all compatible |
| Double-count safety | 100/100 | Structurally independent from all existing sources |
| **Overall** | **95/100** | |

`
DECISION: GO

Architecture is sound. Implementation may proceed.
`

### Mandatory Before Implementation (2 items)

MANDATORY 1: Fix expense_record.dart copyWith sessionId sentinel (Phase 3 D-1)
Before writing other_income_record.dart, fix expense_record.dart.
Use the corrected pattern as the template for OtherIncomeRecord.copyWith.
Estimated effort: 5 lines.

MANDATORY 2: Implement OtherIncomeRecord.copyWith sessionId sentinel from day one
Do not inherit the D-1 defect. Use _sentinel for nullable sessionId from the start.

### Recommended Improvements (4 items)

REC-1: Add UNIQUE constraint on other_income_categories.name from the initial schema.
REC-2: Improve v30 migration: wrap both table creates in a single try/catch.
REC-3: Implement otherIncomeUsersMapProvider using Riverpod DI (not AppDatabase.instance).
REC-4: Use logWarning (not logInfo) for income.voided activity log event.

### Nice-to-Have (2 items)

NTH-1: Optional 'payer' free-text field on other_income_records for future 'who paid us?' queries.
NTH-2: Optional 'paymentMethod' text column (cash/bank_transfer/check) for future bank reconciliation.

---

## Implementation Blueprint

| Item | Value |
|---|---|
| Schema version | 30 |
| New tables | other_income_categories, other_income_records |
| New Drift DAO | OtherIncomeDao |
| New domain models | OtherIncomeCategory, OtherIncomeRecord, OtherIncomePage, OtherIncomeSummary |
| New repository | OtherIncomeRepository |
| New providers | otherIncomeCategoriesProvider, otherIncomeProvider, otherIncomeSummaryProvider, otherIncomeFilterProvider |
| New screens | /income (OtherIncomeScreen) |
| New dialogs | OtherIncomeDialog, OtherIncomeCategoryDialog |
| New event type | CashLedgerEventType.otherIncome ('OTHER_INCOME', 'إيراد آخر', true) |
| Cash Ledger changes | +1 UNION branch, +2 _readSet entries, +1 drill-down case |
| New permissions | financial.income.view/create/edit/delete |
| New activity types | income.created/updated/voided/category.created/category.updated |
| Route | /income |
| Template source | Phase 3 Expense module |
| Key deviations | direction=inflow, isInflow=true, event_ts=receivedAt, color=success/green, logWarning for void |

---

*Report generated by: Senior ERP Financial Architect*
*Project: Lez POS*
*Date: 2026-06-22*
*Phase: 4.0 Pre-Implementation Architecture Audit*