# B27 Discovery Report — Next Production Integrity / Idempotency Gap

**Date:** 2026-10-14  
**Mode:** READ-ONLY discovery (no source/test/schema edits)  
**Baseline HEAD:** `6d3d1b78f8f598adbc82b4b7536500e369d7cf96` (`6d3d1b7`)  
**Commit:** `feat(pos): harden POS session close`  
**Remote:** LOCAL HEAD == origin/main  
**Schema:** **51** (`AppDatabase.schemaVersion`)  
**Prior milestone:** B26 CLOSED (POS session close hardening)

---

## 1. Executive Summary

After B26, POS session lifecycle (open B25 + close B26) and most canonical financial/inventory writers (B2–B24 domain services) are hardened with idempotency tables, atomic SQL guards, or fingerprint replay patterns.

A fresh repo-wide audit finds the highest remaining production integrity risk in the **POS checkout UI idempotency lifecycle**: `PosSaleService.processSale` (B5) is authoritative and replay-safe per idempotency key, but checkout generates a **new key on every `PaymentDialog` instance**. After a successful DB commit followed by UI-level failure before cart clear (or user retry with a fresh payment dialog), a second submit can use a **different key** with the **same fingerprint** — B5 explicitly allows two sales (`pos_sale_idempotency_b5_test.dart` test 7). That produces duplicate invoices, stock deductions, session cash totals, loyalty effects, and receivable movements.

**Recommended B27:** Bind a sticky checkout operation idempotency key to the active cart checkout intent (mirror B24 `PosSettleDebtIdempotencyState` and `CustomerPaymentsScreen`), invalidate on intent change, clear only on confirmed success or explicit cart reset — **no schema change**.

---

## 2. Baseline

| Check | Expected | Actual |
|-------|----------|--------|
| `git rev-parse HEAD` | `6d3d1b7…` | `6d3d1b78f8f598adbc82b4b7536500e369d7cf96` |
| Commit message | `feat(pos): harden POS session close` | Match |
| Parent | `fb368f8…` | Match (B25 baseline) |
| Tracked working tree | Clean | Clean (only unrelated untracked `docs/*`, `tool/*`) |
| Schema | 51 | 51 |
| B26 artifacts | Present | `PosSessionCloseService`, B26 tests, wired repo/provider/dialog |

---

## 3. B-Series Protection Matrix (post-B26)

| Domain | UI entry | Canonical service | Idempotency / guard | Txn + seal | Concurrency tests | Notes |
|--------|----------|-------------------|----------------------|------------|---------------------|-------|
| POS sale checkout | `pos_screen` → `PaymentDialog` → `CartNotifier.checkout` | `PosSaleService.processSale` | `pos_sale_idempotency` (B5) | Yes | B5 | **UI key not sticky across dialog reopen** |
| POS quick return | `customer_returns_screen` | `PosSaleService.processQuickReturn` | B9 | Yes | B9 | Sticky key in screen |
| POS debt settle | `pos_screen._settleDebt` | `CustomerAccountService` via repo | B6 + B24 sticky UI | Yes | B6/B24 | Reference for B27 |
| POS session open | `SessionOpenDialog` | `PosSessionOpenService` | B25 + UNIQUE open index | Yes | B25 | |
| POS session close | `SessionCloseDialog` | `PosSessionCloseService` | B26 fingerprint replay | Yes | B26 | |
| Customer payment | `customer_payments_screen` | `CustomerAccountService` | B6 | Yes | B6 | Sticky key |
| Customer refund settle | refund dialogs | `CustomerRefundSettlementService` | refund idempotency table | Yes | Phase C | Sticky per dialog |
| Customer manual/quick/invoice returns | returns / invoice UI | Manual / Quick / Invoice return services | B9/B10/B16 | Yes | Yes | |
| Supplier payment/return/refund | supplier UI | B8/B15/settlement services | Tables | Yes | Yes | |
| Purchase save | purchase form | `PurchaseSaveService` | B7 | Yes | B7 | |
| Expense / other income CRUD+void | dialogs | B18/B19/B22/B23 | Tables | Yes | Yes | |
| Opening stock / stock adjustment | inventory UI | B20/B21 | Tables | Yes | Yes | |
| Invoice number / credit limit | in sale txn | B4/B2 | Atomic | In txn | B2/B4 | |

`PartialReturnService` writes in production only via `CustomerInvoiceReturnService` (B16) from invoice UI.

---

## 4. Production Mutation Inventory (summary)

Major financial/inventory mutations in `lib/features` route through B-series services. Residual paths:

| Path | Risk | Production UI? |
|------|------|----------------|
| `PurchasesDao.deleteInvoice` | Header delete; no reversal | Provider `delete` exists; no purchases screen caller found |
| `PurchasesDao.savePurchaseInvoice` | Non-idempotent legacy | Tests only |
| `ProductsNotifier` CRUD | Catalog; post-commit activity | Yes; low duplicate-$ impact |

No production bypass for B5 (`processSale` only from `CartNotifier.checkout`).

---

## 5. Retry / Duplicate-Submit Audit

| Path | Key generation | Sticky across retry? |
|------|----------------|----------------------|
| POS checkout | `PaymentDialog`: new UUID per dialog | **No** |
| POS settle debt | B24 `prepareKey` | **Yes** |
| Customer payment | sticky until success | **Yes** |

**Failure mode:** `processSale` commits → error/crash before `clearCart()` in `pos_screen.dart` → cart unchanged → new `PaymentDialog` → new key → second sale (B5 test 7).

---

## 6. Concurrency Audit

Same-key races: covered by B5. **Different keys, identical cart fingerprint:** no invariant — highest risk when combined with UI retry after success.

---

## 7. Financial Integrity Audit

Duplicate checkout double-counts sale totals, cash/card/debt, loyalty, and receivable (B2 path). Session reporting and derived ledger views inherit duplicate source rows.

---

## 8. Inventory Integrity Audit

Duplicate checkout ⇒ duplicate `StockGuard` deductions. Returns/adjustments/purchases covered by B7–B21. No stock transfer feature in `lib/`.

---

## 9. Terminal-State Audit

POS session close: B26 conditional close. Invoice returns: B16. Expense/other income void: B22/B23. Purchase hard delete: low reach.

---

## 10. Activity / Audit Atomicity

POS sale activity logged inside sale txn. Invoice return activity post-txn (informational only). Not B27.

---

## 11. Production Bypass Audit

No feature-layer bypass of `PosSaleService` for checkout. Gap is UI key lifecycle, not alternate writers.

---

## 12. Test Gap Audit

B5 strong at service layer; **no** checkout sticky-key / retry-after-success UI test. Aligns with P1 risk.

---

## 13. Current B-Series Coverage

B1–B26 confirmed on main @ 6d3d1b7. Schema 51.

---

## 14. Ranked Candidates

| ID | Name | Sev | Scope | Schema |
|----|------|-----|-------|--------|
| **R1** | POS checkout sticky operation idempotency | **P0** | Small–medium | None |
| R2 | B5 fingerprint-level dedup (service) | P1 | Medium | Maybe |
| R3 | Purchase `deleteInvoice` | P2 | Small | TBD |
| R4 | Return post-txn activity | P3 | Small | None |
| R5 | Product CRUD retry | P3 | Medium | None |
| R6 | Backup restore | P2 | Large | N/A |

---

## 15. Selected B27 Target

**B27 — POS checkout operation-intent sticky idempotency (UI + cart orchestration)**

One idempotency key per checkout intent until success or intent change; reuse B5 backend.

---

## 16. Runner-Ups

**R2 (B5 fingerprint dedup):** Defense in depth but changes tested service semantics → B28/B5.1.

**R3 (purchase delete):** Real integrity issue if exposed → purchases track; lower daily risk than checkout.

**R4 (return activity):** Audit only → backlog.

---

## 17. B27 Scope

**IN:** PaymentDialog / pos_screen / CartNotifier sticky key; bind to `PosSaleFingerprint` inputs; clear on success; invalidate on cart/payment intent change.

**OUT:** B26, B5 semantic change (unless design adds conflict UX only), schema, print handling, unrelated domains.

---

## 18. Expected Implementation Surface

New `checkout_idempotency` helper; modify payment dialog + pos screen (+/- cart notifier); tests `pos_checkout_idempotency_b27_test.dart`; no DAO/schema.

---

## 19. Test Strategy

Fresh success; duplicate submit; retry after commit+UI failure; intent change new key; conflict; in-flight; regression B5/B24/B25/B26.

---

## 20. Schema Decision

**A. No schema change** (reuse `pos_sale_idempotency`).

---

## 21. Risks / Open Questions

Cart slot ID retained on `clearCart()`; multi-cart policy; cancel vs retain key; conflict messaging; optional future R2.

---

## 22. Final Verdict

**B27 DISCOVERY: READY FOR DESIGN REVIEW**