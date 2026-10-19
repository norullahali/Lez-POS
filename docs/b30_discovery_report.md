# B30 Discovery Report — Fresh Integrity & Idempotency Risk Assessment

**Date:** 2026-10-19  
**Mode:** READ-ONLY discovery (no production/test/schema/git mutations)  
**Project:** Lez POS  
**Prior milestone:** B29 CLOSED (`feat(supplier): protect refund settlement idempotency`)

---

## 1. Baseline verification

| Check | Expected | Actual |
|-------|----------|--------|
| Branch | `main` | `main` |
| `git rev-parse HEAD` | `da030ab538015ee44661f17c2869ecb902dd3ac8` | `da030ab538015ee44661f17c2869ecb902dd3ac8` |
| `git rev-parse origin/main` | same | same |
| HEAD == origin/main | yes | **yes** |
| Schema | 51 | **51** (`lib/core/database/app_database.dart`: `int get schemaVersion => 51`) |
| Staged changes | none | **none** |
| Modified tracked files | none | **none** |
| Latest commit message | B29 feat | `feat(supplier): protect refund settlement idempotency` |

**Untracked files (preserved, not touched):** unrelated `docs/*` (including `docs/b29_discovery_report.md`), `tool/*` — same pattern as prior milestones.

Discovery was performed against committed source at `da030ab`; no git clean/reset/stage/commit/push.

---

## 2. Closed-milestone exclusions

The following areas were re-verified in **current** source and tests. They are **excluded** as primary B30 candidates unless noted as residual P2/P3.

| Milestone | Domain | Current evidence (post-B29) | B30 status |
|-----------|--------|----------------------------|------------|
| B2 | Customer credit limit on sale debt | `CustomerAccountsDao.recordSaleInTransactionIfWithinCreditLimit` inside `PosSaleService` txn | Closed |
| B4 | Invoice number allocation | `InvoiceNumberService.allocateNextInTransaction` in sale txn | Closed |
| B5 | POS sale idempotency (per key) | `PosSaleService.processSale` + `pos_sale_idempotency` | Closed (service); UI see B27 |
| B6 | Customer payment idempotency | `CustomerAccountService.processPayment` | Closed |
| B7 | Purchase save idempotency | `PurchaseSaveService` + sticky key in `purchase_form_screen.dart` | Closed |
| B8 | Supplier payment idempotency | `SupplierAccountService` + sticky key in `supplier_payments_screen.dart` | Closed |
| B9–B10 | Quick / manual return **service** idempotency | `PosSaleService.processQuickReturn`, `ManualReturnService` | Closed at **service**; **UI intent gap remains** (see #1 candidate) |
| B11 / Phase C | Customer refund settlement **service** | `CustomerRefundSettlementService.settleCredit` | Closed |
| B15–B16 | Supplier / invoice-linked return **services** | `SupplierReturnService`, `CustomerInvoiceReturnService` | Closed at service; UI dual-key mitigated partly by returnable caps (P2) |
| B18–B23 | Expense / other income create & mutation | B-series services + sticky dialog keys | Closed |
| B20–B21 | Opening stock / stock adjustment | Save services + sticky UI keys | Closed |
| B24 | POS debt settlement UI intent | `PosSettleDebtIdempotencyState.prepareKey` in `pos_screen.dart` | Closed |
| B25–B26 | POS session open / close | `PosSessionOpenService`, `PosSessionCloseService` | Closed |
| B27 | POS checkout UI operation intent | `PosCheckoutIdempotencyState` on `CartNotifier` + `pos_screen.dart` checkout wiring | Closed (in-memory; process-death P2) |
| B28 | Customer refund settlement UI intent | `CustomerRefundSettlementIdempotencyState.prepareSettlementKey` | Closed |
| B29 | Supplier refund settlement UI intent | `SupplierRefundSettlementIdempotencyState` on `SupplierRefundSettlementUiNotifier` (`supplier_refund_settlement_provider.dart` L148–256) | **Closed** — not reopened |

**B29 regression check:** Supplier refund UI now computes `SupplierRefundSettlementIntentFingerprint` and calls `prepareSettlementKey` at submit time; `reset()` clears UI state only, not the sticky map (same pattern as B28). No separate material B29 gap found.

**Historical test hygiene (non-blocking):** Some older suites pin schema 34–35 while app is 51 (e.g. Phase C tests M/N, SR 3.0 test J). Not treated as open production defects.

---

## 3. Production-path inventory

Summary of **production write paths** (`lib/features` → services → DAOs). Idempotency = whether a **stable operation key** survives retry/reopen for the same business intent.

| Path | UI entry | Orchestration | Service | Txn boundary | Balance/stock authority | Concurrency | Idempotency | Retry / post-commit | Tests | Residual gap |
|------|----------|---------------|---------|--------------|-------------------------|-------------|-------------|---------------------|-------|--------------|
| POS checkout | `pos_screen.dart` `_checkout` | `CartNotifier.checkout` | `PosSaleService.processSale` | Single Drift txn + seal | StockGuard, B2 credit SQL | B5 dual-conn | B5 + **B27 sticky key** | Sale commits before print/clearCart; sticky key on failure | `pos_sale_idempotency_b5_test.dart`, `pos_checkout_idempotency_b27_test.dart` | Process-death loses in-memory key (P2) |
| POS quick return | `customer_returns_screen.dart` | Screen state | `PosSaleService.processQuickReturn` | Txn + seal | Stock + session cash path | B9 | B9 per key; **UI clears key on success** | Failure retains key | `customer_quick_return_idempotency_b9_test.dart` test 15 | **UI intent gap (P1)** |
| Customer manual return | `customer_returns_screen.dart` | Screen state | `ManualReturnService.processManualReturn` | Txn + seal | `returnsDao.saveCustomerReturnInTransaction` + stock | B10 same-key | B10 per key; **UI clears key on success** | Failure retains key | `customer_manual_return_idempotency_b10_test.dart` test 14 | **UI intent gap (P1)** |
| Customer invoice return | `invoice_details_dialog.dart` | Dialog state | `CustomerInvoiceReturnService` | Txn + seal | PartialReturnService / caps | B16 | Sticky key while dialog open; cleared on success | Fingerprint invalidates key on change | `customer_invoice_return_idempotency_b16_test.dart` | Reopen = new key; caps limit duplicate (P2) |
| Customer payment | `customer_payments_screen.dart` | `_idempotencyKey ??=` | `CustomerAccountService.processPayment` | Txn | Atomic payable SQL | B6 | Sticky | Standard | B6 | Low |
| Customer refund settle | refund dialog | `CustomerRefundSettlementUiNotifier` | `CustomerRefundSettlementService` | Txn | Aggregate + return caps | Phase C | **B28 sticky intent** | Refresh ordering fixed in review | B28/B29 pattern tests | Low |
| POS debt settle | `pos_screen.dart` | B24 `prepareKey` | `CustomerAccountService` | Txn | B6 | B6/B24 | Sticky | Standard | B24 | Low |
| Supplier payment | `supplier_payments_screen.dart` | sticky key | `SupplierAccountService` | Txn | Atomic SQL | B8 | Sticky | Standard | B8 | Low |
| Supplier purchase return | `create_supplier_return_dialog.dart` | `supplier_return_draft_provider` | `SupplierReturnService.postPurchaseLinkedReturn` | Txn | Returnable qty SQL | B15 same-key | B15 per key; **reset() clears key** | Sticky within failed retry (test U) | `supplier_purchase_return_idempotency_b15_test.dart` | Cross-dialog intent (P2; caps help) |
| Supplier refund settle | `supplier_refund_settlement_dialog.dart` | B29 notifier | `SupplierRefundSettlementService` | Txn | Credit caps | SR 3.0 | **B29 sticky intent** | SF-03 refresh order | `supplier_refund_settlement_idempotency_b29_test.dart` | Low |
| Purchase save | `purchase_form_screen.dart` | sticky + fingerprint | `PurchaseSaveService` | Txn | Stock/cost | B7 | Sticky | Standard | B7 | Low |
| Expense / other income | dialogs / screens | sticky keys | B18–B23 services | Txn | Ledger | B18–B23 | Sticky | Standard | B18–B23 | Low |
| Opening stock / adjustment | inventory UI | sticky + fingerprint | B20/B21 | Txn | Stock ledger | B20/B21 | Sticky | Standard | B20/B21 | Low |
| POS session open | `SessionOpenDialog` | new UUID in `initState` | `PosSessionOpenService` | Txn | `uq_pos_sessions_one_open` | B25 | Per key; UNIQUE open | AlreadyOpen on second open | `pos_session_open_b25_test.dart` | Reopen new key (P3) |
| POS session close | `SessionCloseDialog` | key regen on input change | `PosSessionCloseService` | Txn | Closed-row replay | B26 | Fingerprint replay | Standard | `pos_session_close_b26_test.dart` | Low |
| Legacy / low reach | — | `PurchasesRepository.delete`, `PosRepository.saveSale` | DAO / legacy | Varies | — | None | **No** | — | — | Not wired from production UI |

---

## 4. Top 5 ranked candidates

### Rank 1 — Customer manual return UI operation-intent idempotency

| Field | Detail |
|-------|--------|
| **Severity** | **P1** |
| **Path** | Returns → manual return flow on `CustomerReturnsScreen` |
| **Evidence** | `customer_returns_screen.dart` L99–126: `_manualReturnIdempotencyKey ??= v4()`; **success calls `_clearManualReturnAttempt()`** (clears key). `ManualReturnService` replays only per key (`manual_return_service.dart` L43–52). `customer_manual_return_idempotency_b10_test.dart` **test 14** proves **two different keys → two returns** and stock +2. |
| **Failure scenario** | User submits manual return; DB commits; user dismisses UI or misses success snackbar; opens the same return dialog again with identical product/qty/price/reason → **new UUID** → second `customer_returns` row and duplicate stock restoration. |
| **Financial / data impact** | Inflated inventory; duplicate return history; distorts analytics and trust in return totals (no purchase invoice cap). |
| **Concurrency** | Same-key races covered by B10; gap is **different keys, same fingerprint**. |
| **Existing protection** | B10 idempotency table; payload fingerprint stored; sticky key **only until success or payload change** (L107–110). |
| **Why insufficient** | No cross-attempt intent map (unlike B28/B29/B27). Service **by design** allows two keys with identical fingerprint (test 14). |
| **Smallest safe scope** | UI-only: `ManualReturnFingerprint` + sticky `prepareReturnKey` map on screen or small helper; clear key only after confirmed success; invalidate on fingerprint change. **No schema change.** |
| **Test strategy** | Notifier/screen tests: reopen after simulated success, post-commit ambiguity, conflict retention, fingerprint change → new key; service replay unchanged. |
| **Schema** | None |
| **Regression risk** | Low if scoped to manual return submit path only |
| **Confidence** | **High** |

### Rank 2 — Customer quick return UI operation-intent idempotency

| Field | Detail |
|-------|--------|
| **Severity** | **P1** (same class as #1; session cash + stock) |
| **Path** | `CustomerReturnsScreen._submitQuickReturn` → `PosSaleService.processQuickReturn` |
| **Evidence** | Parallel pattern L165–196: `_clearQuickReturnAttempt()` on success. `customer_quick_return_idempotency_b9_test.dart` **test 15**: different keys → two returns. |
| **Failure scenario** | Same as #1 for quick (no-invoice) refund path. |
| **Impact** | Duplicate stock movement + duplicate quick-return financial effects tied to POS session reporting. |
| **Scope note** | **Separate milestone** from #1 to keep B30 minimal; same remediation pattern. |
| **Confidence** | **High** |

### Rank 3 — POS sale recorded against closed session

| Field | Detail |
|-------|--------|
| **Severity** | **P2** |
| **Path** | `pos_screen.dart` `_checkout` (L774: reads open session once) → `CartNotifier.checkout` → `PosSaleService.processSale` |
| **Evidence** | `PosSaleService._executeNewSaleInTransaction` inserts invoice with caller-supplied `sessionId` (`pos_provider.dart` L576–577); **no** `is_closed` check in service (grep: no matches in `pos_sale_service.dart`). `PosSessionCloseService` closes session in txn (B26). |
| **Failure scenario** | Stale `sessionId` captured before close (long payment dialog + session closed elsewhere) → sale row attached to **closed** session; session summary / cash reconciliation diverges from operational reality. |
| **Impact** | Session integrity and reporting; not duplicate sale if B27 key holds. |
| **Smallest scope** | Service guard: in sale txn, `SELECT is_closed FROM pos_sessions WHERE id = ?` must be open. |
| **Schema** | None |
| **Confidence** | **Medium** (single-desktop POS reduces likelihood; still real TOCTOU) |

### Rank 4 — Loyalty points over-redemption under concurrent sales

| Field | Detail |
|-------|--------|
| **Severity** | **P2** |
| **Path** | `PosSaleService` → `LoyaltyService.applyPostSalePoints` |
| **Evidence** | `loyalty_service.dart` L102–105: `UPDATE customers SET loyalty_points = MAX(0, loyalty_points + ?)` — no `WHERE loyalty_points >= usedPoints`. UI validates before checkout only. |
| **Failure scenario** | Two concurrent checkouts for same customer redeem more points than balance. |
| **Impact** | Excess discount on one or both sales. |
| **Smallest scope** | Conditional UPDATE or serialize redeem in sale txn. |
| **Schema** | None |
| **Confidence** | **Medium** (requires concurrent writers; sale idempotency does not span two sales) |

### Rank 5 — Supplier purchase return UI operation-intent (cross-dialog)

| Field | Detail |
|-------|--------|
| **Severity** | **P2** |
| **Path** | `showCreateSupplierReturnDialog` (reset on open/close) → `supplier_return_draft_provider.submitReturn` |
| **Evidence** | `create_supplier_return_dialog.dart` L16–22 `reset()`; provider L152–154 clears key on success; B15 test **U** sticky key on **failure retry only**. `SupplierReturnFingerprint` exists. |
| **Failure scenario** | Post-success duplicate **same lines** often blocked by `quantityExceedsReturnable` (`supplier_return_service.dart` L282–287). Gap remains for **concurrent** dual-key before cap updates and ambiguous retry before UI refresh. |
| **Impact** | Stock + supplier credit (when caps allow). |
| **Smallest scope** | Mirror B29 UI intent map (optional follow-on milestone). |
| **Confidence** | **Medium** (mitigated vs refund settlement because returnable qty is re-read in txn) |

---

## 5. Deep analysis — Rank 1 (customer manual return UI operation-intent)

### 5.1 Call graph

```
CustomerReturnsScreen._submitManualReturn (customer_returns_screen.dart)
  → ref.read(manualReturnServiceProvider).processManualReturn(idempotencyKey: …)
      → ManualReturnService.processManualReturn (manual_return_service.dart)
          → customer_manual_return_idempotency_dao (lookup / insert seal)
          → returnsDao.saveCustomerReturnInTransaction (header + items + stock)
```

No alternate production writer for manual returns found in `lib/features`.

### 5.2 Transaction boundaries

- Entire operation runs inside **one** `db.transaction` in `ManualReturnService.processManualReturn`.
- Idempotency row inserted **after** return row + optional `preSealHook` (test hooks).
- Seal race retried up to 8 attempts (same pattern as B5/B15).

### 5.3 Authoritative reads/writes

| Step | Authority |
|------|-----------|
| Product existence | DB read in txn |
| Return header/items | `returnsDao.saveCustomerReturnInTransaction` |
| Stock | Inside save path (return increases stock) |
| Idempotency | `customer_manual_return_idempotency` keyed by **UUID string only** |

### 5.4 UI key lifecycle (gap)

```dart
// customer_returns_screen.dart (abbreviated)
_manualReturnIdempotencyKey ??= _manualReturnUuid.v4();
await manualReturnService.processManualReturn(idempotencyKey: _manualReturnIdempotencyKey!, …);
_clearManualReturnAttempt(); // on success — key discarded
```

- **Payload change:** L107–110 clears key if `ManualReturnPayload` differs — partial intent binding.
- **Dialog reopen / new submission after success:** new key guaranteed → service treats as new operation.
- **Failure / generic catch:** key **retained** (good for same-dialog retry).

### 5.5 Fingerprint (already canonical)

`ManualReturnFingerprint.compute` (`manual_return_fingerprint.dart`) hashes productId, 6dp quantity/unitPrice, normalized reason, userId, approvedByUserId — aligned with service rounding.

### 5.6 Reproduction scenario (concrete)

1. Cashier records manual return: product P, qty 4, price 10, reason "تالف".
2. `processManualReturn` commits with key K1; stock +4.
3. Snackbar not seen (focus loss, overlay, or user closes panel quickly).
4. Cashier repeats the same dialog fields → key K2.
5. **Result:** second return row; stock +4 again; B10 test 14 documents service acceptance.

This is **not** a theoretical race; it is the same **operation-intent / UI lifecycle** class closed by B27–B29.

### 5.7 Concurrency

- Same key + same fingerprint: replay (B10).
- Same key + different fingerprint: conflict.
- **Different keys + same fingerprint:** two commits (test 14) — **the B30 gap**.

### 5.8 Existing tests vs gaps

| Covered | Missing |
|---------|---------|
| Service replay, conflict, seal race (B10) | UI sticky intent across reopen / post-success ambiguity |
| Payload mismatch clears key (screen logic) | Notifier-level test like B29 T11–T16 |

**Confirmed defect class:** UI/service boundary — **not** a missing service txn.

### 5.9 Schema

**No migration required** for recommended option (UI intent map only).

---

## 6. Options and scope (Rank 1)

### Option A — UI sticky operation key by fingerprint (recommended; mirror B28/B29/B27)

- Add `CustomerManualReturnIdempotencyState` (or screen-scoped map): `prepareReturnKey(fingerprintHash, generateUuid)`.
- Compute fingerprint at submit using existing `ManualReturnFingerprint`.
- Clear slot only on **confirmed success** (or explicit “new return” user action).
- Invalidate when fingerprint changes (already partially via `ManualReturnPayload.matches`).

| Criterion | Rating |
|-----------|--------|
| Correctness | High for retry-after-success ambiguity |
| Financial/data safety | Stops duplicate stock inflation |
| Concurrency | Same as B28/B29 (in-memory map; process-death P2 accepted) |
| Migration risk | None |
| Regression risk | Low |
| Scope | Small (1 screen + helper + tests) |
| Testability | High (mirror B29 suite structure) |

### Option B — Service rejects duplicate fingerprint globally

- Before insert, lookup existing idempotency row by **fingerprint hash** (new index or scan).

| Criterion | Rating |
|-----------|--------|
| Correctness | High |
| Migration risk | **Medium** (unique index on fingerprint; conflict rules) |
| Regression risk | Medium (legitimate distinct operations with same fingerprint impossible by definition) |
| Scope | Service + DAO + migration |

### Option C — Persist UI intent map (SharedPreferences / Drift)

- Survive process death.

| Criterion | Rating |
|-----------|--------|
| Correctness | Highest durability |
| Scope | Larger; overlaps B27/B28 accepted non-goals |
| Recommendation | Defer unless product requires kill-after-commit parity |

**Recommendation:** **Option A** — minimal, proven pattern in-repo (B27/B28/B29), no schema change, tests already establish service behavior.

**Do not bundle** quick return (#2) into the same milestone unless explicitly expanded; same pattern but separate entrypoints and `QuickReturnFingerprint` / B9 service.

---

## 7. Recommended B30 scope

**Milestone title (proposed):** Customer manual return UI operation-intent idempotency  

**In scope:**

- `lib/features/returns/screens/customer_returns_screen.dart` (manual return submit path)
- New small UI helper (e.g. `lib/features/returns/customer_manual_return_idempotency.dart`) mirroring B28/B29
- Tests: `test/customer_manual_return_idempotency_b30_test.dart` (or extend B10 UI group with parallel B29 scenarios)

**Out of scope (explicit):**

- B29 supplier refund settlement (closed)
- Quick return UI (#2) — follow-on milestone
- Supplier purchase return UI (#5)
- POS closed-session service guard (#3)
- Loyalty conditional UPDATE (#4)
- Schema / migration changes
- Backend changes to `ManualReturnService` unless design review finds Option A insufficient

---

## 8. Proposed test matrix (Rank 1)

| ID | Scenario | Expected |
|----|----------|----------|
| T1 | Same fingerprint, two submit calls without success clear | Same key |
| T2 | Fingerprint change | New key |
| T3 | Simulated success then reopen/submit same fingerprint | Replay via same key (service mock) |
| T4 | Post-commit success + refresh/invalidate failure | Key retained; retry replays |
| T5 | Idempotency conflict | Key retained; user message |
| T6 | Concurrent double-submit same generation | One service call / replay |
| T7 | Service integration: same key replay | Existing B10 behavior unchanged |
| T8 | Regression: payload mismatch still rotates key | Unchanged |

---

## 9. Schema / migration assessment

**Recommended Option A:** **No schema change.** Reuse `customer_manual_return_idempotency` with existing idempotency keys; only UI stabilizes which UUID is sent.

Option B would require unique constraint on `fingerprint_hash` — **not recommended** for B30 scope.

---

## 10. Regression risks

| Risk | Mitigation |
|------|------------|
| Legitimate back-to-back manual returns (same product, same qty) | After intentional success, design must **clear** intent slot so a **deliberate** second return gets a new key — mirror B29 `clearSettlementKey` on success |
| Stale key on edited form | Fingerprint / payload mismatch must reset key (existing + helper) |
| B10 service tests | Do not change service semantics |

---

## 11. Out-of-scope items

- Git cleanup of unrelated untracked docs/tools
- Rewriting B10 test 14 service semantics (documents intentional dual-key at service layer)
- POS checkout process-death persistence (accepted P2 since B27)
- Invoice partial/full return UI intent (P2; caps mitigate)
- Dead code removal (`PosRepository.saveSale`, purchase delete)
- Markdown trailing whitespace in committed docs

---

## 12. Final recommendation

After B29, the highest **remaining material** gap in the **operation-intent idempotency** family is **customer manual return UI**: the service is replay-safe per key, but the screen **discards the key after every success**, and the test suite **proves** that two keys with the same logical return create two stock mutations.

**Recommended next milestone:** B30 — **Customer manual return UI operation-intent idempotency** (Option A, no schema).

---

## Final verdict

**B30 DISCOVERY READY FOR DESIGN REVIEW**
