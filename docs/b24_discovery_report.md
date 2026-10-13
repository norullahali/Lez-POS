# B24 DISCOVERY REPORT

**Date:** 2026-10-13
**Mode:** DISCOVERY ONLY — no production/test/schema changes, no commit, no push

---

## 1. Executive Summary

Post-**B23**, Lez POS has canonical save/idempotency protection across essentially all **material financial and stock mutation** paths (POS checkout, AR/AP payments, purchases, returns, expenses, other income, opening stock, stock adjustments). Schema baseline is **v50**.

The highest-value **remaining production gap** is not a missing backend idempotency table but a **channel-specific UI failure**: **POS in-cart customer debt settlement** calls the fully protected **B6** `CustomerAccountService.processPayment`, yet generates a **fresh UUID on every confirm**, so transient failures after commit can produce **duplicate customer payments and ledger cash inflows** on retry. The dedicated **Customer Payments** screen already implements the correct sticky-key pattern.

The second cluster is **POS session open/close**: no idempotency, no database invariant enforcing a single open session, **close metadata can be overwritten**, and session **activity logs run outside** the DAO transaction. This affects cash reconciliation and operational integrity more than direct double-ledger posting, but is material for multi-terminal and retry scenarios.

**Latent footguns** remain: legacy `PosRepository.saveSale` (zero `lib/` callers) and `PurchasesDao.deleteInvoice` (header-only delete, no production UI caller).

**Recommended next phase:** **B24 — POS in-cart debt settlement intent protection** (align POS channel with B6 retry semantics; primarily UI/state; optional design notes for fingerprint reset on amount change).

**Discovery verdict:** **READY FOR DESIGN REVIEW**

---

## 2. Current Baseline

| Item | Value |
|------|-------|
| Branch | `main` |
| HEAD | `856f9a8e95e33f47432c1563637de7487bce607d` |
| B23 subject | `feat(other-income): protect other income updates and voids` |
| Schema version | **50** (`lib/core/database/app_database.dart` `schemaVersion => 50`) |
| Working tree | **Clean tracked files**; untracked `docs/*` and `tool/*` only |

Architecture pattern (unchanged): operation-specific **idempotency table** + **fingerprint** + **seal-last** inside `db.transaction()`; financial ledger remains **derived** (read-only UNION), not a separate posting journal.

---

## 3. Protected Mutation Matrix

Verified by code inspection at HEAD `856f9a8`. Closed B-phases are treated as **closed** unless a new bypass is evidenced.

| Business area | Production path | Protection | B-phase |
|---------------|-----------------|------------|---------|
| POS sale / checkout | `CartNotifier.checkout` → `PosSaleService.processSale` | `pos_sale_idempotency`; sticky key in `PaymentDialog` | B5 |
| Customer payment (dedicated screen) | `CustomerPaymentsScreen` → `CustomerAccountService.processPayment` | `customer_payment_idempotency`; sticky key | B6 |
| Customer credit limit on sale debt | Inside `PosSaleService` / account paths | Cap enforcement | B2 |
| Invoice number allocation | Sale/purchase save services | Atomic sequence | B4 |
| Purchase save | `PurchaseFormScreen` → `PurchaseSaveService` | Purchase idempotency; sticky key | B7 |
| Supplier payment | `SupplierPaymentsScreen` → `SupplierPaymentService` | Supplier payment idempotency | B8 |
| Customer quick return | `CustomerReturnsScreen` → quick return service | Idempotency + sticky key | B9 |
| Customer manual return | Same screen, manual path | Idempotency + sticky key | B10 |
| Partial invoice return | `InvoiceDetailsDialog` → `CustomerInvoiceReturnService` | Idempotency; ledger suppression rules | B11, B16 |
| Partial return credit cap | Partial return execution | Credit cap | B12 |
| Full invoice return | Invoice dialog full return | Idempotency; credit race guards | B13, B16 |
| Supplier purchase return | Supplier return draft/submit | Credit cap + idempotency | B14, B15 |
| Mixed-payment return cash ledger | Return settlement paths | Ledger rules | B17 |
| Expense create / update / void | `ExpenseDialog` / `ExpenseScreen` → creation + `ExpenseMutationSaveService` | B18 create; B22 mutation idempotency | B18, B22 |
| Other income create / update / void | `OtherIncomeDialog` / `OtherIncomeScreen` → creation + `OtherIncomeMutationSaveService` | B19 create; B23 mutation idempotency | B19, B23 |
| Opening stock init | `OpeningStockScreen` → `OpeningStockSaveService` | Idempotency; sticky key | B20 |
| Stock adjustment | `InventoryScreen` → `StockAdjustmentSaveService` | Idempotency; sticky key | B21 |
| Customer refund settlement (credit) | `CustomerRefundSettlementUiNotifier.submit` | Service idempotency; key set at `init`, reused on retry | Phase C |
| Supplier refund settlement | `SupplierRefundSettlementUiNotifier` | Same pattern as customer refund UI | Phase C |

**Explicitly partial / unprotected in production:**

| Business area | Gap |
|---------------|-----|
| POS in-cart debt settlement | B6 backend OK; **UI key not sticky** |
| POS session open | Plain insert; no idempotency |
| POS session close | DAO update; audit outside txn; re-close overwrites |

---

## 4. Remaining Mutation / Financial Paths

| Path | Mutates | Idempotency | Atomic audit | Production UI |
|------|---------|-------------|--------------|---------------|
| `pos_screen._settleDebt` | Customer balance, payment txn, ledger inflow | Per-key only (B6); **new key each attempt** | In B6 txn | **Yes** |
| `PosSessionNotifier.openSession` | `pos_sessions` row | No | Post-commit `ActivityLoggerService` | **Yes** |
| `PosSessionNotifier.closeSession` | Session close fields | No | Post-commit activity | **Yes** |
| `PosRepository.saveSale` | Invoice, stock, optional debt | No (legacy) | Repo txn only | **No `lib/` callers** |
| `PurchasesNotifier.delete` → `deleteInvoice` | Deletes purchase header only | No | N/A | **No screen caller** |
| Master data CRUD | Metadata | No | Often post-txn activity | Yes (P3 scope) |
| `CustomerInvoiceReturnService` warning activity | Audit only | N/A | After idempotent txn | Yes |

---

## 5. Detailed Candidate Findings

### C24-01 — POS in-cart debt settlement: non-sticky idempotency key

| Field | Detail |
|-------|--------|
| **Candidate ID** | C24-01 |
| **Business area** | Customer accounts / payments; POS |
| **Exact production path** | `lib/features/pos/screens/pos_screen.dart` `_settleDebt` (664–758) → `PosRepository.settleDebt` (104–115) → `CustomerAccountService.processPayment` |
| **Relevant files** | `pos_screen.dart`; `pos_repository.dart`; `customer_account_service.dart`; contrast `customer_payments_screen.dart` (61–110) |
| **Current behavior** | On confirm: `final idempotencyKey = _settleDebtUuid.v4();` (line 722) then `settleDebt(...)`. `_settleDebtInFlight` blocks concurrent calls in one widget instance only. |
| **Why unsafe** | B6 replays only when the **same** key and matching parameters are reused. A new key is a **new financial operation**. |
| **Concrete failure scenario** | Cashier settles 50,000 IQD from POS; DB commits payment; UI fails before success feedback. Cashier retries → **second payment** with new key → duplicate ledger inflow. |
| **Failure class** | **Retry-related** |
| **Financial / stock impact** | Duplicate AR payment and ledger cash inflow; no stock |
| **Existing protections** | B6 idempotency + txn; in-flight guard |
| **Why insufficient** | In-flight does not survive retry after error; key never sticky |
| **Severity** | **P1** |
| **Estimated scope** | **Small** — sticky key state on `PosScreen`, reset on success, reset when amount/customer intent changes |
| **Schema migration** | **No** |
| **B-phase overlap** | Extends B6 to POS channel; not re-opening B6 backend |
| **Legacy reachable?** | Active POS path |
| **Recommended phase** | **B24 lead** |

### C24-02 — POS session open: duplicate open sessions

| Field | Detail |
|-------|--------|
| **Candidate ID** | C24-02 |
| **Business area** | Sessions / cash reconciliation |
| **Exact production path** | `SessionOpenDialog._open` → `PosSessionNotifier.openSession` (39–55) → `SalesDao.openSession` insert |
| **Relevant files** | `session_dialog.dart`; `pos_provider.dart`; `sales_dao.dart` (19–26); `pos_sessions_table.dart` (no unique open guard) |
| **Current behavior** | Each open inserts `is_closed = false`. `getOpenSession` picks latest by `opened_at DESC`. |
| **Why unsafe** | Multiple open rows possible (double-click, two terminals, retry). |
| **Concrete failure scenario** | Orphan open sessions; sales attach to latest session only; reconciliation diverges. |
| **Failure class** | **Concurrent** + **retry-related** |
| **Financial / stock impact** | Indirect — session cash reporting |
| **Existing protections** | UI `_isLoading` only |
| **Severity** | **P1** (operations) |
| **Estimated scope** | **Medium–large**; likely schema |
| **Schema migration** | **Likely yes** |
| **Recommended phase** | Runner-up (session lifecycle) |

### C24-03 — POS session close: re-close overwrite + split audit

| Field | Detail |
|-------|--------|
| **Candidate ID** | C24-03 |
| **Business area** | Sessions |
| **Exact production path** | `SessionCloseDialog._close` → `closeSession` (62–105) → `SalesDao.closeSession` (28–46) |
| **Current behavior** | Update by `session_id` only; no `is_closed = false` guard; activity after commit. |
| **Why unsafe** | Retry overwrites close fields; audit may be missing. |
| **Failure class** | **Retry-related** |
| **Severity** | **P2** |
| **Schema migration** | Optional |
| **Recommended phase** | Bundle with C24-02 |

### C24-04 — Legacy `PosRepository.saveSale`

| Field | Detail |
|-------|--------|
| **Candidate ID** | C24-04 |
| **Path** | `pos_repository.dart` `saveSale` (50–101) |
| **Why unsafe** | Bypasses B5/B4/B2 if reactivated |
| **Severity** | **P2** latent |
| **Reachable** | **No** `lib/` callers |
| **Schema** | No |

### C24-05 — Purchase `deleteInvoice` (header-only)

| Field | Detail |
|-------|--------|
| **Candidate ID** | C24-05 |
| **Path** | `purchases_provider.dart` delete → `PurchasesDao.deleteInvoice` (149–150) |
| **Why unsafe** | No stock/AP reversal |
| **Severity** | **P2** latent |
| **Reachable** | **No** UI caller |

### C24-06 — Post-commit activity logs

| Field | Detail |
|-------|--------|
| **Candidate ID** | C24-06 |
| **Paths** | Session open/close; `CustomerInvoiceReturnService` (95–105, 138–148) |
| **Severity** | **P3** audit consistency |

---

## 6. Cross-Path Concurrency Findings

| Interaction | Protection today | Gap |
|-------------|------------------|-----|
| POS settle debt retry | B6 with same key | **New key each attempt (C24-01)** |
| Two payment UIs same customer | Separate keys | By design (two operators) |
| Session open vs checkout | UI requires session | Duplicate opens (C24-02) |
| Session close vs sale | None on close | Timing window (C24-03) |
| Other income / expense update vs void | B22/B23 | Closed |

---

## 7. Legacy / Bypass Findings

| Artifact | Production reachable? | Notes |
|----------|----------------------|-------|
| `PosRepository.saveSale` | No | Definition only |
| `PurchasesNotifier.delete` | No | Header-only delete |
| Expense/other income repo test helpers | Tests only | B22/B23 production uses mutation services |

---

## 8. Ranked Candidate Table

| Rank | ID | Title | Severity | Schema? | Scope |
|------|-----|-------|----------|---------|-------|
| 1 | C24-01 | POS settle-debt sticky intent (B6 channel) | P1 | No | Small |
| 2 | C24-02 | Session open single-open invariant | P1 ops | Likely | Med–large |
| 3 | C24-03 | Session close conditional + audit | P2 | Optional | Medium |
| 4 | C24-04 | Legacy `saveSale` guard/remove | P2 | No | Small |
| 5 | C24-05 | Purchase delete footgun | P2 | TBD | Small |
| 6 | C24-06 | Post-commit activity | P3 | No | Medium |

---

## 9. Recommended Next Phase

**B24 — POS in-cart customer debt settlement intent protection**

Sticky `idempotencyKey` per settlement intent on `PosScreen`, matching `CustomerPaymentsScreen` semantics. **B6** remains canonical backend.

---

## 10. Why It Is Higher Priority Than the Runners-Up

1. **Direct duplicate payments** on a common POS workflow vs session metadata drift.
2. **Small, low-risk fix** — backend already correct when key is reused.
3. **Proven inconsistency** — payments screen retains key on error; POS does not.
4. Session lifecycle (C24-02/03) is broader and likely needs schema — better as follow-on **B25**.

This recommendation is **not** “add another idempotency table”; it closes the last **payment** UI gap on POS.

---

## 11. Proposed Discovery Verdict

**READY FOR DESIGN REVIEW**

Design should define key reset rules (success, amount change, customer change) and UX for idempotent replay after transient errors. Session open/close documented as follow-on candidate.

---

## Appendix — Evidence Snippets

**POS settle debt — fresh UUID each confirm** (`lib/features/pos/screens/pos_screen.dart` lines 722–730):

```dart
        final idempotencyKey = _settleDebtUuid.v4();
        setState(() => _settleDebtInFlight = true);
        try {
          await ref.read(posRepositoryProvider).settleDebt(
                idempotencyKey: idempotencyKey,
                customerId: customerId,
                amount: amt,
                note: 'تسوية دين من POS',
              );
```

**Customer payments — sticky key** (`lib/features/customers/screens/customer_payments_screen.dart` lines 61–83):

```dart
  void _resetPaymentAttempt() {
    _idempotencyKey = null;
  }
  ...
    _idempotencyKey ??= _customerPaymentUuid.v4();
      await ref.read(customerAccountServiceProvider).processPayment(
            idempotencyKey: _idempotencyKey!,
```

**Session close — activity after DAO** (`lib/features/pos/providers/pos_provider.dart` lines 76–97).

**Legacy sale** (`lib/features/pos/repositories/pos_repository.dart` lines 50–64) — no `lib/` callers.

**Purchase delete** (`lib/core/database/daos/purchases_dao.dart` lines 149–150) — header row only.
