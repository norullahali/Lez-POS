# Expense Management — Phase 3 Final Audit Report
**Lez POS · Flutter + Riverpod + Drift**
**Audit Date:** 2026-06-22
**Auditor Role:** Senior ERP Financial Architect and Code Auditor
**Scope:** Phase 3 (Foundation + UI/CRUD + Cash Ledger Integration)
**Decision Type:** Enterprise Sign-Off

---

## Executive Summary

The Expense Management module (Phase 3) is functionally complete and architecturally sound.
The database schema is correctly versioned, indexes are present, soft-delete is properly
implemented, and the Cash Ledger integration is accurate with no double-count risk.
The module has zero dead code, no FORENSIC traces, and clean static analysis.

Two correctness defects and five maintainability weaknesses were identified.
None are blocking for current usage. Defect D-1 (copyWith sessionId) becomes a
correctness risk specifically when Cash Reconciliation (Phase 7) is built.

**Overall Score: 90/100**
**Final Decision: CONDITIONAL GO**
Conditions are documented in Section 13.

---

## Section 1 — Database Audit

### Files Reviewed
- lib/core/database/tables/expense_categories_table.dart
- lib/core/database/tables/expense_records_table.dart
- lib/core/database/app_database.dart (migration v29)

### expense_categories

| Column | Type | Nullable | Default | Status |
|---|---|---|---|---|
| id | INTEGER PK AUTOINCREMENT | NO | — | PASS |
| name | TEXT (1-120 chars) | NO | — | PASS |
| description | TEXT | NO | '' | PASS |
| is_active | BOOLEAN | NO | true | PASS — soft-disable |
| created_at | DATETIME | NO | CURRENT_TIMESTAMP | PASS |
| updated_at | DATETIME | YES | NULL | PASS — mutation marker |

**Index:** expense_categories_active_idx ON (is_active) — PASS

**Weakness W-1 (LOW):** No UNIQUE constraint on 
ame. Two categories with identical
names can be inserted. Not a crash risk, but a data quality risk as the database grows.

### expense_records

| Column | Type | Nullable | Default | Status |
|---|---|---|---|---|
| id | INTEGER PK AUTOINCREMENT | NO | — | PASS |
| category_id | INTEGER FK → expense_categories.id | NO | — | PASS |
| amount | REAL | NO | — | PASS (note: project-wide float pattern) |
| expense_date | DATETIME | NO | — | PASS |
| paid_at | DATETIME | NO | — | PASS — ledger timestamp |
| notes | TEXT | NO | '' | PASS |
| session_id | INTEGER FK → pos_sessions.id | YES | NULL | PASS — optional |
| created_by | INTEGER FK → users.id | NO | — | PASS — audit trail |
| created_at | DATETIME | NO | CURRENT_TIMESTAMP | PASS |
| updated_at | DATETIME | YES | NULL | PASS — mutation marker |
| is_voided | BOOLEAN | NO | false | PASS — soft-delete |

**Indexes (4):**
- expense_records_category_idx ON (category_id) — PASS joins and filter
- expense_records_paid_at_idx ON (paid_at) — PASS ledger ORDER BY
- expense_records_session_idx ON (session_id) — PASS session reconciliation
- expense_records_voided_idx ON (is_voided) — PASS active-only queries

**Note on REAL type:** Consistent with all other monetary columns in the project
(sales_invoices.cash_paid, purchase_invoices.paid_amount, etc.).
Integer cents would be more precise but requires a project-wide migration decision.

### Migration v29

Each table creation is independently wrapped in try/catch that only debugPrint on failure.

**Weakness W-2 (LOW):** If expenseCategories creation fails, expenseRecords creation
is still attempted despite the FK dependency. Failure is invisible in release builds
because debugPrint is a no-op outside debug mode.

No hidden duplication risks. No schema inconsistencies with other tables.

**Database Readiness: 90/100**

---

## Section 2 — DAO Audit

### File Reviewed
- lib/core/database/daos/expenses_dao.dart

### Method Assessment

| Method | Transaction | Hard Delete | Notes |
|---|---|---|---|
| createCategory | No (insert only) | N/A | PASS |
| updateCategory | No (replace only) | N/A | PASS |
| listCategories | N/A | N/A | PASS |
| getCategoryById | N/A | N/A | PASS |
| createExpense | No (insert only) | N/A | PASS |
| updateExpense | No (replace only) | N/A | PASS — called only inside repo transaction |
| voidExpense | No (partial update) | N/A | PASS — called only inside repo transaction |
| getExpenseById | N/A | N/A | PASS |
| getExpensesPaged | N/A | N/A | PASS with minor note |
| getExpenseSummary | N/A | N/A | PASS with minor note |

No hard deletes anywhere in the module.

**Pagination note:** getExpensesPaged runs two independent queries (count query and data
query) that both independently apply the same WHERE conditions. The filter logic is
duplicated in two places. If a new condition is added to one branch and not the other,
count and data will diverge silently. Maintainability risk, not a current bug.

**getExpenseSummary note:** Uses raw customSelect SQL rather than Drift typed query
builder. Column name changes would fail at runtime, not compile time. The reactive
readsFrom: {expenseRecords} declaration is correctly present.

**DAO Readiness: 88/100**

---

## Section 3 — Repository Audit

### File Reviewed
- lib/features/expenses/repositories/expense_repository.dart

### Findings

Separation of concerns is clean. Repository holds business logic.
DAO holds data access. No DAO logic duplicated in repository.

**Transaction safety:**
- updateExpense: wraps fetch + guard + update in _db.transaction(). PASS
  Prevents TOCTOU race condition.
  Guards against updating a voided record (throws StateError).
  Hardcodes isVoided: const Value(false) to prevent accidental un-voiding via replace.
- voidExpense: wraps fetch + guard + void in _db.transaction(). PASS
  before is nullable (db.ExpenseRecord?) — no LateInitializationError risk.
  Early-return guard prevents double-void.

**Defect D-1 (MEDIUM): ExpenseRecord.copyWith cannot clear sessionId to null.**

ExpenseRecord.copyWith uses sessionId ?? this.sessionId with no sentinel.
When a user edits an expense and unchecks ''link to session'' (_linkSession = false),
the dialog passes sessionId: null to copyWith, which resolves to this.sessionId
(the original value). The session link is silently preserved.

Impact: Session-linked expenses cannot be unlinked via the edit dialog.
This is currently low-impact because sessionId only affects Cash Reconciliation (Phase 7).
The Cash Ledger uses paid_at, not session_id.
However this is a semantic correctness defect that must be resolved before Phase 7.

Fix: Add Object? sessionId = _sentinel sentinel parameter to copyWith,
mirroring the pattern already used in ExpensesFilter.copyWith.

No circular dependencies. ExpenseRepository imports only DAOs, models, and services.

**Repository Readiness: 87/100**

---

## Section 4 — Provider Audit

### File Reviewed
- lib/features/expenses/providers/expense_providers.dart

### Findings

**expensesFilterProvider (NotifierProvider):**
All filter mutations reset page to 0. copyWith uses _sentinel for nullable fields.
Correct. PASS.

**expenseCategoriesProvider (FutureProvider.autoDispose + keepAlive 45s):**
Returns all categories (activeOnly: false) — intended for the manager dialog.
Filter bar correctly filters to active categories client-side. PASS.

**expensesProvider (FutureProvider.autoDispose + keepAlive 45s):**
Watches expensesFilterProvider — rebuilds on any filter change. PASS.

**expenseSummaryProvider (FutureProvider.autoDispose):**
Uses ref.watch(expenseCategoriesProvider.future) for category count.
Uses ref.read(expenseRepositoryProvider) for expense aggregates.
Because ref.read is used (not ref.watch) for the repository call, it does NOT
automatically rebuild when expense records change. It relies entirely on manual
ref.invalidate(expenseSummaryProvider) calls after mutations.
This is the correct push-invalidation pattern for this architecture.
Risk: A future mutation path that bypasses the UI would leave the summary stale.
Currently no such path exists.

**Weakness W-3 (LOW): usersMapForExpensesProvider bypasses Riverpod DI.**

  final users = await db.AppDatabase.instance.usersDao.getAllUsers();

Accesses AppDatabase.instance singleton directly instead of going through Riverpod.
All other providers inject AppDatabase through the provider tree. Makes this provider
untestable in isolation. No functional impact.

**Weakness W-4 (LOW): Redundant provider alias.**
_usersMapProvider is private and immediately re-exported as usersMapForExpensesProvider.
The alias adds no value.

No provider loops. No unnecessary autoDispose removals.

**Provider Readiness: 82/100**

---

## Section 5 — UI Audit

### Files Reviewed
- lib/features/expenses/screens/expense_screen.dart
- lib/features/expenses/screens/widgets/expense_dialog.dart
- lib/features/expenses/screens/widgets/expense_category_dialog.dart

### Findings

**RTL layout:** App-level Directionality(textDirection: TextDirection.rtl) covers all
widgets. expense_screen.dart and expense_dialog.dart have no redundant explicit
textDirection assignments. PASS.

**Inconsistency:** expense_category_dialog.dart retains explicit textDirection: TextDirection.rtl
on the AlertDialog title, two TextFormFields, and a SwitchListTile title. These are
redundant (not harmful) but inconsistent with the other two dialog files.

**Responsiveness:** Wrap, Expanded, ConstrainedBox, SizedBox with fixed widths
appropriate for Windows desktop POS. PASS.

**Pagination:** _PaginationBar reads expensesFilterProvider for current page
and expensesProvider for totalPages. Prev/next buttons correctly disabled at
boundaries. Total item count displayed. PASS.

**Table rendering:** _DataTable uses DataTable with wrapping SingleChildScrollView
for horizontal overflow. This is inside a Column > Expanded > Container > Column >
Expanded chain. If the data table is taller than the available height, the
SingleChildScrollView relies on the parent Expanded to bound it. Low-risk layout
issue on screens with many rows — acceptable for desktop POS.

**Dialog validation:**
- ExpenseDialog: amount validated as positive double (twice: validator + _submit guard).
  Category validated by form validator and _submit guard. PASS.
- ExpenseCategoryDialog: name not-empty validation. PASS.
- Both dialogs disable submit button while _saving = true. PASS.
- Both dialogs handle exceptions and show SnackBar with error message. PASS.
- Both dialogs check mounted before navigation after async calls. PASS.

**Permission visibility:**
- Add expense button: gated by financialExpensesCreate. PASS.
- Edit icon per row: gated by financialExpensesEdit. PASS.
- Void icon per row: gated by financialExpensesDelete. PASS.
- Add category button inside manager: gated by financialExpensesCreate. PASS.
- Edit category button: gated by financialExpensesEdit. PASS.

**Weakness W-5 (LOW): Category manager button has no outer permission gate.**
The ''Manage Categories'' button in _HeaderRow is accessible to anyone with
financial.expenses.view. Inner add/edit buttons are permission-gated so no mutations
are possible without the correct permissions. However category names and descriptions
are readable by view-only users. Not a security concern given the access level required.

**UI Readiness: 85/100**

---

## Section 6 — Permissions Audit

### Files Reviewed
- lib/features/auth/permissions/permission_keys.dart
- lib/features/auth/permissions/route_permissions.dart
- lib/core/widgets/side_nav.dart

### Findings

**Keys defined:**
  financialExpensesView   = 'financial.expenses.view'
  financialExpensesCreate = 'financial.expenses.create'
  financialExpensesEdit   = 'financial.expenses.edit'
  financialExpensesDelete = 'financial.expenses.delete'

All four keys are included in PermissionKeys.all. PASS — owner sync included.
All four have Arabic descriptions in PermissionKeys.descriptions. PASS.
Naming follows financial.*.* namespace convention. PASS.

Route guard: /expenses mapped to financialExpensesView. PASS.
Side nav: /expenses item gated by financialExpensesView. PASS.

**Future key financial.expenses.export:** Not yet defined. Correct — no export feature
exists. Define and add to all[] when Phase 4/5 export is implemented.

**Permissions Readiness: 96/100**

---

## Section 7 — Activity Log Audit

### Files Reviewed
- lib/core/activity/activity_types.dart
- lib/core/activity/activity_categories.dart
- lib/core/services/activity_logger_service.dart
- lib/features/expenses/repositories/expense_repository.dart

### Findings

**Event types defined (5):**
  expense.created, expense.updated, expense.voided,
  expense.category.created, expense.category.updated
All mutations covered. PASS.

**Category:** ActivityCategories.financial = 'financial'.
Arabic label 'المالية', icon Icons.account_balance_wallet_outlined. PASS.

**Arabic titles (Unicode decoded):**
  createCategory  → 'إضافة فئة مصروف'     PASS
  updateCategory  → 'تعديل فئة مصروف'     PASS
  createExpense   → 'تسجيل مصروف'         PASS
  updateExpense   → 'تعديل مصروف'         PASS
  voidExpense     → 'إلغاء مصروف'         PASS

**Severity mapping:**

| Action | Method | Severity | Expected |
|---|---|---|---|
| createCategory | logEntityCreate | info | PASS |
| updateCategory | logEntityUpdate | info | PASS |
| createExpense | logEntityCreate | info | PASS |
| updateExpense | logEntityUpdate | info | PASS |
| voidExpense | logInfo | info | FAIL — should be logWarning |

**Weakness W-6 (LOW): voidExpense uses logInfo instead of logWarning.**
Voiding is a destructive, irreversible operation — it permanently removes the expense
from the Cash Ledger. logWarning would be consistent with how logEntityDelete works
(warning severity) and would make void events stand out in the activity viewer.

Entity types: 'expense_record' and 'expense_category' — consistent with project
naming conventions. PASS.

No duplicate logs. Each operation logs exactly once. PASS.
Activity logger _write has its own try/catch — logging failure never blocks the
calling operation. PASS.

**Activity Log Readiness: 91/100**

---

## Section 8 — Cash Ledger Audit

### Files Reviewed
- lib/features/financial/models/cash_ledger_event_type.dart
- lib/features/financial/repositories/financial_ledger_repository.dart
- lib/features/financial/screens/cash_ledger_screen.dart

### Findings

**Event type expense:**
  expense('EXPENSE', 'مصروف', false)
  code = 'EXPENSE', isInflow = false (outflow). PASS.
  fromCode('EXPENSE') iterates values and returns CashLedgerEventType.expense. PASS.

**UNION branch mapping:**

| Field | Value | Status |
|---|---|---|
| ledger_id | 'EXPENSE:' or er.id | PASS |
| event_ts | er.paid_at | PASS |
| event_type | 'EXPENSE' | PASS |
| amount | er.amount | PASS |
| direction | 'outflow' | PASS |
| reference_type | 'expense_record' | PASS |
| reference_id | er.id | PASS |
| user_id | er.created_by | PASS |
| customer_id | NULL | PASS |
| supplier_id | NULL | PASS |
| invoice_id | NULL | PASS |
| description | category name + ' — ' + notes, with fallback | PASS |

**Filters:**
  WHERE er.is_voided = 0   → voided expenses fully excluded. PASS.
  AND er.amount > 0        → zero/negative amounts excluded. PASS.

No reversal rows. No compensating entries. PASS.

**_readSet() includes:**
  _db.expenseRecords     PASS — reactive to expense mutations
  _db.expenseCategories  PASS — reactive to category name changes

**Export:** getEntriesForExport delegates to getEntries — EXPENSE rows exported. PASS.
**Pagination and running balance:** Window function SUM() OVER covers all UNION sources. PASS.
**Filter support:** Dropdown uses CashLedgerEventType.values.map — EXPENSE automatic. PASS.
**Void behaviour:** is_voided = 1 excludes row. Edit updates on next query. PASS.
**Drill-down switch:** case CashLedgerEventType.expense: break; present. Exhaustive. PASS.

**Cash Ledger Readiness: 97/100**

---

## Section 9 — Double Count Audit

expense_records records operational costs: overhead, utilities, wages, supplies.

| Source | Nature | Shared FK with expense_records | Overlap risk |
|---|---|---|---|
| sales_invoices | Revenue from sales | None | None |
| customer_transactions | Customer payments | None | None |
| purchase_invoices | Goods procurement (COGS) | None | None |
| supplier_transactions | Payments against supplier debt | None | None |
| return_audit_logs | Cash-back to customers | None | None |

A purchase_invoice represents acquiring inventory (COGS).
An expense_record represents operational cost (OPEX) not tied to inventory.
These are structurally independent financial objects.

Cardinality: One expense_record row → exactly one EXPENSE ledger entry.
No anti-duplication guard needed or present.

**Double-count safety: 100/100 — CONFIRMED**

---

## Section 10 — Dead Code Audit

Search results across lib/features/expenses/** and lib/features/financial/**:

  Pattern: FORENSIC, debugPrint, TODO, FIXME, HACK, TEMP
  Result: No matches found.

Zero dead code. Zero forensic traces. Zero debug prints in expense and financial modules.

debugPrint in app_database.dart migration blocks are operational migration diagnostics
present across all migration steps — not expense-specific dead code.

Minor technical debt (non-blocking):
  - Redundant _usersMapProvider alias (W-4)
  - Redundant textDirection: TextDirection.rtl in expense_category_dialog.dart

**Maintainability: 87/100**

---

## Section 11 — Future Readiness

**Phase 4 — Other Income: HIGH READINESS**
Pattern is fully established. Steps:
  1. Add other_income table (amount, paid_at, is_voided, created_by).
  2. Add CashLedgerEventType.income('INCOME', 'إيراد آخر', true).
  3. Add UNION branch in _unionSql.
  4. Add table to _readSet().
  5. Add drill-down no-op case.
No architectural changes needed. Estimated effort: 2 hours.

**Phase 5 — Financial Dashboard: HIGH READINESS**
ExpenseSummary already exposes totalAmount, activeCount, voidedCount, categoryCount.
CashLedgerSummary already exposes totalInflow, totalOutflow, netCashFlow.
Category-level breakdown requires a new GROUP BY category_id query — schema ready.

**Phase 6 — Profit and Loss: HIGH READINESS**
expense_records.paid_at provides period filtering.
expense_records.category_id enables OPEX category grouping.
Existing getExpensesPaged with dateFrom/dateTo can serve P&L range queries.
A dedicated aggregate query would be cleaner but schema needs no changes.

**Phase 7 — Cash Reconciliation: MEDIUM READINESS**
session_id FK exists and is indexed.
BLOCKER: Defect D-1 (copyWith sessionId sentinel) must be fixed before Phase 7.
Session-linked expenses that have been ''unlinked'' via the UI will carry their
original session_id, causing incorrect session-level totals in reconciliation.

---

## Section 12 — Readiness Scores

| Layer | Score | Status |
|---|---|---|
| Database schema | 90/100 | GO |
| DAO | 88/100 | GO |
| Repository | 87/100 | CONDITIONAL (D-1) |
| Providers | 82/100 | GO |
| UI | 85/100 | GO |
| Permissions | 96/100 | GO |
| Activity logs | 91/100 | GO |
| Cash Ledger | 97/100 | GO |
| Double-count safety | 100/100 | GO |
| Maintainability | 87/100 | GO |
| **Overall** | **90/100** | **CONDITIONAL GO** |

---

## Strengths

1. Clean schema with correct types, nullable semantics, audit timestamps, 4 targeted indexes.
2. Soft-delete via is_voided — no hard deletes anywhere.
3. TOCTOU-safe mutations via _db.transaction() in updateExpense and voidExpense.
4. isVoided bypass prevention — hardcoded isVoided: const Value(false) in updateExpense.
5. Clean Cash Ledger integration — UNION branch correct and minimal.
6. Zero double-count risk — expense_records structurally independent of all other sources.
7. Correct permissions model — four granular keys, route-guarded, in all[], Arabic descriptions.
8. Complete activity log coverage — five event types, Arabic titles, correct entity types.
9. Zero dead code — no debugPrint, no FORENSIC traces in expense/financial modules.
10. Future-ready for Phases 4, 5, and 6 with no architectural changes required.

---

## Weaknesses

| ID | Severity | Location | Description |
|---|---|---|---|
| D-1 | MEDIUM | ExpenseRecord.copyWith | Cannot clear sessionId to null. No sentinel pattern. Silently preserves session link when user unchecks 'link to session' in edit dialog. Correctness defect for Phase 7. |
| W-1 | LOW | ExpenseCategories table | No UNIQUE constraint on name. Duplicate names can be inserted. |
| W-2 | LOW | Migration v29 | Independent try/catch per table. FK-dependent table attempted even if parent failed. Failure invisible in release builds. |
| W-3 | LOW | usersMapForExpensesProvider | Bypasses Riverpod DI via AppDatabase.instance singleton. Untestable in isolation. |
| W-4 | LOW | expense_providers.dart | Redundant _usersMapProvider / usersMapForExpensesProvider alias. |
| W-5 | LOW | _HeaderRow | 'Manage Categories' button visible to all view-permission users. Inner actions are gated but category list is exposed. |
| W-6 | LOW | voidExpense activity log | Uses logInfo severity. Should be logWarning for a destructive irreversible operation. |

---

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| D-1 corrupts Phase 7 session reconciliation | HIGH if built on current code | MEDIUM | Fix before Phase 7 sprint starts |
| Duplicate category names degrade UX | MEDIUM over time | LOW | Add unique constraint in future migration |
| expenseSummaryProvider stale via non-UI path | LOW (no such path today) | LOW | Document invalidation requirement for future bulk operations |
| Migration failure invisible in production | LOW | HIGH | Add error propagation or use onCreate for fresh installs |

---

## Recommendations

### Before next sprint (non-blocking, recommended)
1. Fix ExpenseRecord.copyWith sessionId sentinel (D-1).
   Add: Object? sessionId = _sentinel in copyWith.
   5-line change in expense_record.dart.

2. Change voidExpense to logWarning (W-6).
   1-line change in expense_repository.dart.

### Before Phase 7 (required)
3. D-1 MUST be fixed before Cash Reconciliation is implemented.

### Before production scale (non-urgent)
4. Add UNIQUE constraint on expense_categories.name (W-1).
5. Refactor usersMapForExpensesProvider to inject AppDatabase through Riverpod (W-3).
6. Remove redundant _usersMapProvider alias (W-4).

### Before Phase 4+ export features
7. Define financial.expenses.export permission key.
   Add to PermissionKeys.all and descriptions when export is implemented.

---

## Final Decision

  CONDITIONAL GO

  Phase 3 Expense Management is production-ready for deployment.

  CONDITION 1 — Required before Phase 7 (Cash Reconciliation):
    Fix ExpenseRecord.copyWith to support clearing sessionId to null (Defect D-1).

  CONDITION 2 — Recommended before production data scale:
    Add UNIQUE constraint on expense_categories.name to prevent duplicate data.

  All other weaknesses are LOW severity and do not affect the correctness of
  the current expense management and Cash Ledger integration.

  Phases 4 (Other Income), 5 (Financial Dashboard), and 6 (Profit and Loss)
  may proceed on the current architecture without prerequisite changes.

  Phase 7 (Cash Reconciliation) requires Condition 1 to be resolved first.

---

Report generated by: Senior ERP Financial Architect and Code Auditor
Project: Lez POS
Date: 2026-06-22
Phase: 3 Enterprise Sign-Off