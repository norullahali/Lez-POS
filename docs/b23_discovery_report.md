# B23 DISCOVERY REPORT

**Date:** 2026-10-12
**Mode:** DISCOVERY ONLY — no production/test/schema changes, no commit, no push

---

## 1. Baseline

| Item | Value |
|------|-------|
| Branch | `main` |
| HEAD | `552636336b07489f0b7f7a5d1cc52cb3e90bef3b` |
| origin/main | `552636336b07489f0b7f7a5d1cc52cb3e90bef3b` |
| Schema version | **49** (`app_database.dart` `schemaVersion => 49`) |
| Working tree | **Clean tracked files**; untracked `docs/*` and `tool/*` only |

---

## 2. Current Architecture

Lez POS financial and inventory mutations increasingly follow a **canonical service** pattern:

- **Idempotency table** (operation-specific) + **fingerprint** (SHA-256 canonical JSON) + **seal-last** inside a single `db.transaction()`.
- **In-transaction activity logs** via `activityLogsDao.insertLog` (B18/B19/B21/B22 family).
- **UI sticky UUID** per save intent, fingerprint change resets key, transient failure retains key (where implemented).
- **Repositories** either delegate to services (production) or retain **test-only** helpers after cutover (B22 expense pattern).

Inventory and AR/AP flows use dedicated services (returns, payments, purchases, adjustments) with phase-specific idempotency DAOs. Derived **financial ledger** reads active rows (e.g. `is_voided = 0`) rather than posting compensating reversal rows for voided income/expense records.

---

## 3. Protected Areas

Verified at HEAD (code inspection + alignment with closed B-phases):

| Area | Canonical protection | Notes |
|------|---------------------|-------|
| POS sale checkout | `PosSaleService.processSale` + `pos_sale_idempotency` | B5; sticky key in `PaymentDialog` |
| Customer payment | `CustomerAccountService.processPayment` + idempotency | B6; sticky key on payments screen |
| Purchase save | `PurchaseSaveService` | B7 |
| Supplier payment | `SupplierPaymentService` | B8 |
| Customer quick/manual/invoice returns | Phase C services + idempotency tables | B9/B10/B16 + caps B12–B13 |
| Supplier purchase return | Idempotent posting | B14/B15 |
| Expense **create** | `ExpenseCreationService` | B18 |
| Expense **update/void** | `ExpenseMutationSaveService` + `expense_mutation_idempotency` | B22 (closed) |
| Other income **create** | `OtherIncomeCreationService` + `other_income_idempotency` | B19 |
| Opening stock init | `OpeningStockSaveService` | B20 |
| Stock adjustment save | `StockAdjustmentSaveService` | B21 |
| Credit limits / invoice numbers / ledger refund rules | B2–B4, B11, B17 | Still present in codebase |

**Dead / non-production:** `PosRepository.saveSale` has **no** `lib/` callers; checkout uses `PosSaleService` via `cartProvider.checkout`.

---

## 4. Unprotected / Partially Protected Paths

| Production path | Status |
|-----------------|--------|
| **Other income UPDATE** | `OtherIncomeDialog` → `OtherIncomeRepository.updateIncome` — txn for row only; **audit after txn**; **no idempotency**; edit path **no sticky key** |
| **Other income VOID** | `OtherIncomeScreen` → `OtherIncomeRepository.voidIncome` — same split txn/audit; **no idempotency**; **no in-flight guard** |
| **POS settle debt** | `pos_screen._settleDebt` → `PosRepository.settleDebt` → `CustomerAccountService.processPayment` (B6 **service** OK) but UI generates **`v4()` on every confirm** — not sticky per intent |
| **Session close** | `PosSessionNotifier.closeSession` → `salesDao.closeSession` then **ActivityLoggerService outside txn**; no idempotency; `_saving` guard only in dialog (not audited replay) |
| Category/product/customer/supplier CRUD | Standard repository + post-txn activity | Out of idempotency scope (P3) |

---

## 5. Findings

### F-OI-1 — Other income update/void gap (mirror pre-B22 expense)

| Field | Detail |
|-------|--------|
| **ID** | F-OI-1 |
| **Priority** | **P1** (material financial consistency; direct B22 parallel) |
| **Production path** | Update: `lib/features/other_income/screens/widgets/other_income_dialog.dart` `_submit` → `OtherIncomeRepository.updateIncome`. Void: `lib/features/other_income/screens/other_income_screen.dart` `_confirmVoid` → `voidIncome` |
| **Current behavior** | Row mutation inside `db.transaction()`; `ActivityLoggerService` **after** commit; no mutation idempotency table; no fingerprints for UPDATE/VOID |
| **Exact risk** | Double-submit or retry can duplicate **audit** or apply **duplicate row writes** (different keys); partial failure leaves **row committed without audit** or vice versa; concurrent update/void races analogous to pre-B22 expense |
| **Concurrency** | Two terminals: last-write-wins update; void vs update ordering relies on DAO guards only; **no cross-path tests** |
| **Existing protection** | B19 CREATE only; repository TOCTOU guards on voided flag |
| **Missing protection** | Canonical mutation service, mutation idempotency, in-txn audit, UI sticky keys, auth parity with B22 |
| **Why it matters** | `financial_ledger_repository` derives **OTHER_INCOME** from `other_income_records` (one row → one ledger entry); void/update changes cash reporting |
| **Evidence** | `other_income_repository.dart` lines 80–143; dialog edit branch 116–125; screen void 582–603 |

### F-POS-1 — POS debt settlement non-sticky idempotency key

| Field | Detail |
|-------|--------|
| **ID** | F-POS-1 |
| **Priority** | **P1** |
| **Production path** | `lib/features/pos/screens/pos_screen.dart` `_settleDebt` → `settleDebt` → `processPayment` |
| **Current behavior** | `final idempotencyKey = _settleDebtUuid.v4();` **on each successful confirm** (line ~722); `_settleDebtInFlight` only |
| **Exact risk** | Transient failure after payment commits but before UI success → user retries → **new key** → **second payment** (service cannot replay) |
| **Concurrency** | Same customer dual payment still serialized by service txn; issue is **retry semantics**, not same-key race |
| **Existing protection** | B6 service idempotency **if** key reused |
| **Missing protection** | Sticky key + fingerprint reset pattern (as `customer_payments_screen.dart` and B22 void) |
| **Evidence** | `pos_screen.dart` 722–730 vs `customer_payments_screen.dart` 61–83 |

### F-SES-1 — Session close non-atomic audit

| Field | Detail |
|-------|--------|
| **ID** | F-SES-1 |
| **Priority** | **P2** |
| **Production path** | `pos_provider.dart` `closeSession` → `posRepository.closeSession` then `ActivityLoggerService.logInfo` |
| **Current behavior** | Session row closed in DAO; audit **outside** transaction; no idempotency |
| **Exact risk** | Close succeeds, audit fails → missing session close log; double-close overwrites close metadata |
| **Evidence** | `pos_provider.dart` 76–97; `sales_dao.dart` 28–46 |

### F-OI-2 — Other income edit auth / in-flight (secondary)

| Field | Detail |
|-------|--------|
| **ID** | F-OI-2 |
| **Priority** | **P2** |
| **Production path** | `OtherIncomeDialog._submit` edit branch |
| **Current behavior** | Create uses `createdBy`; edit update does not enforce `userId > 0` at UI; `_saving` on create path but edit uses same flag without mutation service |
| **Missing** | Parity with B22 auth + void in-flight on screen |

---

## 6. Idempotency Coverage Matrix

| Business operation | Active production path | Idempotency | Atomic guard (txn) | Transaction | Main risk |
|---|---|---|---|---|---|
| POS checkout | `PosSaleService.processSale` | Yes (B5) | Yes | Full txn | Low |
| POS settle debt | `CustomerAccountService.processPayment` | Service yes / **UI key no** | Yes | Service txn | **Retry duplicate payment** |
| Customer payment (screen) | `processPayment` | Yes (B6) | Yes | Service txn | Low |
| Purchase save | `PurchaseSaveService` | Yes (B7) | Yes | Service txn | Low |
| Supplier payment | `SupplierPaymentService` | Yes (B8) | Yes | Service txn | Low |
| Customer returns (quick/manual/invoice) | Phase C services | Yes | Yes | Service txn | Low |
| Supplier purchase return | Posting services | Yes | Yes | Service txn | Low |
| Expense create/update/void | Creation + mutation services | Yes | Yes | In-txn audit+seal | Low (B22) |
| Other income **create** | `OtherIncomeCreationService` | Yes (B19) | Yes | In-txn | Low |
| Other income **update/void** | `OtherIncomeRepository` | **No** | Partial (row only) | Audit split | **Duplicate / split effects** |
| Opening stock init | `OpeningStockSaveService` | Yes (B20) | Yes | Service txn | Low |
| Stock adjustment | `StockAdjustmentSaveService` | Yes (B21) | Yes | Service txn | Low |
| Session close | `salesDao.closeSession` | No | Partial | Audit split | Audit gap / double-close metadata |

---

## 7. Database Invariant Matrix

| Invariant | Enforcement |
|---|---|
| One idempotency seal per client operation key | **A** — per-table PK on `idempotency_key` (where table exists) |
| Voided income/expense excluded from active totals | **B** — queries filter `is_voided = 0` |
| Non-negative stock (guarded paths) | **B/C** — `StockGuard` in sale/adjustment services |
| Customer/supplier payment idempotent replay | **A+B** — idempotency + service txn |
| Other income update exactly-once per intent | **D** — not enforced |
| Session closed at most once with immutable close snapshot | **D** — `is_closed` flips but close fields can be overwritten |
| Invoice number uniqueness | **A** — B4 atomic allocation |

Legend: **A** database; **B** atomic in transaction; **C** application-only; **D** not enforced

---

## 8. Cross-Path Race Findings

| Race | Real in production? | Protection today | Gap |
|---|---|---|---|
| Other income **update vs void** | Yes (dialog + screen) | DAO void flag checks | No mutation idempotency; audit outside txn; **same class as pre-B22 expense** |
| Expense update vs void | Yes | B22 mutation service | Closed |
| POS sale vs customer payment | Related but separate intents | Separate services | Low |
| Stock adjustment vs sale/return | Yes | B21 cross tests + txn | Mitigated |
| Session close vs POS sale | Yes (same session) | Session must be open to sell | Close not idempotent |
| Settle debt vs checkout payment | Same customer AR | Both use payment service | UI key gap on settle path only |

---

## 9. Ranked Candidates

### 1. C23-A — Other income record UPDATE + VOID save protection

- **Priority:** P1 (strongest financial parity with closed B22)
- **Risk:** Duplicate mutation/audit; split txn/audit; update↔void races; ledger/summary drift
- **Why strongest:** Full production gap on an active financial module; B19 left CREATE protected only; proven B22 template (separate mutation idempotency table, `OtherIncomeMutationSaveService`, in-txn warning void audit, UI keys); clear deterministic test matrix including update↔void dual-connection cases

### 2. C23-B — POS settle-debt sticky idempotency UI

- **Priority:** P1
- **Risk:** Duplicate customer payments on retry
- **Why #2 not #1:** Backend already B6-safe **when key is reused**; smaller scoped UI fix; no schema; does not address other-income mutation architecture

### 3. C23-C — Session close idempotency + in-txn audit

- **Priority:** P2
- **Risk:** Missing/overwritten close audit; weak replay semantics
- **Why #3:** Operational/session reporting; less direct cash/ledger corruption than other-income mutations

---

## 10. Recommended B23 Candidate

**C23-A: Other income UPDATE and VOID save protection** (architectural parallel to B22 expense mutation protection, preserving B19 CREATE unchanged).

---

## 11. Discovery Verdict

**READY FOR DESIGN REVIEW**
