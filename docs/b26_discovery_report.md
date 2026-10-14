# B26 Discovery Report

## 1. Date

2026-10-14

## 2. Baseline

| Item | Value |
|------|-------|
| Branch | `main` |
| HEAD | `fb368f80eef14e9adbdfefe4907efdbffe21317e` (`fb368f8`) |
| Commit | `feat(pos): protect POS session open` |
| origin/main | Matches HEAD |
| Prior milestone | B25 CLOSED (session **open** protection, schema v51) |
| Schema version | **51** (`app_database.dart`: `int get schemaVersion => 51`) |
| Working tree | No modified tracked files; known unrelated untracked `docs/*` and `tool/*` |

## 3. Repository state

Discovery performed against committed HEAD `fb368f8` only. No source/test/schema edits during discovery.

Post-B25, the highest asymmetry in POS session lifecycle is: **open is fully hardened (B25); close remains a thin DAO update with post-commit, non-authoritative activity logging.**

## 4. Current B1–B25 protection matrix

| Workflow | Production entry | Canonical service / writer | Idempotency | Atomicity (biz + audit) | Concurrency | DB invariant | Replay-safe |
|----------|------------------|----------------------------|-------------|-------------------------|-------------|--------------|-------------|
| POS sale (checkout) | `pos_screen` → `PosSessionNotifier.checkout` | `PosSaleService.processSale` | `pos_sale_idempotency` (B5) | Txn + seal last | Tested dual-connection | Invoice UNIQUE (B4) | Yes |
| Customer payment (UI) | `customer_payments_screen` | `CustomerAccountService.processPayment` | `customer_payment_idempotency` (B6) | Txn + seal | Tested | Payable cap in SQL path | Yes |
| POS in-cart debt settle | `pos_screen._settleDebt` | `CustomerAccountService` via `PosRepository.settleDebt` | B6 + sticky UUID (B24) | Same as B6 | B24 tests | Same as B6 | Yes |
| Supplier payment | `supplier_payments_screen` | `SupplierAccountService.processPayment` | `supplier_payment_idempotency` (B8) | Txn + seal | B8 tests | Payable cap SQL | Yes |
| Purchase save | purchases UI → repository | `PurchaseSaveService` | `purchase_idempotency` (B7) | Txn + seal | B7 tests | — | Yes |
| Customer manual return | returns UI | `ManualReturnService` | B10 table | Txn + seal | B10 tests | — | Yes |
| Customer invoice return (full/partial) | `invoice_details_dialog` | `CustomerInvoiceReturnService` | B16 table | Txn + seal | B16 tests | — | Yes |
| Customer refund settlement | refund UI | `CustomerRefundSettlementService` | B11 table | Txn + seal | Tests | — | Yes |
| Supplier return | supplier return UI | `SupplierReturnService` | B14 table | Txn + seal | Tests | — | Yes |
| Supplier refund settlement | UI | `SupplierRefundSettlementService` | table | Txn + seal | Tests | — | Yes |
| Expense create | `expense_dialog` | `ExpenseCreationService` | B18 table | Txn + seal | B18 tests | — | Yes |
| Expense update/void | expense UI | `ExpenseMutationSaveService` | B22 table | Txn + seal | B22 tests | — | Yes |
| Other income create | dialog | `OtherIncomeCreationService` | B19 table | Txn + seal | B19 tests | — | Yes |
| Other income update/void | dialog | `OtherIncomeMutationSaveService` | B23 table | Txn + seal | B23 tests | — | Yes |
| Opening stock init | inventory UI | `OpeningStockSaveService` | B20 table + product seals | Txn + seal | B20 tests | Eligibility guards | Yes |
| Stock adjustment | inventory UI | `StockAdjustmentSaveService` | B21 table | Txn + seal | B21 tests | — | Yes |
| POS session **open** | `SessionOpenDialog` | `PosSessionOpenService` | `pos_session_open_idempotency` (B25) | Txn activity DAO + seal | B25 dual-connection | `uq_pos_sessions_one_open` | Yes |
| POS session **close** | `SessionCloseDialog` | `SalesDao.closeSession` (via repo/provider) | **None** | **Close txn only; activity post-commit** | **Not tested** | **None on close** | **No** |
| Invoice number | sale path | `InvoiceNumberService` | — | Atomic counter (B4) | B4 tests | UNIQUE invoice_number | N/A |
| Backup / restore | settings/backup UI | `BackupService` | None | File replace | — | Permission-gated | N/A |

**Note:** `PartialReturnService` is used internally by `CustomerInvoiceReturnService` and for read/helpers in invoice UI; production **writes** for invoice-linked returns go through B16 service. `ReturnsDao.returnFullSaleInvoice` is **test-only** (no `lib/features` callers).

## 5. Production mutation inventory (summary)

Systematic `lib/` review of persistent writes shows major financial/inventory mutations routed through B-series services above. Remaining **production** session mutation:

- `SalesDao.closeSession` — unconditional `UPDATE pos_sessions SET is_closed=1 ... WHERE id = ?` (no `is_closed = 0` guard).

No production `into(posSessions).insert` bypass (B25): only `SalesDao.insertOpenSessionRow` via `PosSessionOpenService`.

No production `CustomerAccountsDao.recordPayment` bypass: payments use `recordPaymentInTransaction` inside `CustomerAccountService`.

## 6. Session close re-audit (B25 deferred item)

### Production path

```
PosScreen (close action, pos_screen.dart ~156–161)
  → SessionCloseDialog._close (session_dialog.dart ~498–505)
    → PosSessionNotifier.closeSession (pos_provider.dart ~59–102)
      → getSessionSummary + compute expected cash (read phase, outside close txn)
      → PosRepository.closeSession → SalesDao.closeSession (UPDATE)
      → ref.invalidateSelf()
      → ActivityLoggerService.logInfo(sessionClosed)  // AFTER DB write; swallows errors
```

### Findings

| # | Question | Answer | Risk |
|---|----------|--------|------|
| 1 | Two close requests race? | Both can run; second **overwrites** close metadata on same row | **P1** |
| 2 | Retry overwrite close metadata? | **Yes** — UPDATE has no `is_closed = 0` predicate | **P1** |
| 3 | Conditional on open session? | **No** at DAO layer | **P1** |
| 4 | Closed session modified by retry? | **Yes** — `closing_cash`, `closed_at`, `notes`, variance fields rewritten | **P1** |
| 5 | Activity atomic with close? | **No** — `ActivityLoggerService._write` catches errors and only `debugPrint`s | **P2** audit |
| 6 | Repeat close same request? | No idempotency key; UI `_isLoading` only (same as pre-B25 open) | **P1** retry-after-success |
| 7 | Duplicate ledger on close? | Close does not post cash ledger rows; no double money movement | N/A |
| 8 | Severity | **P1** — material shift-close integrity and audit reliability | |
| 9 | Idempotency table required? | **Not proven required** — business outcome may be “close once”; conditional update + txn audit + sticky replay may suffice (design phase) | |
| 10 | Smaller solution? | **Likely yes:** `PosSessionCloseService` with `UPDATE ... WHERE id=? AND is_closed=0`, in-txn `activityLogsDao.insertLog`, optional sticky UUID (mirror B25/B24 pattern) | |

### UI

- `SessionCloseDialog`: no idempotency UUID; `_isLoading` disables button only.
- Retry after provider failure following successful UPDATE can re-close with different cash/notes.

## 7. Financial integrity audit (remaining gaps)

Protected domains (payments, settlements, expenses, income, returns) use idempotent services with seal-last transactions and SQL caps where applicable (B6/B8 payable checks).

**Session close** affects **authoritative shift record** (closing cash, variance, notes) but not customer/supplier balances directly.

**Backup restore** (`BackupService.restoreBackup`, permission-gated): full DB replace — high impact but operator-intentional, not duplicate-submit class.

**`adjustCustomerBalance`**: defined in `CustomerAccountService` but **no production feature callers** found in `lib/features` (dead/admin path risk low).

## 8. Inventory integrity audit

Sales, purchases, returns, opening stock, and adjustments route through protected services. No new production bypass found at HEAD beyond session close (non-inventory).

## 9. Concurrency / retry audit (session close focus)

| Scenario | Session close behavior |
|----------|------------------------|
| Double-click | Two UPDATEs; metadata from last wins |
| Commit then UI error | User retries; **overwrites** prior close |
| Same request retry | No replay semantics |
| Dual connection | Not guarded |
| SQLITE_BUSY | No bounded retry at close layer |
| Audit + close atomic | **Fail** — logger swallows errors |

## 10. Authorization / operator context

Close uses `closedByUserId` from auth provider (nullable). No additional role gate beyond reaching POS close UI while session open. Consistent with pre-B25 open semantics. **No new integrity gap** relative to open.

## 11. Production bypass audit

| Domain | Canonical | Bypass search result |
|--------|-----------|----------------------|
| Session open | `PosSessionOpenService` | **None** in `lib/` |
| Session close | *(none)* | Direct `SalesDao.closeSession` — **only path** (not a bypass; **unprotected canonical gap**) |
| Customer payment | `CustomerAccountService` | No direct `recordPayment` from features |
| POS sale | `PosSaleService` | No alternate checkout writer |
| Expense create | `ExpenseCreationService` | Dialog uses service |

## 12. Ranked candidate table

| ID | Candidate | Severity | Production path | Current protection | Failure mode | Consequence | Concurrency | Recommended scope |
|----|-----------|----------|-----------------|-------------------|--------------|-------------|-------------|-------------------|
| **C01** | **POS session close** | **P1** | Close dialog → notifier → `SalesDao.closeSession` | `_isLoading` only | Retry/double close overwrites close metadata; non-atomic audit | Wrong shift close record; missing/duplicate activity logs | Unprotected | **B26 primary** |
| C02 | Backup restore | P0/P1 | Settings backup UI | Permission only | Full DB replace misuse | Catastrophic if misused | N/A | Separate security/ops hardening |
| C03 | ActivityLogger post-commit pattern (other flows) | P2 | Various legacy logs | Swallows errors | Audit gap after success | Incomplete audit trail | — | Out of B26 |
| C04 | ReturnsDao legacy full return | P2 | **Tests only** | B16 supersedes UI | Duplicate return if called | Integrity | — | Not production |

## 13. Selected B26 target

**C01 — POS session close hardening (authoritative close + transactional audit + retry/idempotency semantics)**

## 14. Runner-up candidates

1. **Backup restore** — highest blast radius but permission-gated and operator-intentional; not duplicate-submit/idempotency class.
2. **Legacy ReturnsDao.returnFullSaleInvoice** — no production UI caller; covered by B16 in invoice UI.

## 15. Why B26 target wins

1. **Real daily production path** paired with B25-open (operators must close shifts).
2. **Reproducible** from source: unconditional UPDATE + post-commit logger.
3. **Material consequence**: closing cash and variance are reconciliation-critical; retry can silently change them.
4. **Not protected** by B1–B25 (explicitly deferred at B25).
5. **Clear boundary**: mirror B25 patterns without reopening open logic.
6. **Testable**: duplicate submit, retry-after-success, already-closed, activity rollback, optional dual-connection.
7. **Highest integrity value** among remaining *routine* POS mutations at HEAD.

Session close ranks above backup restore for B26 because restore is a deliberate admin action with permissions, whereas close is a high-frequency mutation with the same vulnerability class B25 fixed for open.

## 16. Test gaps (selected target)

| Area | Status |
|------|--------|
| Existing session close tests | **None** dedicated at HEAD |
| Duplicate submit | **Missing** |
| Retry-after-success | **Missing** |
| Already-closed second close | **Missing** |
| Activity failure rollback | **Missing** |
| Concurrency / dual-connection | **Missing** |
| Production path integration | **Missing** |
| Migration | **TBD in design** (may be none if conditional UPDATE only) |

## 17. Expected change surface (estimate)

| Layer | Likely touch (confirm in design) |
|-------|----------------------------------|
| Production | New `PosSessionCloseService` (or equivalent), `pos_repository` / `pos_provider`, `session_dialog.dart` sticky UUID |
| Database | Possibly **none** or additive idempotency table — design choice |
| Tests | New `test/pos_session_close_b26_test.dart` (+ helpers) |
| Documentation | `docs/b26_*` per B-series convention |

## 18. Schema impact

**Likely: additive optional or none.**

- **Minimum:** no new table — conditional `UPDATE ... WHERE is_closed = 0`, transactional activity insert, typed “already closed” / replay via sticky key fingerprint (closing cash, notes, session id).
- **Hybrid (if design matches B25):** `pos_session_close_idempotency` + migration v52 — only if design proves idempotency table needed beyond conditional close.

Prefer smallest durable invariant that prevents metadata overwrite and splits “success replay” from “genuine second close attempt.”

## 19. Explicit out-of-scope for B26

- POS session **open** (B25 closed)
- B5/B6/B24 checkout and payment logic
- Backup/restore redesign
- Unrelated UI polish, performance, refactors
- Customer returns / supplier returns / expenses / income (already B-series protected)
- `ReturnsDao.returnFullSaleInvoice` test helpers
- Unrelated untracked docs/tools in working tree
- Generic permission audit

## 20. Discovery verdict

**B26 DISCOVERY: READY FOR DESIGN REVIEW**

One clear production candidate (session close), evidence-backed P1 integrity gap, bounded scope, testable, baseline consistent.
